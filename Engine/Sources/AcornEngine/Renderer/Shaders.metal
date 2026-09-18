#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position;
    float4 color;
    float2 texCoord;
    float3 normal;
};

struct SkinnedVertexIn {
    float3 position;
    float4 color;
    float2 texCoord;
    ushort4 joints;
    float3 normal;
    float4 weights;
};

static_assert(sizeof(SkinnedVertexIn) == 80, "SkinnedVertexIn size mismatch");
static_assert(__builtin_offsetof(SkinnedVertexIn, position) == 0, "position offset mismatch");
static_assert(__builtin_offsetof(SkinnedVertexIn, color) == 16, "color offset mismatch");
static_assert(__builtin_offsetof(SkinnedVertexIn, texCoord) == 32, "texCoord offset mismatch");
static_assert(__builtin_offsetof(SkinnedVertexIn, joints) == 40, "joints offset mismatch");
static_assert(__builtin_offsetof(SkinnedVertexIn, normal) == 48, "normal offset mismatch");
static_assert(__builtin_offsetof(SkinnedVertexIn, weights) == 64, "weights offset mismatch");

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

vertex VertexOut skinned_vertex_main(uint vertexID [[vertex_id]],
                                    constant SkinnedVertexIn *vertices [[buffer(0)]],
                                    constant GlobalUniforms &uniforms [[buffer(1)]],
                                    constant float4x4 *jointMatrices [[buffer(2)]]) {
    SkinnedVertexIn v = vertices[vertexID];
    
    float weightSum = v.weights.x + v.weights.y + v.weights.z + v.weights.w;
    float4x4 skinMatrix;
    if (weightSum > 1e-4) {
        float invWeightSum = 1.0 / weightSum;
        float4 w = v.weights * invWeightSum;
        skinMatrix =
            w.x * jointMatrices[v.joints.x] +
            w.y * jointMatrices[v.joints.y] +
            w.z * jointMatrices[v.joints.z] +
            w.w * jointMatrices[v.joints.w];
    } else {
        skinMatrix = float4x4(1.0);
    }
        
    float4 localPos = skinMatrix * float4(v.position, 1.0);
    float3 localNorm = (skinMatrix * float4(v.normal, 0.0)).xyz;
    
    VertexOut out;
    out.position = uniforms.modelViewProjectionMatrix * localPos;
    out.worldPosition = (uniforms.modelMatrix * localPos).xyz;
    out.color = v.color;
    out.normal = (uniforms.normalMatrix * float4(localNorm, 0.0)).xyz;
    out.texCoord = v.texCoord;
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

// --- Instanced Rendering Shaders ---

struct FrameUniforms {
    float4x4 viewProjectionMatrix;
    float4 ambientLightColor;
    float4 directionalLightColor;
    float4 directionalLightDirection;
    float4 pointLightColor;
    float4 pointLightPosition;
};

struct MeshInstanceData {
    float4x4 modelMatrix;
    float4x4 normalMatrix;
    float4 color;
};

struct SpriteFrameUniforms {
    float4x4 viewProjectionMatrix;
};

struct SpriteInstanceData {
    float4x4 modelMatrix;
    float4 colorTint;
    float4 uvRect; // (uMin, vMin, uMax, vMax)
};

vertex VertexOut instanced_vertex_main(uint vertexID [[vertex_id]],
                                       uint instanceID [[instance_id]],
                                       constant VertexIn *vertices [[buffer(0)]],
                                       constant MeshInstanceData *instances [[buffer(1)]],
                                       constant FrameUniforms &frameUniforms [[buffer(2)]]) {
    VertexOut out;
    MeshInstanceData inst = instances[instanceID];
    float4 pos = float4(vertices[vertexID].position, 1.0);
    float4 worldPos = inst.modelMatrix * pos;
    
    out.position = frameUniforms.viewProjectionMatrix * worldPos;
    out.worldPosition = worldPos.xyz;
    out.color = vertices[vertexID].color * inst.color;
    out.normal = (inst.normalMatrix * float4(vertices[vertexID].normal, 0.0)).xyz;
    out.texCoord = vertices[vertexID].texCoord;
    return out;
}

fragment float4 instanced_fragment_main(VertexOut in [[stage_in]],
                                        constant FrameUniforms &uniforms [[buffer(0)]],
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
    float3 pointLightDirNorm = pointLightDir / max(distance, 0.0001);
    float pointNDotL = max(0.0, dot(normal, pointLightDirNorm));
    float attenuation = 1.0 / (1.0 + 0.1 * distance + 0.01 * distance * distance);
    float3 pointDiffuse = uniforms.pointLightColor.rgb * pointNDotL * attenuation;
    
    // Ambient
    float3 ambient = uniforms.ambientLightColor.rgb;
    
    float4 baseColor = texColor * in.color;
    float3 finalColor = baseColor.rgb * (ambient + directionalDiffuse + pointDiffuse);
    
    return float4(finalColor, baseColor.a);
}

vertex VertexOutSprite sprite_vertex_instanced(uint vertexID [[vertex_id]],
                                               uint instanceID [[instance_id]],
                                               constant VertexIn *vertices [[buffer(0)]],
                                               constant SpriteInstanceData *instances [[buffer(1)]],
                                               constant SpriteFrameUniforms &uniforms [[buffer(2)]]) {
    VertexOutSprite out;
    SpriteInstanceData inst = instances[instanceID];
    float4 pos = float4(vertices[vertexID].position, 1.0);
    out.position = uniforms.viewProjectionMatrix * (inst.modelMatrix * pos);
    out.color = vertices[vertexID].color * inst.colorTint;
    
    // Interpolate unit quad UVs (0..1) into the sprite sheet frame uvRect
    float2 unitUV = vertices[vertexID].texCoord;
    out.texCoord = float2(
        mix(inst.uvRect.x, inst.uvRect.z, unitUV.x),
        mix(inst.uvRect.y, inst.uvRect.w, unitUV.y)
    );
    return out;
}

// --- Road Rendering Shaders ---

struct RoadUniforms {
    float4x4 modelViewProjectionMatrix;
    float4 outlineColor;
    float outlineWidth; // default outline width fraction (e.g. 0.18)
    float edgeWidth;    // anti-aliasing edge width (e.g. 0.04)
    float widthScale;   // global road width scale (e.g. 1.0)
    float renderMode;   // 0 = unified single-pass, 1 = casing pass (outlines only), 2 = fill pass (inners only)
};

struct VertexOutRoad {
    float4 position [[position]];
    float4 roadColor;
    float4 outlineColor;
    float2 texCoord; // x: normalized across-line coordinate [-1, 1], y: outline ratio [0, 0.5]
    float3 worldPosition;
};

vertex VertexOutRoad road_vertex(uint vertexID [[vertex_id]],
                                 constant VertexIn *vertices [[buffer(0)]],
                                 constant RoadUniforms &uniforms [[buffer(1)]]) {
    VertexOutRoad out;
    VertexIn v = vertices[vertexID];
    
    float widthScale = uniforms.widthScale > 0.0 ? uniforms.widthScale : 1.0;
    float baseHalfWidth = (v.normal.y * 0.5) * widthScale;
    
    float outlineRatio = v.texCoord.y > 0.0 ? v.texCoord.y : uniforms.outlineWidth;
    float effectiveHalfWidth = baseHalfWidth;
    
    // In fill pass (renderMode == 2.0), scale ribbon down to inner pavement width
    if (uniforms.renderMode > 1.5) {
        effectiveHalfWidth = baseHalfWidth * max(0.0, 1.0 - outlineRatio);
    }
    
    float3 offset = float3(v.normal.x, 0.0, v.normal.z) * (v.texCoord.x * effectiveHalfWidth);
    float3 worldPos = v.position + offset;
    
    out.position = uniforms.modelViewProjectionMatrix * float4(worldPos, 1.0);
    out.worldPosition = worldPos;
    
    if (uniforms.renderMode > 0.5 && uniforms.renderMode < 1.5) {
        // Casing pass: color is the outline color
        out.roadColor = uniforms.outlineColor;
    } else {
        // Fill or single pass: color is vertex road color
        out.roadColor = v.color;
    }
    
    out.outlineColor = uniforms.outlineColor;
    out.texCoord = v.texCoord;
    return out;
}

fragment float4 road_fragment(VertexOutRoad in [[stage_in]],
                               constant RoadUniforms &uniforms [[buffer(0)]],
                               texture2d<float> roadTexture [[texture(0)]]) {
    constexpr sampler repeatSampler(coord::normalized,
                                    address::repeat,
                                    filter::linear);

    // in.texCoord.x is normalized across-line coordinate in [-1.0, 1.0]
    float d = abs(in.texCoord.x);

    bool hasTexture = (roadTexture.get_width() > 1 || roadTexture.get_height() > 1);

    if (hasTexture) {
        // 1. Sample Precreated Road Texture (Cobblestone / Aggregate Pavement)
        // Sampled in world-space coordinates to tile seamlessly across ribbon segments and junctions
        float2 worldXZ = in.worldPosition.xz;
        float4 texSample = roadTexture.sample(repeatSampler, worldXZ * 0.18);

        // Show the road texture as is without blending with the white road or outline color.
        // Blending only occurs at the outer edges where the road meets and joins the land.
        float textureLuma = dot(texSample.rgb, float3(0.299, 0.587, 0.114));
        float edgeJitter = (textureLuma - 0.5) * 0.12;
        float blendMargin = 0.22; // Outer ~22% of road softly feathers and blends with the ground
        float edgeStart = 1.0 - blendMargin + edgeJitter;
        float alpha = 1.0 - smoothstep(edgeStart, 1.0 + edgeJitter * 0.5, d);

        return float4(texSample.rgb, alpha * texSample.a * in.roadColor.a);
    }

    // Fallback: untextured vector road rendering
    float edgeWidth = uniforms.edgeWidth > 0.0 ? uniforms.edgeWidth : 0.04;

    if (uniforms.renderMode > 0.5) {
        // Two-pass mode (1.0 = casing pass, 2.0 = fill pass)
        float alpha = 1.0 - smoothstep(1.0 - edgeWidth, 1.0, d);
        return float4(in.roadColor.rgb, in.roadColor.a * alpha);
    }

    // Single-pass vector mode (renderMode == 0.0)
    float outlineRatio = in.texCoord.y > 0.0 ? in.texCoord.y : uniforms.outlineWidth;
    float innerEdge = 1.0 - outlineRatio;
    float outlineFactor = smoothstep(innerEdge - 0.08, innerEdge + 0.04, d);
    float alpha = 1.0 - smoothstep(1.0 - edgeWidth, 1.0, d);

    float3 finalRgb = mix(in.roadColor.rgb, in.outlineColor.rgb, outlineFactor);
    return float4(finalRgb, in.roadColor.a * alpha);
}

