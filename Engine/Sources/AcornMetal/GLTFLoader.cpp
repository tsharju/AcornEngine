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
        int* outTextureSize,
        GLTFAnimationContainer* outAnimations,
        GLTFSkinContainer* outSkins
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

        struct alignas(16) DefaultSkinnedVertex {
            float position[3];
            float _pad1;
            float color[4];
            float texCoord[2];
            float _pad2[2];
            float normal[3];
            float _pad3;
            uint16_t joints[4];
            float _padJoints[2];
            float weights[4];
        };

        static_assert(sizeof(DefaultSkinnedVertex) == 96, "DefaultSkinnedVertex size must be 96 bytes");
        static_assert(offsetof(DefaultSkinnedVertex, color) == 16, "color must be at offset 16");
        static_assert(offsetof(DefaultSkinnedVertex, texCoord) == 32, "texCoord must be at offset 32");
        static_assert(offsetof(DefaultSkinnedVertex, normal) == 48, "normal must be at offset 48");
        static_assert(offsetof(DefaultSkinnedVertex, joints) == 64, "joints must be at offset 64");
        static_assert(offsetof(DefaultSkinnedVertex, weights) == 80, "weights must be at offset 80");

        // First, load all meshes and primitives in local coordinates (no transform baking)
        std::vector<size_t> meshPrimitiveOffsets(asset->meshes.size());
        std::vector<size_t> meshPrimitiveCounts(asset->meshes.size());
        size_t currentOffset = 0;
        
        auto loadPrimitive = [&](const fastgltf::Primitive& primitive) -> AcornMetalMesh* {
            auto* positionAccessor = asset->accessors.data() + primitive.findAttribute("POSITION")->accessorIndex;
            size_t vertexCount = positionAccessor->count;

            auto jointsAttr = primitive.findAttribute("JOINTS_0");
            auto weightsAttr = primitive.findAttribute("WEIGHTS_0");
            bool isSkinnedPrimitive = (jointsAttr != primitive.attributes.end()) && (weightsAttr != primitive.attributes.end());
            
            // Indices
            std::vector<uint32_t> indices;
            if (primitive.indicesAccessor.has_value()) {
                auto& indexAccessor = asset->accessors[primitive.indicesAccessor.value()];
                indices.reserve(indexAccessor.count);
                fastgltf::iterateAccessor<std::uint32_t>(asset.get(), indexAccessor, [&](std::uint32_t idx) {
                    indices.push_back(idx);
                });
            }

            MTL::Buffer* vertexBuffer = nullptr;
            MTL::Buffer* indexBuffer = nullptr;
            if (!indices.empty()) {
                indexBuffer = device->newBuffer(indices.data(), indices.size() * sizeof(uint32_t), MTL::ResourceStorageModeShared);
            }

            if (isSkinnedPrimitive) {
                std::vector<DefaultSkinnedVertex> vertices(vertexCount);

                fastgltf::iterateAccessorWithIndex<fastgltf::math::fvec3>(asset.get(), *positionAccessor, [&](fastgltf::math::fvec3 pos, size_t idx) {
                    vertices[idx].position[0] = pos.x();
                    vertices[idx].position[1] = pos.y();
                    vertices[idx].position[2] = pos.z();
                    vertices[idx]._pad1 = 0.0f;
                    vertices[idx].color[0] = 1.0f; vertices[idx].color[1] = 1.0f; vertices[idx].color[2] = 1.0f; vertices[idx].color[3] = 1.0f;
                    vertices[idx].texCoord[0] = 0.0f; vertices[idx].texCoord[1] = 0.0f;
                    vertices[idx]._pad2[0] = 0.0f; vertices[idx]._pad2[1] = 0.0f;
                    vertices[idx].normal[0] = 0.0f; vertices[idx].normal[1] = 0.0f; vertices[idx].normal[2] = 1.0f;
                    vertices[idx]._pad3 = 0.0f;
                    vertices[idx].joints[0] = 0; vertices[idx].joints[1] = 0; vertices[idx].joints[2] = 0; vertices[idx].joints[3] = 0;
                    vertices[idx]._padJoints[0] = 0.0f; vertices[idx]._padJoints[1] = 0.0f;
                    vertices[idx].weights[0] = 0.0f; vertices[idx].weights[1] = 0.0f; vertices[idx].weights[2] = 0.0f; vertices[idx].weights[3] = 0.0f;
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

                auto& jointsAccessor = asset->accessors[jointsAttr->accessorIndex];
                if (jointsAccessor.componentType == fastgltf::ComponentType::UnsignedByte) {
                    fastgltf::iterateAccessorWithIndex<fastgltf::math::u8vec4>(asset.get(), jointsAccessor, [&](fastgltf::math::u8vec4 j, size_t idx) {
                        vertices[idx].joints[0] = j.x();
                        vertices[idx].joints[1] = j.y();
                        vertices[idx].joints[2] = j.z();
                        vertices[idx].joints[3] = j.w();
                    });
                } else if (jointsAccessor.componentType == fastgltf::ComponentType::UnsignedShort) {
                    fastgltf::iterateAccessorWithIndex<fastgltf::math::u16vec4>(asset.get(), jointsAccessor, [&](fastgltf::math::u16vec4 j, size_t idx) {
                        vertices[idx].joints[0] = j.x();
                        vertices[idx].joints[1] = j.y();
                        vertices[idx].joints[2] = j.z();
                        vertices[idx].joints[3] = j.w();
                    });
                }

                auto& weightsAccessor = asset->accessors[weightsAttr->accessorIndex];
                fastgltf::iterateAccessorWithIndex<fastgltf::math::fvec4>(asset.get(), weightsAccessor, [&](fastgltf::math::fvec4 w, size_t idx) {
                    vertices[idx].weights[0] = w.x();
                    vertices[idx].weights[1] = w.y();
                    vertices[idx].weights[2] = w.z();
                    vertices[idx].weights[3] = w.w();
                });

                vertexBuffer = device->newBuffer(vertices.data(), vertices.size() * sizeof(DefaultSkinnedVertex), MTL::ResourceStorageModeShared);
                AcornMetalMesh* resultMesh = new AcornMetalMesh(device, vertexCount, vertexBuffer, indexBuffer, indices.size());
                resultMesh->setIsSkinned(true);
                vertexBuffer->release();
                if (indexBuffer) indexBuffer->release();
                return resultMesh;
            } else {
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

                vertexBuffer = device->newBuffer(vertices.data(), vertices.size() * sizeof(DefaultVertex), MTL::ResourceStorageModeShared);
                AcornMetalMesh* resultMesh = new AcornMetalMesh(device, vertexCount, vertexBuffer, indexBuffer, indices.size());
                resultMesh->setIsSkinned(false);
                
#ifndef NDEBUG
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
            }
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
                nodeData.skinIndex = node.skinIndex.has_value() ? static_cast<int>(node.skinIndex.value()) : -1;
                
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
                        virtualNode.skinIndex = nodeData.skinIndex;
                        
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
                nodeData.skinIndex = -1;
                
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

        // Extract animations if requested
        if (outAnimations) {
            outAnimations->animationCount = 0;
            outAnimations->animations = nullptr;
            
            if (!asset->animations.empty()) {
                size_t numAnims = asset->animations.size();
                outAnimations->animations = new GLTFAnimationData[numAnims]();
                outAnimations->animationCount = static_cast<int>(numAnims);
                
                for (size_t a = 0; a < numAnims; ++a) {
                    auto& gltfAnim = asset->animations[a];
                    auto& animData = outAnimations->animations[a];
                    
                    if (!gltfAnim.name.empty()) {
                        strncpy(animData.name, gltfAnim.name.c_str(), sizeof(animData.name) - 1);
                        animData.name[sizeof(animData.name) - 1] = '\0';
                    } else {
                        snprintf(animData.name, sizeof(animData.name), "animation_%zu", a);
                    }
                    
                    animData.duration = 0.0f;
                    
                    std::vector<GLTFChannelData> validChannels;
                    validChannels.reserve(gltfAnim.channels.size());
                    
                    for (size_t c = 0; c < gltfAnim.channels.size(); ++c) {
                        auto& gltfChannel = gltfAnim.channels[c];
                        if (gltfChannel.samplerIndex >= gltfAnim.samplers.size()) continue;
                        
                        int targetNode = -1;
                        if (gltfChannel.nodeIndex.has_value()) {
                            size_t nodeIdx = gltfChannel.nodeIndex.value();
                            if (nodeIdx < gltfNodeToReturnedIndex.size()) {
                                targetNode = gltfNodeToReturnedIndex[nodeIdx];
                            }
                        }
                        if (targetNode < 0) continue;
                        
                        auto& sampler = gltfAnim.samplers[gltfChannel.samplerIndex];
                        if (sampler.inputAccessor >= asset->accessors.size() ||
                            sampler.outputAccessor >= asset->accessors.size()) {
                            continue;
                        }
                        
                        auto& inputAccessor = asset->accessors[sampler.inputAccessor];
                        auto& outputAccessor = asset->accessors[sampler.outputAccessor];
                        
                        // Extract timestamps
                        std::vector<float> timestamps;
                        timestamps.reserve(inputAccessor.count);
                        fastgltf::iterateAccessor<float>(asset.get(), inputAccessor, [&](float t) {
                            timestamps.push_back(t);
                            if (t > animData.duration) {
                                animData.duration = t;
                            }
                        });
                        
                        if (timestamps.empty()) continue;
                        
                        uint8_t interp = 0;
                        if (sampler.interpolation == fastgltf::AnimationInterpolation::Step) {
                            interp = 1;
                        } else if (sampler.interpolation == fastgltf::AnimationInterpolation::CubicSpline) {
                            interp = 2;
                        }
                        
                        uint8_t pathType = 0;
                        std::vector<float> values;
                        
                        if (gltfChannel.path == fastgltf::AnimationPath::Translation) {
                            pathType = 1;
                            values.reserve(outputAccessor.count * 3);
                            fastgltf::iterateAccessor<fastgltf::math::fvec3>(asset.get(), outputAccessor, [&](fastgltf::math::fvec3 v) {
                                values.push_back(v.x());
                                values.push_back(v.y());
                                values.push_back(v.z());
                            });
                        } else if (gltfChannel.path == fastgltf::AnimationPath::Rotation) {
                            pathType = 2;
                            values.reserve(outputAccessor.count * 4);
                            fastgltf::iterateAccessor<fastgltf::math::fquat>(asset.get(), outputAccessor, [&](fastgltf::math::fquat q) {
                                values.push_back(q.x());
                                values.push_back(q.y());
                                values.push_back(q.z());
                                values.push_back(q.w());
                            });
                        } else if (gltfChannel.path == fastgltf::AnimationPath::Scale) {
                            pathType = 3;
                            values.reserve(outputAccessor.count * 3);
                            fastgltf::iterateAccessor<fastgltf::math::fvec3>(asset.get(), outputAccessor, [&](fastgltf::math::fvec3 v) {
                                values.push_back(v.x());
                                values.push_back(v.y());
                                values.push_back(v.z());
                            });
                        } else if (gltfChannel.path == fastgltf::AnimationPath::Weights) {
                            pathType = 4;
                            values.reserve(outputAccessor.count);
                            fastgltf::iterateAccessor<float>(asset.get(), outputAccessor, [&](float w) {
                                values.push_back(w);
                            });
                        }
                        
                        if (pathType == 0 || values.empty()) continue;
                        
                        GLTFChannelData channelData = {};
                        channelData.nodeIndex = targetNode;
                        channelData.path = pathType;
                        channelData.interpolation = interp;
                        channelData.keyframeCount = static_cast<int>(timestamps.size());
                        channelData.valuesPerKeyframe = static_cast<int>(values.size() / timestamps.size());
                        
                        float* tsCopy = new float[timestamps.size()];
                        std::copy(timestamps.begin(), timestamps.end(), tsCopy);
                        channelData.timestamps = tsCopy;
                        
                        float* valCopy = new float[values.size()];
                        std::copy(values.begin(), values.end(), valCopy);
                        channelData.values = valCopy;
                        
                        validChannels.push_back(channelData);
                    }
                    
                    animData.channelCount = static_cast<int>(validChannels.size());
                    if (!validChannels.empty()) {
                        animData.channels = new GLTFChannelData[validChannels.size()];
                        std::copy(validChannels.begin(), validChannels.end(), animData.channels);
                    } else {
                        animData.channels = nullptr;
                    }
                }
            }
        }

        // Extract skins if requested
        if (outSkins && !asset->skins.empty()) {
            outSkins->skinCount = static_cast<int>(asset->skins.size());
            outSkins->skins = new GLTFSkinData[asset->skins.size()];
            
            for (size_t s = 0; s < asset->skins.size(); ++s) {
                auto& skin = asset->skins[s];
                auto& skinData = outSkins->skins[s];
                
                strncpy(skinData.name, skin.name.c_str(), sizeof(skinData.name) - 1);
                skinData.name[sizeof(skinData.name) - 1] = '\0';
                
                skinData.jointCount = static_cast<int>(skin.joints.size());
                skinData.jointNodeIndices = new int[skin.joints.size()];
                for (size_t j = 0; j < skin.joints.size(); ++j) {
                    size_t gltfNodeIdx = skin.joints[j];
                    skinData.jointNodeIndices[j] = (gltfNodeIdx < gltfNodeToReturnedIndex.size()) 
                        ? gltfNodeToReturnedIndex[gltfNodeIdx] 
                        : static_cast<int>(gltfNodeIdx);
                }
                
                skinData.inverseBindMatrices = new float[skin.joints.size() * 16];
                if (skin.inverseBindMatrices.has_value()) {
                    auto& ibmAccessor = asset->accessors[skin.inverseBindMatrices.value()];
                    fastgltf::iterateAccessorWithIndex<fastgltf::math::fmat4x4>(asset.get(), ibmAccessor, [&](fastgltf::math::fmat4x4 mat, size_t idx) {
                        if (idx < skin.joints.size()) {
                            float* dst = &skinData.inverseBindMatrices[idx * 16];
                            const auto* src = mat.data();
                            std::copy(src, src + 16, dst);
                        }
                    });
                } else {
                    for (size_t j = 0; j < skin.joints.size(); ++j) {
                        float* dst = &skinData.inverseBindMatrices[j * 16];
                        for (int k = 0; k < 16; ++k) dst[k] = 0.0f;
                        dst[0] = dst[5] = dst[10] = dst[15] = 1.0f;
                    }
                }
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
        int* outTextureSize,
        GLTFAnimationContainer* outAnimations,
        GLTFSkinContainer* outSkins
    ) {
        std::vector<GLTFNodeData> loadedNodes;
        std::vector<AcornMetalMesh*> loadedMeshes = load(std::string(path), devicePtr, loadedNodes, outTextureData, outTextureSize, outAnimations, outSkins);
        
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

    void GLTFLoader::freeAnimationContainer(GLTFAnimationContainer* container) {
        if (!container || !container->animations) return;
        for (int i = 0; i < container->animationCount; ++i) {
            auto& anim = container->animations[i];
            if (anim.channels) {
                for (int j = 0; j < anim.channelCount; ++j) {
                    auto& ch = anim.channels[j];
                    delete[] ch.timestamps;
                    delete[] ch.values;
                }
                delete[] anim.channels;
            }
        }
        delete[] container->animations;
        container->animations = nullptr;
        container->animationCount = 0;
    }

    void GLTFLoader::freeSkinContainer(GLTFSkinContainer* container) {
        if (!container || !container->skins) return;
        for (int i = 0; i < container->skinCount; ++i) {
            auto& skin = container->skins[i];
            delete[] skin.jointNodeIndices;
            delete[] skin.inverseBindMatrices;
        }
        delete[] container->skins;
        container->skins = nullptr;
        container->skinCount = 0;
    }
}
