#include "GLTFLoader.hpp"
#include <Metal/Metal.hpp>
#include <fastgltf/core.hpp>
#include <fastgltf/types.hpp>
#include <fastgltf/tools.hpp>
#include <iostream>

namespace Acorn {
    std::vector<AcornMetalMesh*> GLTFLoader::load(const std::string& path, void* devicePtr) {
        MTL::Device* device = (MTL::Device*)devicePtr;
        std::vector<AcornMetalMesh*> meshes;
        
        fastgltf::Parser parser(fastgltf::Extensions::None);
        
        auto data = fastgltf::GltfDataBuffer::FromPath(path);
        if (data.error() != fastgltf::Error::None) {
            std::cerr << "Failed to load file: " << path << std::endl;
            return meshes;
        }
        
        auto asset = parser.loadGltfBinary(data.get(), path, fastgltf::Options::LoadExternalBuffers);
        if (asset.error() != fastgltf::Error::None) {
            // fallback to parsing as standard gltf if binary fails
            asset = parser.loadGltfJson(data.get(), path, fastgltf::Options::LoadExternalBuffers);
            if (asset.error() != fastgltf::Error::None) {
                std::cerr << "Failed to parse gltf: " << path << std::endl;
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
        
        struct DefaultVertex {
            float position[3];
            float color[4];
            float texCoord[2];
            float normal[3];
        };
        
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

        meshes.push_back(resultMesh);
        return meshes;
    }
}
