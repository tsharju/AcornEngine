#include <NoGraphicsAPI/shader.slang>
#include "acorn_shared.h"

GPU_ROOT(AcornInstancedSpriteRoot, root);

struct VertexOut {
    float4 position : SV_Position;
    float4 color : COLOR0;
    float2 texCoord : TEXCOORD0;
};

[shader("vertex")]
VertexOut vertexMain(uint vertexId : SV_VertexID, uint instanceId : SV_InstanceID) {
    AcornGpuVertex v = root.vertices[vertexId];
    AcornGpuSpriteInstanceData inst = root.instances[instanceId];
    AcornGpuSpriteFrameUniforms u = root.uniforms[0];

    float4 worldPos = mul(inst.modelMatrix, float4(v.position, 1.0));

    VertexOut output;
    output.position = mul(u.viewProjectionMatrix, worldPos);
    output.color = v.color * inst.colorTint;

    float2 unitUV = v.texCoord;
    output.texCoord = float2(
        lerp(inst.uvRect.x, inst.uvRect.z, unitUV.x),
        lerp(inst.uvRect.y, inst.uvRect.w, unitUV.y)
    );
    return output;
}

[shader("fragment")]
float4 fragmentMain(VertexOut input) : SV_Target0 {
    Texture2D tex = gpu_texture<Texture2D>(root.textureIndex);
    SamplerState smp = gpu_sampler(root.samplerIndex);
    return tex.Sample(smp, input.texCoord) * input.color;
}
