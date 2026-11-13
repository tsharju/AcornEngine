#include <NoGraphicsAPI/shader.slang>
#include "acorn_shared.h"

GPU_ROOT(AcornMeshRoot, root);

struct VertexOut {
    float4 position : SV_Position;
    float4 color : COLOR0;
    float3 normal : TEXCOORD0;
    float3 worldPosition : TEXCOORD1;
    float2 texCoord : TEXCOORD2;
};

[shader("vertex")]
VertexOut vertexMain(uint vertexId : SV_VertexID) {
    AcornGpuVertex v = root.vertices[vertexId];
    AcornGpuGlobalUniforms u = root.uniforms[0];
    float4 pos = float4(v.position, 1.0);

    VertexOut output;
    output.position = mul(u.modelViewProjectionMatrix, pos);
    output.worldPosition = mul(u.modelMatrix, pos).xyz;
    output.color = v.color;
    output.normal = mul(u.normalMatrix, float4(v.normal, 0.0)).xyz;
    output.texCoord = v.texCoord;
    return output;
}

[shader("fragment")]
float4 fragmentMain(VertexOut input) : SV_Target0 {
    AcornGpuGlobalUniforms u = root.uniforms[0];
    Texture2D tex = gpu_texture<Texture2D>(root.textureIndex);
    SamplerState smp = gpu_sampler(root.samplerIndex);

    float4 texColor = tex.Sample(smp, input.texCoord);
    float3 normal = normalize(input.normal);
    float3 lightDir = normalize(-u.directionalLightDirection.xyz);

    float nDotL = max(0.0, dot(normal, lightDir));
    float3 directionalDiffuse = u.directionalLightColor.rgb * nDotL;

    float3 pointLightDir = u.pointLightPosition.xyz - input.worldPosition;
    float distance = length(pointLightDir);
    float3 pointLightDirNorm = pointLightDir / max(distance, 0.0001);
    float pointNDotL = max(0.0, dot(normal, pointLightDirNorm));
    float attenuation = 1.0 / (1.0 + 0.1 * distance + 0.01 * distance * distance);
    float3 pointDiffuse = u.pointLightColor.rgb * pointNDotL * attenuation;

    float3 ambient = u.ambientLightColor.rgb;
    float4 baseColor = texColor * input.color * u.meshColor;
    float3 finalColor = baseColor.rgb * (ambient + directionalDiffuse + pointDiffuse);

    return float4(finalColor, baseColor.a);
}
