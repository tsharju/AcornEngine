#include <NoGraphicsAPI/shader.slang>
#include "acorn_shared.h"

GPU_ROOT(AcornRoadRoot, root);

struct VertexOut {
    float4 position : SV_Position;
    float4 roadColor : COLOR0;
    float4 outlineColor : COLOR1;
    float2 texCoord : TEXCOORD0;
    float3 worldPosition : TEXCOORD1;
};

[shader("vertex")]
VertexOut vertexMain(uint vertexId : SV_VertexID) {
    AcornGpuVertex v = root.vertices[vertexId];
    AcornGpuRoadUniforms u = root.uniforms[0];

    float widthScale = u.widthScale > 0.0 ? u.widthScale : 1.0;
    float baseHalfWidth = (v.normal.y * 0.5) * widthScale;
    float outlineRatio = v.texCoord.y > 0.0 ? v.texCoord.y : u.outlineWidth;
    float effectiveHalfWidth = baseHalfWidth;

    if (u.renderMode > 1.5) {
        effectiveHalfWidth = baseHalfWidth * max(0.0, 1.0 - outlineRatio);
    }

    float3 offset = float3(v.normal.x, 0.0, v.normal.z) * (v.texCoord.x * effectiveHalfWidth);
    float3 worldPos = v.position + offset;

    VertexOut output;
    output.position = mul(u.modelViewProjectionMatrix, float4(worldPos, 1.0));
    output.worldPosition = worldPos;

    if (u.renderMode > 0.5 && u.renderMode < 1.5) {
        output.roadColor = u.outlineColor;
    } else {
        output.roadColor = v.color;
    }

    output.outlineColor = u.outlineColor;
    output.texCoord = v.texCoord;
    return output;
}

[shader("fragment")]
float4 fragmentMain(VertexOut input) : SV_Target0 {
    AcornGpuRoadUniforms u = root.uniforms[0];
    float d = abs(input.texCoord.x);

    if (root.hasTexture != 0) {
        Texture2D roadTex = gpu_texture<Texture2D>(root.textureIndex);
        SamplerState repeatSmp = gpu_sampler(root.samplerIndex);
        float2 worldXZ = input.worldPosition.xz;
        float4 texSample = roadTex.Sample(repeatSmp, worldXZ * 0.18);

        float textureLuma = dot(texSample.rgb, float3(0.299, 0.587, 0.114));
        float edgeJitter = (textureLuma - 0.5) * 0.12;
        float blendMargin = 0.22;
        float edgeStart = 1.0 - blendMargin + edgeJitter;
        float alpha = 1.0 - smoothstep(edgeStart, 1.0 + edgeJitter * 0.5, d);

        return float4(texSample.rgb, alpha * texSample.a * input.roadColor.a);
    }

    float edgeWidth = u.edgeWidth > 0.0 ? u.edgeWidth : 0.04;
    if (u.renderMode > 0.5) {
        float alpha = 1.0 - smoothstep(1.0 - edgeWidth, 1.0, d);
        return float4(input.roadColor.rgb, input.roadColor.a * alpha);
    }

    float outlineRatio = input.texCoord.y > 0.0 ? input.texCoord.y : u.outlineWidth;
    float innerEdge = 1.0 - outlineRatio;
    float outlineFactor = smoothstep(innerEdge - 0.08, innerEdge + 0.04, d);
    float alpha = 1.0 - smoothstep(1.0 - edgeWidth, 1.0, d);

    float3 finalRgb = lerp(input.roadColor.rgb, input.outlineColor.rgb, outlineFactor);
    return float4(finalRgb, input.roadColor.a * alpha);
}
