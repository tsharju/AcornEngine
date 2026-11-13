#pragma once

#include <NoGraphicsAPIUtility/shader_types.h>

// Shared CPU/GPU vertex, uniform, and root structs compiled identically across
// C++20, Slang -> Metal 4 (c-layout + row-major matrices), and Slang -> SPIR-V.

struct AcornGpuVertex {
    float3 position;
    float _pad0;
    float4 color;
    float2 texCoord;
    float2 _pad1;
    float3 normal;
    float _pad2;
};

struct AcornGpuSkinnedVertex {
    float3 position;
    float _padPosition;
    float4 color;
    float2 texCoord;
    uint2 packedJoints; // Packed little-endian uint16_t joints[4]
    float3 normal;
    float _padNormal;
    float4 weights;
};

struct AcornGpuGlobalUniforms {
    float4x4 modelViewProjectionMatrix;
    float4x4 modelMatrix;
    float4x4 normalMatrix;
    float4 ambientLightColor;
    float4 directionalLightColor;
    float4 directionalLightDirection;
    float4 pointLightColor;
    float4 pointLightPosition;
    float4 meshColor;
};

struct AcornGpuSdfUniforms {
    float4 textColor;
    float4 outlineColor;
    float outlineWidth;
    float edgeWidth;
    float2 _padding;
    float4x4 modelViewProjectionMatrix;
};

struct AcornGpuSpriteUniforms {
    float4x4 modelViewProjectionMatrix;
    float4 colorTint;
};

struct AcornGpuFrameUniforms {
    float4x4 viewProjectionMatrix;
    float4 ambientLightColor;
    float4 directionalLightColor;
    float4 directionalLightDirection;
    float4 pointLightColor;
    float4 pointLightPosition;
};

struct AcornGpuMeshInstanceData {
    float4x4 modelMatrix;
    float4x4 normalMatrix;
    float4 color;
};

struct AcornGpuSpriteFrameUniforms {
    float4x4 viewProjectionMatrix;
};

struct AcornGpuSpriteInstanceData {
    float4x4 modelMatrix;
    float4 colorTint;
    float4 uvRect;
};

struct AcornGpuRoadUniforms {
    float4x4 modelViewProjectionMatrix;
    float4 outlineColor;
    float outlineWidth;
    float edgeWidth;
    float widthScale;
    float renderMode;
};

// Root constant buffers passed as 16-byte-aligned GPU pointers (<= 32 bytes each).
struct AcornMeshRoot {
    AcornGpuVertex* vertices;
    AcornGpuGlobalUniforms* uniforms;
    uint32 textureIndex;
    uint32 samplerIndex;
    uint32 _pad[2];
};

struct AcornSkinnedMeshRoot {
    AcornGpuSkinnedVertex* vertices;
    AcornGpuGlobalUniforms* uniforms;
    float4x4* jointMatrices;
    uint32 textureIndex;
    uint32 samplerIndex;
};

struct AcornInstancedMeshRoot {
    AcornGpuVertex* vertices;
    AcornGpuFrameUniforms* uniforms;
    AcornGpuMeshInstanceData* instances;
    uint32 textureIndex;
    uint32 samplerIndex;
};

struct AcornSdfRoot {
    AcornGpuVertex* vertices;
    AcornGpuSdfUniforms* uniforms;
    uint32 textureIndex;
    uint32 samplerIndex;
    uint32 _pad[2];
};

struct AcornSpriteRoot {
    AcornGpuVertex* vertices;
    AcornGpuSpriteUniforms* uniforms;
    uint32 textureIndex;
    uint32 samplerIndex;
    uint32 _pad[2];
};

struct AcornInstancedSpriteRoot {
    AcornGpuVertex* vertices;
    AcornGpuSpriteFrameUniforms* uniforms;
    AcornGpuSpriteInstanceData* instances;
    uint32 textureIndex;
    uint32 samplerIndex;
};

struct AcornRoadRoot {
    AcornGpuVertex* vertices;
    AcornGpuRoadUniforms* uniforms;
    uint32 textureIndex;
    uint32 samplerIndex;
    uint32 hasTexture;
    uint32 _pad;
};

struct AcornPostProcessRoot {
    float4* uniforms;
    uint32 colorTextureIndex;
    uint32 depthTextureIndex;
    uint32 colorSamplerIndex;
    uint32 depthSamplerIndex;
    uint32 _pad[2];
};

#if !defined(__SLANG__)
static_assert(sizeof(AcornGpuVertex) == 64);
static_assert(sizeof(AcornGpuSkinnedVertex) == 80);
static_assert(sizeof(AcornGpuGlobalUniforms) == 288);
static_assert(sizeof(AcornGpuSdfUniforms) == 112);
static_assert(sizeof(AcornGpuSpriteUniforms) == 80);
static_assert(sizeof(AcornGpuFrameUniforms) == 144);
static_assert(sizeof(AcornGpuMeshInstanceData) == 144);
static_assert(sizeof(AcornGpuSpriteFrameUniforms) == 64);
static_assert(sizeof(AcornGpuSpriteInstanceData) == 96);
static_assert(sizeof(AcornGpuRoadUniforms) == 96);

static_assert(sizeof(AcornMeshRoot) == 32);
static_assert(sizeof(AcornSkinnedMeshRoot) == 32);
static_assert(sizeof(AcornInstancedMeshRoot) == 32);
static_assert(sizeof(AcornSdfRoot) == 32);
static_assert(sizeof(AcornSpriteRoot) == 32);
static_assert(sizeof(AcornInstancedSpriteRoot) == 32);
static_assert(sizeof(AcornRoadRoot) == 32);
static_assert(sizeof(AcornPostProcessRoot) == 32);
#endif
