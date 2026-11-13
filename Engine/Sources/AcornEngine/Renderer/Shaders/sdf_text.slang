#include <NoGraphicsAPI/shader.slang>
#include "acorn_shared.h"

GPU_ROOT(AcornSdfRoot, root);

struct VertexOut {
    float4 position : SV_Position;
    float4 color : COLOR0;
    float2 texCoord : TEXCOORD0;
};

[shader("vertex")]
VertexOut vertexMain(uint vertexId : SV_VertexID) {
    AcornGpuVertex v = root.vertices[vertexId];
    AcornGpuSdfUniforms u = root.uniforms[0];

    VertexOut output;
    output.position = mul(u.modelViewProjectionMatrix, float4(v.position, 1.0));
    output.color = v.color;
    output.texCoord = v.texCoord;
    return output;
}

[shader("fragment")]
float4 fragmentMain(VertexOut input) : SV_Target0 {
    AcornGpuSdfUniforms u = root.uniforms[0];
    Texture2D sdfTex = gpu_texture<Texture2D>(root.textureIndex);
    SamplerState smp = gpu_sampler(root.samplerIndex);

    float dist = sdfTex.Sample(smp, input.texCoord).r;
    float edgeWidth = u.edgeWidth;
    float outlineWidth = u.outlineWidth;

    float outlineFactor = smoothstep(0.5 - outlineWidth - edgeWidth, 0.5 - outlineWidth + edgeWidth, dist);
    float bodyFactor = smoothstep(0.5 - edgeWidth, 0.5 + edgeWidth, dist);

    float4 finalColor = lerp(u.outlineColor, u.textColor * input.color, bodyFactor);
    finalColor.a *= outlineFactor;
    return finalColor;
}
