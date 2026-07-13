#pragma once
#include <simd/simd.h>

namespace Acorn {
    struct GlobalUniforms {
        simd_float4x4 modelViewProjectionMatrix;
        simd_float4x4 modelMatrix;
        simd_float4x4 normalMatrix;
        simd_float4 ambientLightColor;
        simd_float4 directionalLightColor;
        simd_float4 directionalLightDirection;
        simd_float4 pointLightColor;
        simd_float4 pointLightPosition;
        simd_float4 meshColor;
    };
    
    struct SpriteUniforms {
        simd_float4x4 modelViewProjectionMatrix;
        simd_float4 colorTint;
    };
    
    struct SDFUniforms {
        simd_float4 textColor;
        simd_float4 outlineColor;
        float outlineWidth;
        float edgeWidth;
        simd_float2 padding;
        simd_float4x4 modelViewProjectionMatrix;
    };
}
