#include <NoGraphicsAPI/shader.slang>
#include "acorn_shared.h"

GPU_ROOT(AcornSkinnedMeshRoot, root);

struct VertexOut {
    float4 position : SV_Position;
    float4 color : COLOR0;
    float3 normal : TEXCOORD0;
    float3 worldPosition : TEXCOORD1;
    float2 texCoord : TEXCOORD2;
};

[shader("vertex")]
VertexOut vertexMain(uint vertexId : SV_VertexID) {
    AcornGpuSkinnedVertex v = root.vertices[vertexId];
    AcornGpuGlobalUniforms u = root.uniforms[0];

    uint j0 = v.packedJoints.x & 0xFFFFu;
    uint j1 = v.packedJoints.x >> 16u;
    uint j2 = v.packedJoints.y & 0xFFFFu;
    uint j3 = v.packedJoints.y >> 16u;

    float weightSum = v.weights.x + v.weights.y + v.weights.z + v.weights.w;
    float4x4 skinMatrix;
    if (weightSum > 1e-4) {
        float invWeightSum = 1.0 / weightSum;
        float4 w = v.weights * invWeightSum;
        skinMatrix =
            w.x * root.jointMatrices[j0] +
            w.y * root.jointMatrices[j1] +
            w.z * root.jointMatrices[j2] +
            w.w * root.jointMatrices[j3];
    } else {
        skinMatrix = float4x4(
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1
        );
    }

    float4 localPos = mul(skinMatrix, float4(v.position, 1.0));
    float3 localNorm = mul(skinMatrix, float4(v.normal, 0.0)).xyz;

    VertexOut output;
    output.position = mul(u.modelViewProjectionMatrix, localPos);
    output.worldPosition = mul(u.modelMatrix, localPos).xyz;
    output.color = v.color;
    output.normal = mul(u.normalMatrix, float4(localNorm, 0.0)).xyz;
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
