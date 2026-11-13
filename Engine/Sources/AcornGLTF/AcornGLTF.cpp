#include "AcornGLTF/AcornGLTF.h"

#include <fastgltf/core.hpp>
#include <fastgltf/tools.hpp>
#include <fastgltf/types.hpp>

#include <algorithm>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

static_assert(sizeof(AcornGLTFVertex) == 64, "AcornGLTFVertex size must be 64 bytes");
static_assert(offsetof(AcornGLTFVertex, color) == 16, "color must be at offset 16");
static_assert(offsetof(AcornGLTFVertex, texCoord) == 32, "texCoord must be at offset 32");
static_assert(offsetof(AcornGLTFVertex, normal) == 48, "normal must be at offset 48");

static_assert(sizeof(AcornGLTFSkinnedVertex) == 80, "AcornGLTFSkinnedVertex size must be 80 bytes");
static_assert(offsetof(AcornGLTFSkinnedVertex, position) == 0, "position at 0");
static_assert(offsetof(AcornGLTFSkinnedVertex, color) == 16, "color at 16");
static_assert(offsetof(AcornGLTFSkinnedVertex, texCoord) == 32, "texCoord at 32");
static_assert(offsetof(AcornGLTFSkinnedVertex, joints) == 40, "joints at 40");
static_assert(offsetof(AcornGLTFSkinnedVertex, normal) == 48, "normal at 48");
static_assert(offsetof(AcornGLTFSkinnedVertex, weights) == 64, "weights at 64");

