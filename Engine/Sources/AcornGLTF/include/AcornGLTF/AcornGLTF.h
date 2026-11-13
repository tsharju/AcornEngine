#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Unskinned vertex layout matching AcornEngine's 64-byte `Vertex` stride.
typedef struct AcornGLTFVertex {
    float position[3];
    float _pad0;
    float color[4];
    float texCoord[2];
    float _pad1[2];
    float normal[3];
    float _pad2;
} AcornGLTFVertex;

/// Skinned vertex layout matching AcornEngine's 80-byte GPU skinned vertex stride.
typedef struct AcornGLTFSkinnedVertex {
    float position[3];
    float _padPosition;
    float color[4];
    float texCoord[2];
    uint16_t joints[4];
    float normal[3];
    float _padNormal;
    float weights[4];
} AcornGLTFSkinnedVertex;

/// CPU-side geometry payload extracted for a single glTF primitive.
typedef struct AcornGLTFMeshData {
    AcornGLTFVertex* vertices;
    AcornGLTFSkinnedVertex* skinnedVertices;
    uint32_t* indices;
    uint32_t vertexCount;
    uint32_t indexCount;
    bool isSkinned;
} AcornGLTFMeshData;

/// Hierarchy node extracted from the default glTF scene.
typedef struct AcornGLTFNodeData {
    char name[64];
    int32_t parentIndex;
    int32_t meshIndex;
    int32_t skinIndex;
    float translation[3];
    float rotation[4];
    float scale[3];
} AcornGLTFNodeData;

/// Single keyframed animation channel targeting one node property.
typedef struct AcornGLTFChannelData {
    int32_t nodeIndex;
    uint8_t path;          // 1 = translation, 2 = rotation, 3 = scale, 4 = weights
    uint8_t interpolation; // 0 = linear, 1 = step, 2 = cubic spline
    int32_t keyframeCount;
    float* timestamps;
    float* values;
    int32_t valuesPerKeyframe;
} AcornGLTFChannelData;

/// Animation clip decoded from glTF.
typedef struct AcornGLTFAnimationData {
    char name[64];
    float duration;
    AcornGLTFChannelData* channels;
    int32_t channelCount;
} AcornGLTFAnimationData;

/// Skinning joint mapping and inverse bind matrices decoded from glTF.
typedef struct AcornGLTFSkinData {
    char name[64];
    int32_t jointCount;
    int32_t* jointNodeIndices;
    float* inverseBindMatrices; // 16 column-major floats per joint
} AcornGLTFSkinData;

/// Complete CPU-side model bundle produced by `acorn_gltf_load_file`.
typedef struct AcornGLTFModelResult {
    AcornGLTFMeshData* meshes;
    int32_t meshCount;
    AcornGLTFNodeData* nodes;
    int32_t nodeCount;
    void* textureData;
    int32_t textureSize;
    AcornGLTFAnimationData* animations;
    int32_t animationCount;
    AcornGLTFSkinData* skins;
    int32_t skinCount;
} AcornGLTFModelResult;

/// Parses a `.glb` or `.gltf` asset from disk into CPU-side arrays.
/// Always release non-empty outputs with `acorn_gltf_free_result`.
bool acorn_gltf_load_file(const char* path, AcornGLTFModelResult* outResult);

/// Releases all heap memory allocated inside `result` and zeroes its fields.
void acorn_gltf_free_result(AcornGLTFModelResult* result);

#ifdef __cplusplus
}
#endif
