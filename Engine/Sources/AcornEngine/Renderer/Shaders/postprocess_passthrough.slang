#include <NoGraphicsAPI/shader.slang>
#include "acorn_shared.h"

GPU_ROOT(AcornPostProcessRoot, root);

struct VertexOut {
    float4 position : SV_Position;
    float2 texCoord : TEXCOORD0;
};

[shader("vertex")]
VertexOut vertexMain(uint vertexId : SV_VertexID) {
    float2 texCoord = float2((vertexId << 1) & 2, vertexId & 2);
    VertexOut output;
    output.position = float4(texCoord * 2.0 - 1.0, 0.0, 1.0);
    output.texCoord = texCoord;
    return output;
}

[shader("fragment")]
float4 fragmentMain(VertexOut input) : SV_Target0 {
    Texture2D colorTex = gpu_texture<Texture2D>(root.colorTextureIndex);
    SamplerState colorSmp = gpu_sampler(root.colorSamplerIndex);
    Texture2D depthTex = gpu_texture<Texture2D>(root.depthTextureIndex);
    SamplerState depthSmp = gpu_sampler(root.depthSamplerIndex);

    float4 color = colorTex.Sample(colorSmp, input.texCoord);
    float depth = depthTex.Sample(depthSmp, input.texCoord).r;
    float4 params = root.uniforms[0];

    return float4(lerp(color.rgb, params.rgb * (1.0 - depth * 0.5), clamp(params.w, 0.0, 1.0)), color.a);
}