namespace {

AcornGLTFMeshData extractPrimitive(const fastgltf::Asset& asset, const fastgltf::Primitive& primitive) {
    AcornGLTFMeshData meshData = {};
    auto posAttr = primitive.findAttribute("POSITION");
    if (posAttr == primitive.attributes.end()) {
        return meshData;
    }

    const auto& positionAccessor = asset.accessors[posAttr->accessorIndex];
    const size_t vertexCount = positionAccessor.count;
    if (vertexCount == 0) {
        return meshData;
    }

    const auto jointsAttr = primitive.findAttribute("JOINTS_0");
    const auto weightsAttr = primitive.findAttribute("WEIGHTS_0");
    const bool isSkinnedPrimitive =
        (jointsAttr != primitive.attributes.end()) && (weightsAttr != primitive.attributes.end());

    std::vector<uint32_t> indices;
    if (primitive.indicesAccessor.has_value()) {
        const auto& indexAccessor = asset.accessors[primitive.indicesAccessor.value()];
        indices.reserve(indexAccessor.count);
        fastgltf::iterateAccessor<std::uint32_t>(asset, indexAccessor, [&](std::uint32_t idx) {
            indices.push_back(idx);
        });
    }

    if (!indices.empty()) {
        meshData.indices = new uint32_t[indices.size()];
        std::copy(indices.begin(), indices.end(), meshData.indices);
        meshData.indexCount = static_cast<uint32_t>(indices.size());
    }

    meshData.vertexCount = static_cast<uint32_t>(vertexCount);
    meshData.isSkinned = isSkinnedPrimitive;

    if (isSkinnedPrimitive) {
        auto* vertices = new AcornGLTFSkinnedVertex[vertexCount]();
        fastgltf::iterateAccessorWithIndex<fastgltf::math::fvec3>(
            asset, positionAccessor, [&](fastgltf::math::fvec3 pos, size_t idx) {
                vertices[idx].position[0] = pos.x();
                vertices[idx].position[1] = pos.y();
                vertices[idx].position[2] = pos.z();
                vertices[idx].color[0] = 1.0f;
                vertices[idx].color[1] = 1.0f;
                vertices[idx].color[2] = 1.0f;
                vertices[idx].color[3] = 1.0f;
                vertices[idx].normal[2] = 1.0f;
            });

        if (auto normalAttr = primitive.findAttribute("NORMAL"); normalAttr != primitive.attributes.end()) {
            fastgltf::iterateAccessorWithIndex<fastgltf::math::fvec3>(
                asset, asset.accessors[normalAttr->accessorIndex],
                [&](fastgltf::math::fvec3 normal, size_t idx) {
                    vertices[idx].normal[0] = normal.x();
                    vertices[idx].normal[1] = normal.y();
                    vertices[idx].normal[2] = normal.z();
                });
        }

        if (auto texCoordAttr = primitive.findAttribute("TEXCOORD_0"); texCoordAttr != primitive.attributes.end()) {
            fastgltf::iterateAccessorWithIndex<fastgltf::math::fvec2>(
                asset, asset.accessors[texCoordAttr->accessorIndex],
                [&](fastgltf::math::fvec2 uv, size_t idx) {
                    vertices[idx].texCoord[0] = uv.x();
                    vertices[idx].texCoord[1] = uv.y();
                });
        }

        const auto& jointsAccessor = asset.accessors[jointsAttr->accessorIndex];
        if (jointsAccessor.componentType == fastgltf::ComponentType::UnsignedByte) {
            fastgltf::iterateAccessorWithIndex<fastgltf::math::u8vec4>(
                asset, jointsAccessor, [&](fastgltf::math::u8vec4 j, size_t idx) {
                    vertices[idx].joints[0] = j.x();
                    vertices[idx].joints[1] = j.y();
                    vertices[idx].joints[2] = j.z();
                    vertices[idx].joints[3] = j.w();
                });
        } else if (jointsAccessor.componentType == fastgltf::ComponentType::UnsignedShort) {
            fastgltf::iterateAccessorWithIndex<fastgltf::math::u16vec4>(
                asset, jointsAccessor, [&](fastgltf::math::u16vec4 j, size_t idx) {
                    vertices[idx].joints[0] = j.x();
                    vertices[idx].joints[1] = j.y();
                    vertices[idx].joints[2] = j.z();
                    vertices[idx].joints[3] = j.w();
                });
        }

        const auto& weightsAccessor = asset.accessors[weightsAttr->accessorIndex];
        fastgltf::iterateAccessorWithIndex<fastgltf::math::fvec4>(
            asset, weightsAccessor, [&](fastgltf::math::fvec4 w, size_t idx) {
                vertices[idx].weights[0] = w.x();
                vertices[idx].weights[1] = w.y();
                vertices[idx].weights[2] = w.z();
                vertices[idx].weights[3] = w.w();
            });

        meshData.skinnedVertices = vertices;
    } else {
        auto* vertices = new AcornGLTFVertex[vertexCount]();
        fastgltf::iterateAccessorWithIndex<fastgltf::math::fvec3>(
            asset, positionAccessor, [&](fastgltf::math::fvec3 pos, size_t idx) {
                vertices[idx].position[0] = pos.x();
                vertices[idx].position[1] = pos.y();
                vertices[idx].position[2] = pos.z();
                vertices[idx].color[0] = 1.0f;
                vertices[idx].color[1] = 1.0f;
                vertices[idx].color[2] = 1.0f;
                vertices[idx].color[3] = 1.0f;
                vertices[idx].normal[2] = 1.0f;
            });

        if (auto normalAttr = primitive.findAttribute("NORMAL"); normalAttr != primitive.attributes.end()) {
            fastgltf::iterateAccessorWithIndex<fastgltf::math::fvec3>(
                asset, asset.accessors[normalAttr->accessorIndex],
                [&](fastgltf::math::fvec3 normal, size_t idx) {
                    vertices[idx].normal[0] = normal.x();
                    vertices[idx].normal[1] = normal.y();
                    vertices[idx].normal[2] = normal.z();
                });
        }

        if (auto texCoordAttr = primitive.findAttribute("TEXCOORD_0"); texCoordAttr != primitive.attributes.end()) {
            fastgltf::iterateAccessorWithIndex<fastgltf::math::fvec2>(
                asset, asset.accessors[texCoordAttr->accessorIndex],
                [&](fastgltf::math::fvec2 uv, size_t idx) {
                    vertices[idx].texCoord[0] = uv.x();
                    vertices[idx].texCoord[1] = uv.y();
                });
        }

        meshData.vertices = vertices;
    }

    return meshData;
}

} // namespace

