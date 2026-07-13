#include "GLTFLoader.hpp"
#include <Metal/Metal.hpp>
#include <fastgltf/core.hpp>
#include <fastgltf/types.hpp>
#include <fastgltf/tools.hpp>
#include <iostream>
#include <filesystem>
#include <cstddef>
#include <cstring>
#include <cstdio>
#include <algorithm>

namespace Acorn {
    std::vector<AcornMetalMesh*> GLTFLoader::load(
        const std::string& path, 
        void* devicePtr, 
        std::vector<GLTFNodeData>& outNodes,
        const void** outTextureData, 
        int* outTextureSize
    ) {
        MTL::Device* device = (MTL::Device*)devicePtr;
        std::vector<AcornMetalMesh*> meshes;
        
        if (outTextureData) *outTextureData = nullptr;
        if (outTextureSize) *outTextureSize = 0;
        
        fastgltf::Parser parser(fastgltf::Extensions::None);
        
        auto data = fastgltf::GltfDataBuffer::FromPath(path);
        if (data.error() != fastgltf::Error::None) {
            std::cerr << "Failed to load file: " << path << std::endl;
            return meshes;
        }
        
        auto directory = std::filesystem::path(path).parent_path();
        
        auto asset = parser.loadGltfBinary(data.get(), directory, fastgltf::Options::LoadExternalBuffers);
        if (asset.error() != fastgltf::Error::None) {
            auto binaryError = asset.error();
            // fallback to parsing as standard gltf if binary fails
            asset = parser.loadGltfJson(data.get(), directory, fastgltf::Options::LoadExternalBuffers);
            if (asset.error() != fastgltf::Error::None) {
                std::cerr << "Failed to parse gltf: " << path 
                          << " (Binary error: " << fastgltf::getErrorName(binaryError) 
                          << ", JSON error: " << fastgltf::getErrorName(asset.error()) << ")" << std::endl;
                return meshes;
            }
        }
        
        struct alignas(16) DefaultVertex {
            float position[3];
            float _pad1; // Pad position to 16 bytes
            float color[4];
            float texCoord[2];
            float _pad2[2]; // Pad normal to 16-byte boundary (offset 48)
            float normal[3];
            float _pad3; // Pad normal to 16 bytes (total 64 bytes)
        };
        
        static_assert(sizeof(DefaultVertex) == 64, "DefaultVertex size must be 64 bytes");
        static_assert(offsetof(DefaultVertex, color) == 16, "color must be at offset 16");
        static_assert(offsetof(DefaultVertex, texCoord) == 32, "texCoord must be at offset 32");
        static_assert(offsetof(DefaultVertex, normal) == 48, "normal must be at offset 48");

        // First, load all meshes and primitives in local coordinates (no transform baking)
        std::vector<size_t> meshPrimitiveOffsets(asset->meshes.size());
        std::vector<size_t> meshPrimitiveCounts(asset->meshes.size());
        size_t currentOffset = 0;
        
        auto loadPrimitive = [&](const fastgltf::Primitive& primitive) -> AcornMetalMesh* {
            auto* positionAccessor = asset->accessors.data() + primitive.findAttribute("POSITION")->accessorIndex;
            size_t vertexCount = positionAccessor->count;
            
            std::vector<DefaultVertex> vertices(vertexCount);
            
            fastgltf::iterateAccessorWithIndex<fastgltf::math::fvec3>(asset.get(), *positionAccessor, [&](fastgltf::math::fvec3 pos, size_t idx) {
                vertices[idx].position[0] = pos.x();
                vertices[idx].position[1] = pos.y();
                vertices[idx].position[2] = pos.z();
                
                // Defaults
                vertices[idx].color[0] = 1.0f; vertices[idx].color[1] = 1.0f; vertices[idx].color[2] = 1.0f; vertices[idx].color[3] = 1.0f;
                vertices[idx].texCoord[0] = 0.0f; vertices[idx].texCoord[1] = 0.0f;
                vertices[idx].normal[0] = 0.0f; vertices[idx].normal[1] = 0.0f; vertices[idx].normal[2] = 1.0f;
            });
            
            if (auto normalAttr = primitive.findAttribute("NORMAL"); normalAttr != primitive.attributes.end()) {
                fastgltf::iterateAccessorWithIndex<fastgltf::math::fvec3>(asset.get(), asset->accessors[normalAttr->accessorIndex], [&](fastgltf::math::fvec3 normal, size_t idx) {
                    vertices[idx].normal[0] = normal.x();
                    vertices[idx].normal[1] = normal.y();
                    vertices[idx].normal[2] = normal.z();
                });
            }
            
            if (auto texCoordAttr = primitive.findAttribute("TEXCOORD_0"); texCoordAttr != primitive.attributes.end()) {
                fastgltf::iterateAccessorWithIndex<fastgltf::math::fvec2>(asset.get(), asset->accessors[texCoordAttr->accessorIndex], [&](fastgltf::math::fvec2 texCoord, size_t idx) {
                    vertices[idx].texCoord[0] = texCoord.x();
                    vertices[idx].texCoord[1] = texCoord.y();
                });
            }
            
            // Indices
            std::vector<uint32_t> indices;
            if (primitive.indicesAccessor.has_value()) {
                auto& indexAccessor = asset->accessors[primitive.indicesAccessor.value()];
                indices.reserve(indexAccessor.count);
                fastgltf::iterateAccessor<std::uint32_t>(asset.get(), indexAccessor, [&](std::uint32_t idx) {
                    indices.push_back(idx);
                });
            }
            
            MTL::Buffer* vertexBuffer = device->newBuffer(vertices.data(), vertices.size() * sizeof(DefaultVertex), MTL::ResourceStorageModeShared);
            MTL::Buffer* indexBuffer = nullptr;
            if (!indices.empty()) {
                indexBuffer = device->newBuffer(indices.data(), indices.size() * sizeof(uint32_t), MTL::ResourceStorageModeShared);
            }
            
            AcornMetalMesh* resultMesh = new AcornMetalMesh(device, vertexCount, vertexBuffer, indexBuffer, indices.size());
            
#ifndef NDEBUG
            // Copy debug data
            std::vector<float> debugVerts;
            debugVerts.reserve(vertexCount * 3);
            for (const auto& v : vertices) {
                debugVerts.push_back(v.position[0]);
                debugVerts.push_back(v.position[1]);
                debugVerts.push_back(v.position[2]);
            }
            resultMesh->setDebugVertexData(debugVerts.data(), debugVerts.size());
            resultMesh->setDebugIndexData(indices.data(), indices.size());
#endif

            vertexBuffer->release();
            if (indexBuffer) indexBuffer->release();
            
            return resultMesh;
        };

        for (size_t i = 0; i < asset->meshes.size(); ++i) {
            auto& gltfMesh = asset->meshes[i];
            meshPrimitiveOffsets[i] = currentOffset;
            meshPrimitiveCounts[i] = gltfMesh.primitives.size();
            for (auto& primitive : gltfMesh.primitives) {
                AcornMetalMesh* mesh = loadPrimitive(primitive);
                meshes.push_back(mesh);
                currentOffset++;
            }
        }

        // Recursively traverse scene node hierarchy to collect nodes
        std::vector<int> gltfNodeToReturnedIndex(asset->nodes.size(), -1);
        
        auto sceneIndex = asset->defaultScene.value_or(0);
        if (sceneIndex < asset->scenes.size()) {
            auto& scene = asset->scenes[sceneIndex];
            
            auto traverseNode = [&](auto& self, size_t nodeIndex, int returnedParentIndex) -> void {
                auto& node = asset->nodes[nodeIndex];
                
                GLTFNodeData nodeData = {};
                strncpy(nodeData.name, node.name.c_str(), sizeof(nodeData.name) - 1);
                nodeData.name[sizeof(nodeData.name) - 1] = '\0';
                nodeData.parentIndex = returnedParentIndex;
                nodeData.meshIndex = -1;
                
                fastgltf::math::fvec3 translation(0.0f);
                fastgltf::math::fquat rotation(0.0f, 0.0f, 0.0f, 1.0f);
                fastgltf::math::fvec3 scale(1.0f);
                
                if (const auto* pTRS = std::get_if<fastgltf::TRS>(&node.transform)) {
                    translation = pTRS->translation;
                    rotation = pTRS->rotation;
                    scale = pTRS->scale;
                } else if (const auto* pMatrix = std::get_if<fastgltf::math::fmat4x4>(&node.transform)) {
                    fastgltf::math::decomposeTransformMatrix(*pMatrix, scale, rotation, translation);
                }
                
                nodeData.translation[0] = translation.x();
                nodeData.translation[1] = translation.y();
                nodeData.translation[2] = translation.z();
                
                nodeData.rotation[0] = rotation.x();
                nodeData.rotation[1] = rotation.y();
                nodeData.rotation[2] = rotation.z();
                nodeData.rotation[3] = rotation.w();
                
                nodeData.scale[0] = scale.x();
                nodeData.scale[1] = scale.y();
                nodeData.scale[2] = scale.z();
                
                int currentReturnedIndex = static_cast<int>(outNodes.size());
                gltfNodeToReturnedIndex[nodeIndex] = currentReturnedIndex;
                
                if (node.meshIndex.has_value()) {
                    size_t meshIdx = node.meshIndex.value();
                    size_t offset = meshPrimitiveOffsets[meshIdx];
                    size_t count = meshPrimitiveCounts[meshIdx];
                    
                    if (count > 0) {
                        nodeData.meshIndex = static_cast<int>(offset);
                    }
                    
                    outNodes.push_back(nodeData);
                    
                    // Create virtual child nodes for subsequent primitives
                    for (size_t p = 1; p < count; ++p) {
                        GLTFNodeData virtualNode = {};
                        snprintf(virtualNode.name, sizeof(virtualNode.name), "%s_primitive_%zu", node.name.c_str(), p);
                        virtualNode.parentIndex = currentReturnedIndex;
                        virtualNode.meshIndex = static_cast<int>(offset + p);
                        
                        virtualNode.translation[0] = 0.0f; virtualNode.translation[1] = 0.0f; virtualNode.translation[2] = 0.0f;
                        virtualNode.rotation[0] = 0.0f; virtualNode.rotation[1] = 0.0f; virtualNode.rotation[2] = 0.0f; virtualNode.rotation[3] = 1.0f;
                        virtualNode.scale[0] = 1.0f; virtualNode.scale[1] = 1.0f; virtualNode.scale[2] = 1.0f;
                        
                        outNodes.push_back(virtualNode);
                    }
                } else {
                    outNodes.push_back(nodeData);
                }
                
                for (auto childIndex : node.children) {
                    self(self, childIndex, currentReturnedIndex);
                }
            };
            
            for (auto rootNodeIndex : scene.nodeIndices) {
                traverseNode(traverseNode, rootNodeIndex, -1);
            }
        }
        
        // Fallback: if no nodes were populated but we have meshes, create flat nodes
        if (outNodes.empty() && !meshes.empty()) {
            for (size_t i = 0; i < meshes.size(); ++i) {
                GLTFNodeData nodeData = {};
                snprintf(nodeData.name, sizeof(nodeData.name), "mesh_node_%zu", i);
                nodeData.parentIndex = -1;
                nodeData.meshIndex = static_cast<int>(i);
                
                nodeData.translation[0] = 0.0f; nodeData.translation[1] = 0.0f; nodeData.translation[2] = 0.0f;
                nodeData.rotation[0] = 0.0f; nodeData.rotation[1] = 0.0f; nodeData.rotation[2] = 0.0f; nodeData.rotation[3] = 1.0f;
                nodeData.scale[0] = 1.0f; nodeData.scale[1] = 1.0f; nodeData.scale[2] = 1.0f;
                
                outNodes.push_back(nodeData);
            }
        }

        // Extract texture data if requested
        if (outTextureData && outTextureSize) {
            const void* texBytes = nullptr;
            size_t texSize = 0;
            
            if (!asset->images.empty()) {
                auto& image = asset->images[0];
                
                if (auto* bufferViewSource = std::get_if<fastgltf::sources::BufferView>(&image.data)) {
                    auto& bufferView = asset->bufferViews[bufferViewSource->bufferViewIndex];
                    auto& buffer = asset->buffers[bufferView.bufferIndex];
                    
                    if (auto* arr = std::get_if<fastgltf::sources::Array>(&buffer.data)) {
                        texBytes = arr->bytes.data() + bufferView.byteOffset;
                        texSize = bufferView.byteLength;
                    } else if (auto* vec = std::get_if<fastgltf::sources::Vector>(&buffer.data)) {
                        texBytes = vec->bytes.data() + bufferView.byteOffset;
                        texSize = bufferView.byteLength;
                    } else if (auto* byteView = std::get_if<fastgltf::sources::ByteView>(&buffer.data)) {
                        texBytes = byteView->bytes.data() + bufferView.byteOffset;
                        texSize = bufferView.byteLength;
                    }
                } else if (auto* vec = std::get_if<fastgltf::sources::Vector>(&image.data)) {
                    texBytes = vec->bytes.data();
                    texSize = vec->bytes.size();
                } else if (auto* arr = std::get_if<fastgltf::sources::Array>(&image.data)) {
                    texBytes = arr->bytes.data();
                    texSize = arr->bytes.size();
                }
            }
            
            if (texBytes && texSize > 0) {
                void* copy = malloc(texSize);
                memcpy(copy, texBytes, texSize);
                *outTextureData = copy;
                *outTextureSize = static_cast<int>(texSize);
            }
        }

        return meshes;
    }

    int GLTFLoader::loadRaw(
        const char* path, 
        void* devicePtr, 
        void** outMeshes, 
        int maxMeshes, 
        GLTFNodeData* outNodes, 
        int maxNodes, 
        int* outNodeCount,
        const void** outTextureData, 
        int* outTextureSize
    ) {
        std::vector<GLTFNodeData> loadedNodes;
        std::vector<AcornMetalMesh*> loadedMeshes = load(std::string(path), devicePtr, loadedNodes, outTextureData, outTextureSize);
        
        int meshCount = std::min(static_cast<int>(loadedMeshes.size()), maxMeshes);
        for (int i = 0; i < meshCount; ++i) {
            outMeshes[i] = loadedMeshes[i];
        }
        
        int nodeCount = std::min(static_cast<int>(loadedNodes.size()), maxNodes);
        for (int i = 0; i < nodeCount; ++i) {
            outNodes[i] = loadedNodes[i];
        }
        if (outNodeCount) {
            *outNodeCount = nodeCount;
        }
        
        return meshCount;
    }
}
