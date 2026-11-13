#include <NoGraphicsAPI/shader.slang>
#include "acorn_shared.h"

GPU_ROOT(AcornSpriteRoot, root);

struct VertexOut {
    float4 position : SV_Position;
    float4 color : COLOR0;
    float2 texCoord : TEXCOORD0;
};

[shader("vertex")]
VertexOut vertexMain(uint vertexId : SV_VertexID) {
    AcornGpuVertex v = root.vertices[vertexId];
    AcornGpuSpriteUniforms u = root.uniforms[0];

    VertexOut output;
    output.position = mul(u.modelViewProjectionMatrix, float4(v.position, 1.0));
    output.color = v.color * u.colorTint;
    output.texCoord = v.texCoord;
    return output;
}

[shader("fragment")]
float4 fragmentMain(VertexOut input) : SV_Target0 {
    Texture2D tex = gpu_texture<Texture2D>(root.textureIndex);
    SamplerState smp = gpu_sampler(root.samplerIndex);
    return tex.Sample(smp, input.texCoord) * input.color;
}
