#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position;
    float4 color;
    float2 texCoord;
    float3 normal;
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float3 normal;
    float3 worldPosition;
    float2 texCoord;
};

struct GlobalUniforms {
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

vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                             constant VertexIn *vertices [[buffer(0)]],
                             constant GlobalUniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    float4 pos = float4(vertices[vertexID].position, 1.0);
    out.position = uniforms.modelViewProjectionMatrix * pos;
    out.worldPosition = (uniforms.modelMatrix * pos).xyz;
    out.color = vertices[vertexID].color;
    out.normal = (uniforms.normalMatrix * float4(vertices[vertexID].normal, 0.0)).xyz;
    out.texCoord = vertices[vertexID].texCoord;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              constant GlobalUniforms &uniforms [[buffer(0)]],
                              texture2d<float> meshTexture [[texture(0)]]) {
    constexpr sampler linearSampler(coord::normalized,
                                    address::clamp_to_edge,
                                    filter::linear);
                                    
    float4 texColor = meshTexture.sample(linearSampler, in.texCoord);
    float3 normal = normalize(in.normal);
    float3 lightDir = normalize(-uniforms.directionalLightDirection.xyz);
    
    // Directional Diffuse
    float nDotL = max(0.0, dot(normal, lightDir));
    float3 directionalDiffuse = uniforms.directionalLightColor.rgb * nDotL;
    
    // Point Light Diffuse
    float3 pointLightDir = uniforms.pointLightPosition.xyz - in.worldPosition;
    float distance = length(pointLightDir);
    float3 pointLightDirNorm = pointLightDir / distance;
    float pointNDotL = max(0.0, dot(normal, pointLightDirNorm));
    // Simple quadratic attenuation
    float attenuation = 1.0 / (1.0 + 0.1 * distance + 0.01 * distance * distance);
    float3 pointDiffuse = uniforms.pointLightColor.rgb * pointNDotL * attenuation;
    
    // Ambient
    float3 ambient = uniforms.ambientLightColor.rgb;
    
    // Multiply texture color with vertex color and mesh color tint
    float4 baseColor = texColor * in.color * uniforms.meshColor;
    
    float3 finalColor = baseColor.rgb * (ambient + directionalDiffuse + pointDiffuse);
    
    return float4(finalColor, baseColor.a);
}

// --- SDF Text Rendering Shaders ---

struct SDFUniforms {
    float4 textColor;
    float4 outlineColor;
    float outlineWidth;
    float edgeWidth;
    float2 padding;
    float4x4 modelViewProjectionMatrix;
};

struct VertexOutText {
    float4 position [[position]];
    float4 color;
    float2 texCoord;
};

vertex VertexOutText sdf_vertex(uint vertexID [[vertex_id]],
                                constant VertexIn *vertices [[buffer(0)]],
                                constant SDFUniforms &uniforms [[buffer(1)]]) {
    VertexOutText out;
    float4 pos = float4(vertices[vertexID].position, 1.0);
    out.position = uniforms.modelViewProjectionMatrix * pos;
    out.color = vertices[vertexID].color;
    out.texCoord = vertices[vertexID].texCoord;
    return out;
}

fragment float4 sdf_fragment(VertexOutText in [[stage_in]],
                             texture2d<float> sdfTexture [[texture(0)]],
                             constant SDFUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler linearSampler(coord::normalized,
                                    address::clamp_to_edge,
                                    filter::linear);
                                    
    // Sample the single-channel distance field
    float dist = sdfTexture.sample(linearSampler, in.texCoord).r;
    
    float edgeWidth = uniforms.edgeWidth;
    float outlineWidth = uniforms.outlineWidth;
    
    // Compute outline and body alpha factors
    float outlineFactor = smoothstep(0.5 - outlineWidth - edgeWidth, 0.5 - outlineWidth + edgeWidth, dist);
    float bodyFactor = smoothstep(0.5 - edgeWidth, 0.5 + edgeWidth, dist);
    
    // Interpolate between outline color and body color (tinted by vertex color)
    float4 finalColor = mix(uniforms.outlineColor, uniforms.textColor * in.color, bodyFactor);
    finalColor.a *= outlineFactor;
    
    return finalColor;
}

// --- Sprite Rendering Shaders ---

struct SpriteUniforms {
    float4x4 modelViewProjectionMatrix;
    float4 colorTint;
};

struct VertexOutSprite {
    float4 position [[position]];
    float4 color;
    float2 texCoord;
};

vertex VertexOutSprite sprite_vertex(uint vertexID [[vertex_id]],
                                     constant VertexIn *vertices [[buffer(0)]],
                                     constant SpriteUniforms &uniforms [[buffer(1)]]) {
    VertexOutSprite out;
    float4 pos = float4(vertices[vertexID].position, 1.0);
    out.position = uniforms.modelViewProjectionMatrix * pos;
    // Multiply vertex color by global color tint
    out.color = vertices[vertexID].color * uniforms.colorTint;
    out.texCoord = vertices[vertexID].texCoord;
    return out;
}

fragment float4 sprite_fragment(VertexOutSprite in [[stage_in]],
                                texture2d<float> spriteTexture [[texture(0)]]) {
    constexpr sampler linearSampler(coord::normalized,
                                    address::clamp_to_edge,
                                    filter::linear);
                                    
    float4 texColor = spriteTexture.sample(linearSampler, in.texCoord);
    return texColor * in.color;
}
