#include "GLTFLoader.hpp"
#include <Metal/Metal.hpp>
#include <fastgltf/core.hpp>
#include <fastgltf/types.hpp>
#include <fastgltf/tools.hpp>
#include <iostream>
#include <filesystem>
#include <cstddef>

namespace Acorn {
    std::vector<AcornMetalMesh*> GLTFLoader::load(const std::string& path, void* devicePtr, const void** outTextureData, int* outTextureSize) {
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
        
        // For simplicity, we just extract the first primitive of the first mesh.
        // In a real engine, we'd iterate and create hierarchy.
        if (asset->meshes.empty()) {
            return meshes;
        }
        
        auto& gltfMesh = asset->meshes[0];
        if (gltfMesh.primitives.empty()) {
            return meshes;
        }
        
        auto& primitive = gltfMesh.primitives[0];
        
        // Create vertex buffer
        // Since we want dynamic descriptors, we ideally create interleaved buffers or use the buffer views directly.
        // fastgltf gives us buffer views. We can map the fastgltf buffer directly into a MTLBuffer.
        
        // For this simplified implementation, we will manually build an interleaved vertex buffer
        // so it matches the default Shaders.metal if possible, or construct the buffer dynamically.
        // Let's use fastgltf::iterateAccessor to build a packed buffer.
        
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
        
        // We will fallback to building DefaultVertex array to ensure it works immediately with Renderer
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

        meshes.push_back(resultMesh);
        return meshes;
    }

    int GLTFLoader::loadRaw(const char* path, void* devicePtr, void** outMeshes, int maxMeshes, const void** outTextureData, int* outTextureSize) {
        std::vector<AcornMetalMesh*> loaded = load(std::string(path), devicePtr, outTextureData, outTextureSize);
        int count = std::min(static_cast<int>(loaded.size()), maxMeshes);
        for (int i = 0; i < count; ++i) {
            outMeshes[i] = loaded[i];
        }
        return count;
    }
}