extern "C" bool acorn_gltf_load_file(const char* path, AcornGLTFModelResult* outResult) {
    if (!path || !outResult) {
        return false;
    }
    *outResult = {};

    fastgltf::Parser parser(fastgltf::Extensions::None);
    auto data = fastgltf::GltfDataBuffer::FromPath(path);
    if (data.error() != fastgltf::Error::None) {
        std::cerr << "Failed to load glTF file: " << path << std::endl;
        return false;
    }

    const auto directory = std::filesystem::path(path).parent_path();
    auto asset = parser.loadGltfBinary(data.get(), directory, fastgltf::Options::LoadExternalBuffers);
    if (asset.error() != fastgltf::Error::None) {
        const auto binaryError = asset.error();
        asset = parser.loadGltfJson(data.get(), directory, fastgltf::Options::LoadExternalBuffers);
        if (asset.error() != fastgltf::Error::None) {
            std::cerr << "Failed to parse glTF: " << path
                      << " (Binary error: " << fastgltf::getErrorName(binaryError)
                      << ", JSON error: " << fastgltf::getErrorName(asset.error()) << ")" << std::endl;
            return false;
        }
    }

    std::vector<size_t> meshPrimitiveOffsets(asset->meshes.size());
    std::vector<size_t> meshPrimitiveCounts(asset->meshes.size());
    std::vector<AcornGLTFMeshData> meshes;

    size_t currentOffset = 0;
    for (size_t i = 0; i < asset->meshes.size(); ++i) {
        const auto& gltfMesh = asset->meshes[i];
        meshPrimitiveOffsets[i] = currentOffset;
        meshPrimitiveCounts[i] = gltfMesh.primitives.size();
        for (const auto& primitive : gltfMesh.primitives) {
            meshes.push_back(extractPrimitive(asset.get(), primitive));
            currentOffset++;
        }
    }

    if (!meshes.empty()) {
        outResult->meshes = new AcornGLTFMeshData[meshes.size()];
        std::copy(meshes.begin(), meshes.end(), outResult->meshes);
        outResult->meshCount = static_cast<int32_t>(meshes.size());
    }

    std::vector<AcornGLTFNodeData> nodes;
    std::vector<int> gltfNodeToReturnedIndex(asset->nodes.size(), -1);
    const size_t sceneIndex = asset->defaultScene.value_or(0);
    if (sceneIndex < asset->scenes.size()) {
        const auto& scene = asset->scenes[sceneIndex];
        auto traverseNode = [&](auto& self, size_t nodeIndex, int returnedParentIndex) -> void {
            const auto& node = asset->nodes[nodeIndex];

            AcornGLTFNodeData nodeData = {};
            std::strncpy(nodeData.name, node.name.c_str(), sizeof(nodeData.name) - 1);
            nodeData.parentIndex = returnedParentIndex;
            nodeData.meshIndex = -1;
            nodeData.skinIndex = node.skinIndex.has_value() ? static_cast<int32_t>(node.skinIndex.value()) : -1;

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

            const int currentReturnedIndex = static_cast<int>(nodes.size());
            gltfNodeToReturnedIndex[nodeIndex] = currentReturnedIndex;

            if (node.meshIndex.has_value()) {
                const size_t meshIdx = node.meshIndex.value();
                const size_t offset = meshPrimitiveOffsets[meshIdx];
                const size_t count = meshPrimitiveCounts[meshIdx];
                if (count > 0) {
                    nodeData.meshIndex = static_cast<int32_t>(offset);
                }
                nodes.push_back(nodeData);

                for (size_t p = 1; p < count; ++p) {
                    AcornGLTFNodeData virtualNode = {};
                    std::snprintf(virtualNode.name, sizeof(virtualNode.name), "%s_primitive_%zu", node.name.c_str(), p);
                    virtualNode.parentIndex = currentReturnedIndex;
                    virtualNode.meshIndex = static_cast<int32_t>(offset + p);
                    virtualNode.skinIndex = nodeData.skinIndex;
                    virtualNode.rotation[3] = 1.0f;
                    virtualNode.scale[0] = 1.0f;
                    virtualNode.scale[1] = 1.0f;
                    virtualNode.scale[2] = 1.0f;
                    nodes.push_back(virtualNode);
                }
            } else {
                nodes.push_back(nodeData);
            }

            for (const auto childIndex : node.children) {
                self(self, childIndex, currentReturnedIndex);
            }
        };

        for (const auto rootNodeIndex : scene.nodeIndices) {
            traverseNode(traverseNode, rootNodeIndex, -1);
        }
    }

    if (nodes.empty() && !meshes.empty()) {
        for (size_t i = 0; i < meshes.size(); ++i) {
            AcornGLTFNodeData nodeData = {};
            std::snprintf(nodeData.name, sizeof(nodeData.name), "mesh_node_%zu", i);
            nodeData.parentIndex = -1;
            nodeData.meshIndex = static_cast<int32_t>(i);
            nodeData.skinIndex = -1;
            nodeData.rotation[3] = 1.0f;
            nodeData.scale[0] = 1.0f;
            nodeData.scale[1] = 1.0f;
            nodeData.scale[2] = 1.0f;
            nodes.push_back(nodeData);
        }
    }

    if (!nodes.empty()) {
        outResult->nodes = new AcornGLTFNodeData[nodes.size()];
        std::copy(nodes.begin(), nodes.end(), outResult->nodes);
        outResult->nodeCount = static_cast<int32_t>(nodes.size());
    }

    if (!asset->images.empty()) {
        const void* texBytes = nullptr;
        size_t texSize = 0;
        const auto& image = asset->images[0];

        if (const auto* bufferViewSource = std::get_if<fastgltf::sources::BufferView>(&image.data)) {
            const auto& bufferView = asset->bufferViews[bufferViewSource->bufferViewIndex];
            const auto& buffer = asset->buffers[bufferView.bufferIndex];
            if (const auto* arr = std::get_if<fastgltf::sources::Array>(&buffer.data)) {
                texBytes = arr->bytes.data() + bufferView.byteOffset;
                texSize = bufferView.byteLength;
            } else if (const auto* vec = std::get_if<fastgltf::sources::Vector>(&buffer.data)) {
                texBytes = vec->bytes.data() + bufferView.byteOffset;
                texSize = bufferView.byteLength;
            } else if (const auto* byteView = std::get_if<fastgltf::sources::ByteView>(&buffer.data)) {
                texBytes = byteView->bytes.data() + bufferView.byteOffset;
                texSize = bufferView.byteLength;
            }
        } else if (const auto* vec = std::get_if<fastgltf::sources::Vector>(&image.data)) {
            texBytes = vec->bytes.data();
            texSize = vec->bytes.size();
        } else if (const auto* arr = std::get_if<fastgltf::sources::Array>(&image.data)) {
            texBytes = arr->bytes.data();
            texSize = arr->bytes.size();
        }

        if (texBytes && texSize > 0) {
            void* copy = std::malloc(texSize);
            if (copy) {
                std::memcpy(copy, texBytes, texSize);
                outResult->textureData = copy;
                outResult->textureSize = static_cast<int32_t>(texSize);
            }
        }
    }

    if (!asset->animations.empty()) {
        const size_t numAnims = asset->animations.size();
        outResult->animations = new AcornGLTFAnimationData[numAnims]();
        outResult->animationCount = static_cast<int32_t>(numAnims);

        for (size_t a = 0; a < numAnims; ++a) {
            const auto& gltfAnim = asset->animations[a];
            auto& animData = outResult->animations[a];
            if (!gltfAnim.name.empty()) {
                std::strncpy(animData.name, gltfAnim.name.c_str(), sizeof(animData.name) - 1);
            } else {
                std::snprintf(animData.name, sizeof(animData.name), "animation_%zu", a);
            }

            std::vector<AcornGLTFChannelData> validChannels;
            validChannels.reserve(gltfAnim.channels.size());
            for (const auto& gltfChannel : gltfAnim.channels) {
                if (gltfChannel.samplerIndex >= gltfAnim.samplers.size()) continue;

                int targetNode = -1;
                if (gltfChannel.nodeIndex.has_value()) {
                    const size_t nodeIdx = gltfChannel.nodeIndex.value();
                    if (nodeIdx < gltfNodeToReturnedIndex.size()) {
                        targetNode = gltfNodeToReturnedIndex[nodeIdx];
                    }
                }
                if (targetNode < 0) continue;

                const auto& sampler = gltfAnim.samplers[gltfChannel.samplerIndex];
                if (sampler.inputAccessor >= asset->accessors.size() ||
                    sampler.outputAccessor >= asset->accessors.size()) {
                    continue;
                }

                const auto& inputAccessor = asset->accessors[sampler.inputAccessor];
                const auto& outputAccessor = asset->accessors[sampler.outputAccessor];

                std::vector<float> timestamps;
                timestamps.reserve(inputAccessor.count);
                fastgltf::iterateAccessor<float>(asset.get(), inputAccessor, [&](float t) {
                    timestamps.push_back(t);
                    if (t > animData.duration) animData.duration = t;
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
                    fastgltf::iterateAccessor<fastgltf::math::fvec3>(
                        asset.get(), outputAccessor, [&](fastgltf::math::fvec3 v) {
                            values.push_back(v.x());
                            values.push_back(v.y());
                            values.push_back(v.z());
                        });
                } else if (gltfChannel.path == fastgltf::AnimationPath::Rotation) {
                    pathType = 2;
                    values.reserve(outputAccessor.count * 4);
                    fastgltf::iterateAccessor<fastgltf::math::fquat>(
                        asset.get(), outputAccessor, [&](fastgltf::math::fquat q) {
                            values.push_back(q.x());
                            values.push_back(q.y());
                            values.push_back(q.z());
                            values.push_back(q.w());
                        });
                } else if (gltfChannel.path == fastgltf::AnimationPath::Scale) {
                    pathType = 3;
                    values.reserve(outputAccessor.count * 3);
                    fastgltf::iterateAccessor<fastgltf::math::fvec3>(
                        asset.get(), outputAccessor, [&](fastgltf::math::fvec3 v) {
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

                AcornGLTFChannelData channelData = {};
                channelData.nodeIndex = targetNode;
                channelData.path = pathType;
                channelData.interpolation = interp;
                channelData.keyframeCount = static_cast<int32_t>(timestamps.size());
                channelData.valuesPerKeyframe = static_cast<int32_t>(values.size() / timestamps.size());
                channelData.timestamps = new float[timestamps.size()];
                std::copy(timestamps.begin(), timestamps.end(), channelData.timestamps);
                channelData.values = new float[values.size()];
                std::copy(values.begin(), values.end(), channelData.values);
                validChannels.push_back(channelData);
            }

            animData.channelCount = static_cast<int32_t>(validChannels.size());
            if (!validChannels.empty()) {
                animData.channels = new AcornGLTFChannelData[validChannels.size()];
                std::copy(validChannels.begin(), validChannels.end(), animData.channels);
            }
        }
    }

    if (!asset->skins.empty()) {
        outResult->skinCount = static_cast<int32_t>(asset->skins.size());
        outResult->skins = new AcornGLTFSkinData[asset->skins.size()]();
        for (size_t s = 0; s < asset->skins.size(); ++s) {
            const auto& skin = asset->skins[s];
            auto& skinData = outResult->skins[s];
            std::strncpy(skinData.name, skin.name.c_str(), sizeof(skinData.name) - 1);
            skinData.jointCount = static_cast<int32_t>(skin.joints.size());
            if (skin.joints.empty()) continue;

            skinData.jointNodeIndices = new int32_t[skin.joints.size()];
            for (size_t j = 0; j < skin.joints.size(); ++j) {
                const size_t gltfNodeIdx = skin.joints[j];
                skinData.jointNodeIndices[j] = (gltfNodeIdx < gltfNodeToReturnedIndex.size())
                    ? gltfNodeToReturnedIndex[gltfNodeIdx]
                    : static_cast<int32_t>(gltfNodeIdx);
            }

            skinData.inverseBindMatrices = new float[skin.joints.size() * 16]();
            if (skin.inverseBindMatrices.has_value()) {
                const auto& ibmAccessor = asset->accessors[skin.inverseBindMatrices.value()];
                fastgltf::iterateAccessorWithIndex<fastgltf::math::fmat4x4>(
                    asset.get(), ibmAccessor, [&](fastgltf::math::fmat4x4 mat, size_t idx) {
                        if (idx < skin.joints.size()) {
                            std::copy(mat.data(), mat.data() + 16, &skinData.inverseBindMatrices[idx * 16]);
                        }
                    });
            } else {
                for (size_t j = 0; j < skin.joints.size(); ++j) {
                    float* dst = &skinData.inverseBindMatrices[j * 16];
                    dst[0] = dst[5] = dst[10] = dst[15] = 1.0f;
                }
            }
        }
    }

    return true;
}

extern "C" void acorn_gltf_free_result(AcornGLTFModelResult* result) {
    if (!result) return;

    if (result->meshes) {
        for (int32_t i = 0; i < result->meshCount; ++i) {
            delete[] result->meshes[i].vertices;
            delete[] result->meshes[i].skinnedVertices;
            delete[] result->meshes[i].indices;
        }
        delete[] result->meshes;
    }

    delete[] result->nodes;
    std::free(result->textureData);

    if (result->animations) {
        for (int32_t i = 0; i < result->animationCount; ++i) {
            auto& anim = result->animations[i];
            if (anim.channels) {
                for (int32_t j = 0; j < anim.channelCount; ++j) {
                    delete[] anim.channels[j].timestamps;
                    delete[] anim.channels[j].values;
                }
                delete[] anim.channels;
            }
        }
        delete[] result->animations;
    }

    if (result->skins) {
        for (int32_t i = 0; i < result->skinCount; ++i) {
            delete[] result->skins[i].jointNodeIndices;
            delete[] result->skins[i].inverseBindMatrices;
        }
        delete[] result->skins;
    }

    *result = {};
}
