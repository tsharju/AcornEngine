#include <metal_stdlib>
using namespace metal;

struct VertexOutPostProcess {
    float4 position [[position]];
    float2 texCoord;
};

struct PostApocalypticUniforms {
    float4x4 inverseViewProjectionMatrix;
    float4x4 viewProjectionMatrix;
    float4 cameraPosition;
    float4 playerPosition;
    float4 mossColorDark;
    float4 mossColorLight;
    float4 mossColorLichen;
    float4 skyFogColor;
    float mossDensity;
    float mossScale;
    float weatheringAmount;
    float fogDensity;
    float time;
    float isEnabled;
    float ssaoIntensity;
    float ssaoRadius;
    float ssaoBias;
    float pad0;
    float pad1;
    float pad2;
};

// MARK: - Fullscreen Triangle Vertex Shader

vertex VertexOutPostProcess postprocess_vertex(uint vertexID [[vertex_id]]) {
    VertexOutPostProcess out;
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    float2 pos = positions[vertexID];
    out.position = float4(pos, 0.0, 1.0);
    out.texCoord = float2(pos.x * 0.5 + 0.5, 1.0 - (pos.y * 0.5 + 0.5));
    return out;
}

// MARK: - High-Precision Integer Hash Perlin Gradient Noise & fBm

namespace {
    // 16 precomputed normalized 2D gradients around unit circle
    // Eliminates all trigonometric (cos/sin) operations in Perlin noise
    constant float2 kGradients[16] = {
        float2( 1.0,          0.0),
        float2( 0.92387953,   0.38268343),
        float2( 0.70710678,   0.70710678),
        float2( 0.38268343,   0.92387953),
        float2( 0.0,          1.0),
        float2(-0.38268343,   0.92387953),
        float2(-0.70710678,   0.70710678),
        float2(-0.92387953,   0.38268343),
        float2(-1.0,          0.0),
        float2(-0.92387953,  -0.38268343),
        float2(-0.70710678,  -0.70710678),
        float2(-0.38268343,  -0.92387953),
        float2( 0.0,         -1.0),
        float2( 0.38268343,  -0.92387953),
        float2( 0.70710678,  -0.70710678),
        float2( 0.92387953,  -0.38268343)
    };

    inline float2 hashGradient(int2 p) {
        uint2 u = as_type<uint2>(p);
        uint h = u.x * 374761393u + u.y * 668265263u;
        h = (h ^ (h >> 13u)) * 1274126177u;
        h = h ^ (h >> 16u);
        return kGradients[h & 15u];
    }

    inline float perlinNoise(float2 p) {
        int2 i = int2(floor(p));
        float2 f = fract(p);
        // Quintic Hermite interpolant for C2 continuity
        float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
        
        float n00 = dot(hashGradient(i + int2(0, 0)), f - float2(0.0, 0.0));
        float n10 = dot(hashGradient(i + int2(1, 0)), f - float2(1.0, 0.0));
        float n01 = dot(hashGradient(i + int2(0, 1)), f - float2(0.0, 1.0));
        float n11 = dot(hashGradient(i + int2(1, 1)), f - float2(1.0, 1.0));
        
        return mix(mix(n00, n10, u.x), mix(n01, n11, u.x), u.y);
    }

    inline float fbm(float2 p, int octaves) {
        float value = 0.0;
        float amplitude = 0.5;
        float2x2 rot = float2x2(0.87758, 0.47942, -0.47942, 0.87758);
        for (int i = 0; i < octaves; ++i) {
            value += amplitude * perlinNoise(p);
            p = rot * p * 2.02 + float2(17.3, 31.7);
            amplitude *= 0.5;
        }
        return value * 0.5 + 0.5; // Normalized to [0, 1]
    }

    // Precomputed Vogel disk sample offsets for 8 SSAO samples
    constant float2 kSSAODisk[8] = {
        float2( 0.2500,  0.0000),
        float2(-0.3193,  0.2925),
        float2( 0.0489, -0.5569),
        float2( 0.4024,  0.5250),
        float2(-0.7389, -0.1288),
        float2( 0.6930, -0.4552),
        float2(-0.2333,  0.8707),
        float2(-0.4747, -0.8439)
    };

    // MARK: - Screen Space Ambient Occlusion (SSAO)
    float evaluateSSAO(
        float3 worldPos,
        float3 normal,
        float2 screenUV,
        texture2d<float> depthTex,
        sampler ptSampler,
        constant PostApocalypticUniforms &u
    ) {
        if (u.ssaoIntensity <= 0.001) {
            return 1.0;
        }

        float camDist = length(worldPos - u.cameraPosition.xyz);
        // Early distance culling: AO is imperceptible beyond 300m and completely faded by 350m
        if (camDist > 300.0) {
            return 1.0;
        }

        // Project world-space radius (ssaoRadius meters) to screen UV space
        float screenRadius = (u.ssaoRadius / max(camDist, 1.0)) * 0.45;
        screenRadius = clamp(screenRadius, 0.003, 0.09);

        // Pseudo-random per-pixel rotation angle to break regular concentric pattern
        float hash = fract(sin(dot(screenUV * 1000.0, float2(12.9898, 78.233))) * 43758.5453);
        float phi = hash * 6.2831853;
        float cosPhi = cos(phi);
        float sinPhi = sin(phi);
        float2 rotCol0 = float2(cosPhi, sinPhi);
        float2 rotCol1 = float2(-sinPhi, cosPhi);

        float totalOcclusion = 0.0;
        const int SAMPLE_COUNT = 8;

        for (int i = 0; i < SAMPLE_COUNT; ++i) {
            float2 diskOffset = kSSAODisk[i];
            float2 rotatedOffset = diskOffset.x * rotCol0 + diskOffset.y * rotCol1;
            float2 sampleUV = screenUV + rotatedOffset * screenRadius;

            if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) {
                continue;
            }

            float sampleDepth = depthTex.sample(ptSampler, sampleUV).r;
            if (sampleDepth >= 0.9999) {
                continue;
            }

            // Reconstruct neighbor 3D world position
            float2 sNdc = float2(sampleUV.x * 2.0 - 1.0, (1.0 - sampleUV.y) * 2.0 - 1.0);
            float4 sClip = float4(sNdc, sampleDepth, 1.0);
            float4 sWorldH = u.inverseViewProjectionMatrix * sClip;
            float3 sWorld = sWorldH.xyz / max(sWorldH.w, 1e-6);

            float3 occluderVec = sWorld - worldPos;
            float occluderDist = length(occluderVec);

            // Skip self-samples and samples beyond influence radius
            if (occluderDist < 0.03 || occluderDist > u.ssaoRadius) {
                continue;
            }

            float3 occluderDir = occluderVec / occluderDist;
            float cosAngle = dot(normal, occluderDir);

            // Occlusion only occurs if sample point lies above tangent plane horizon
            if (cosAngle > u.ssaoBias) {
                float angleWeight = cosAngle - u.ssaoBias;
                float distFalloff = max(0.0, 1.0 - occluderDist / u.ssaoRadius);
                totalOcclusion += angleWeight * (distFalloff * distFalloff);
            }
        }

        float rawAO = totalOcclusion / float(SAMPLE_COUNT);
        float aoFactor = clamp(1.0 - rawAO * u.ssaoIntensity * 2.2, 0.0, 1.0);

        // Smooth distance fade out towards 350m
        float distFade = clamp(1.0 - (camDist - 150.0) / 150.0, 0.0, 1.0);
        return mix(1.0, aoFactor, distFade);
    }
}

// MARK: - Post-Apocalyptic Fragment Shader

fragment float4 postprocess_fragment(
    VertexOutPostProcess in [[stage_in]],
    texture2d<float> sceneColorTexture [[texture(0)]],
    texture2d<float> sceneDepthTexture [[texture(1)]],
    constant PostApocalypticUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    constexpr sampler pointSampler(coord::normalized, address::clamp_to_edge, filter::nearest);

    float4 sceneColor = sceneColorTexture.sample(linearSampler, in.texCoord);
    float depth = sceneDepthTexture.sample(pointSampler, in.texCoord).r;

    // Fast exit if post-apocalyptic effect is disabled
    if (uniforms.isEnabled <= 0.001) {
        return sceneColor;
    }

    // Sky rendering: depth buffer clear depth is 1.0
    if (depth >= 0.9999) {
        float skyGradient = clamp(in.texCoord.y * 1.6, 0.0, 1.0);
        float skyClouds = fbm(in.texCoord * 4.0 + float2(uniforms.time * 0.015, 0.0), 2);
        float3 skyHorizon = uniforms.skyFogColor.rgb * 1.15;
        float3 skyZenith = uniforms.skyFogColor.rgb * 0.42;
        float3 skyColor = mix(skyZenith, skyHorizon, skyGradient);
        skyColor += (skyClouds - 0.5) * 0.06;
        return float4(skyColor, 1.0);
    }

    // 1. Reconstruct 3D World Position from Depth Buffer
    float2 ndcXY = float2(in.texCoord.x * 2.0 - 1.0, (1.0 - in.texCoord.y) * 2.0 - 1.0);
    float4 clipPos = float4(ndcXY, depth, 1.0);
    float4 worldPosH = uniforms.inverseViewProjectionMatrix * clipPos;
    float3 worldPos = worldPosH.xyz / max(worldPosH.w, 1e-6);

    // 2. Reconstruct Surface Normal via Screen-Space Derivatives
    float3 dPdx = dfdx(worldPos);
    float3 dPdy = dfdy(worldPos);
    float3 normal = normalize(cross(dPdx, dPdy));
    if (dot(normal, uniforms.cameraPosition.xyz - worldPos) < 0.0) {
        normal = -normal;
    }

    // 3. Exclude Player Character Avatar and Beacon Ring from Moss Post-Processing
    float playerDistXZ = length(worldPos.xz - uniforms.playerPosition.xz);
    float playerDeltaY = worldPos.y - uniforms.playerPosition.y;
    bool isPlayerAvatar = (playerDistXZ <= 0.60 && playerDeltaY >= 0.03 && playerDeltaY <= 2.10);
    bool isPlayerBeacon = (playerDistXZ >= 0.65 && playerDistXZ <= 2.30 && playerDeltaY >= 0.05 && playerDeltaY <= 0.25 && normal.y > 0.7);
    if (isPlayerAvatar || isPlayerBeacon) {
        return sceneColor;
    }

    // 4. Multi-Octave Procedural Perlin Noise Moss Evaluation
    // Macro patch noise (large organic clumps) & micro detail noise (leafy clusters)
    float nMacro = fbm(worldPos.xz * uniforms.mossScale, 3);
    float nMicro = fbm(worldPos.xz * uniforms.mossScale * 3.8, 2);
    float clump = nMacro * 0.65 + nMicro * 0.35;

    // Crack-following moss growth along concrete seams and asphalt fissures
    float crackNoise = abs(perlinNoise(worldPos.xz * 0.18));
    float crackGrowth = (1.0 - smoothstep(0.005, 0.035, crackNoise)) * 0.15 * uniforms.mossDensity;
    clump += crackGrowth;

    // Organic thresholding: produces distinct patches of overgrown moss rather than a solid sheet
    float threshold = 0.42 + (1.0 - uniforms.mossDensity) * 0.22;
    float mossMask = smoothstep(threshold - 0.05, threshold + 0.05, clump);
    
    // Flat-surface moss applied to upward-facing horizontal planes (roofs, roads, terrain)
    mossMask *= smoothstep(0.25, 0.65, normal.y);

    // 5. Vertical Wall Overgrowth: Foundation Creep, Climbing Ivy, Drainage Runoff, & Ledges
    // Only apply wall effects to vertical and steeply angled surfaces (normal.y near 0)
    float isWall = smoothstep(0.70, 0.25, abs(normal.y));

    if (isWall > 0.01) {
        // Multi-faceted wall coordinate combining both horizontal facade dimensions
        float wallCoordX = worldPos.x * abs(normal.z) + worldPos.z * abs(normal.x);
        float2 wallUV = float2(wallCoordX, worldPos.y);

        // A. Foundation & Mid-Wall Creep: climbing up to 14.0 meters from ground level
        float wallBaseCreep = clamp(1.0 - worldPos.y / 14.0, 0.0, 1.0);
        float wallCreep = 0.0;
        if (wallBaseCreep > 0.01) {
            float creepNoise = fbm(wallUV * float2(0.28, 0.35), 3);
            wallCreep = wallBaseCreep * smoothstep(0.35, 0.62, creepNoise);
        }

        // B. Vertical Climbing Ivy & Vine Tendrils reaching up to 35+ meters
        float vineNoise = abs(perlinNoise(wallUV * float2(0.55, 0.14)));
        float vineCluster = fbm(wallUV * float2(0.16, 0.07), 2);
        float vines = (1.0 - smoothstep(0.015, 0.085, vineNoise)) * smoothstep(0.32, 0.62, vineCluster);

        // C. Vertical drainage runoff streaks from building rooftops and ledges
        float streakNoise = fbm(wallUV * float2(0.32, 0.04), 2);
        float streaks = smoothstep(0.48, 0.72, streakNoise) * 0.85;

        // D. Window ledges, decorative moldings, and architectural crevices
        float ledgeMoss = smoothstep(0.15, 0.50, normal.y) * smoothstep(0.85, 0.55, normal.y) * smoothstep(0.35, 0.65, nMicro);

        // Total wall moss coverage
        float totalWallMoss = (wallCreep * 1.35 + vines * 1.10 + streaks * 0.85 + ledgeMoss * 0.70) * uniforms.mossDensity * isWall;
        totalWallMoss = clamp(totalWallMoss, 0.0, 1.0);
        mossMask = max(mossMask, totalWallMoss);
    }

    // Damp dark decay halo along borders of moss patches
    float edgeDecay = smoothstep(threshold - 0.12, threshold - 0.02, clump) * (1.0 - mossMask);
    float3 decayedScene = mix(sceneColor.rgb, sceneColor.rgb * 0.40, edgeDecay * 0.75 * uniforms.weatheringAmount);

    // 7. Weathering, Grime & Desaturation for Post-Apocalyptic Mood
    float grimeNoise = fbm(worldPos.xz * 0.14 + worldPos.y * 0.08, 2);
    float luma = dot(decayedScene, float3(0.299, 0.587, 0.114));
    float3 weathered = mix(decayedScene, float3(luma * 0.90), uniforms.weatheringAmount * 0.35);
    weathered *= (1.0 - grimeNoise * 0.18 * uniforms.weatheringAmount);

    // 6. Multi-Palette Botanical Shading with High Color Variation
    // Evaluated only when moss is present, saving noise evaluation on clear surfaces
    float3 sceneWithMoss = weathered;
    if (mossMask > 0.001) {
        // Botanical color definitions
        float3 colDeepVelvet = float3(0.06, 0.16, 0.04);   // Dark, moist sheltered moss
        float3 colLushEmerald = float3(0.24, 0.52, 0.13);  // Vibrant active spring moss
        float3 colBuddingTip  = float3(0.58, 0.74, 0.16);  // Chartreuse youthful sporing highlights
        float3 colGoldLichen  = float3(0.84, 0.68, 0.16);  // Warm xanthoria / golden sun lichen
        float3 colSageLichen  = float3(0.38, 0.55, 0.44);  // Pale crustose mint/sage lichen
        float3 colDryPeat     = float3(0.34, 0.22, 0.10);  // Decayed brownish-ochre dry vegetation
        float3 colIvyGreen    = float3(0.11, 0.28, 0.10);  // Darker waxy ivy leaves on building facades

        // Independent chromatic noise field (uncorrelated with mask boundaries)
        float nColorMacro = fbm(worldPos.xz * uniforms.mossScale * 1.6 + float2(13.7, 47.1), 2);
        float nColorMicro = perlinNoise(worldPos.xz * uniforms.mossScale * 6.8 + float2(89.3, 12.9));
        float nLichenSpots = fbm(worldPos.xz * uniforms.mossScale * 3.4 + float2(51.2, 73.6), 2);

        // Base vegetative gradient between deep velvet and vibrant emerald
        float3 baseMoss = mix(colDeepVelvet, colLushEmerald, smoothstep(0.25, 0.70, nMicro));

        // Blend in dry ochre/peat patches in exposed areas
        baseMoss = mix(baseMoss, colDryPeat, smoothstep(0.18, 0.35, nColorMacro) * (1.0 - smoothstep(0.35, 0.52, nColorMacro)) * 0.85);

        // Blend in golden xanthoria lichen colonies
        baseMoss = mix(baseMoss, colGoldLichen, smoothstep(0.62, 0.78, nLichenSpots));

        // Blend in pale sage/mint crustose lichen patches
        baseMoss = mix(baseMoss, colSageLichen, smoothstep(0.68, 0.84, nColorMacro));

        // Bright chartreuse budding tips / sporing highlights on micro crests
        baseMoss = mix(baseMoss, colBuddingTip, smoothstep(0.35, 0.75, nColorMicro) * 0.65);

        // For vertical building facades, blend towards deeper waxy ivy foliage
        float3 mossColor = mix(baseMoss, colIvyGreen, isWall * 0.45);

        sceneWithMoss = mix(weathered, mossColor, mossMask);
    }

    // 8. Screen Space Ambient Occlusion (SSAO)
    // Darkens building base seams, inner corners, alleyways, and architectural crevices
    float ao = evaluateSSAO(worldPos, normal, in.texCoord, sceneDepthTexture, pointSampler, uniforms);
    float aoMultiplier = mix(0.35, 1.0, ao);
    float3 occludedScene = sceneWithMoss * aoMultiplier;

    // 9. Distance Fog (Atmospheric Post-Apocalyptic Haze)
    float dist = length(worldPos - uniforms.cameraPosition.xyz);
    float fog = 1.0 - exp(-dist * uniforms.fogDensity);
    float3 finalScene = mix(occludedScene, uniforms.skyFogColor.rgb, clamp(fog, 0.0, 1.0));

    // 10. Cinematic Edge Vignette
    float2 vigUV = in.texCoord * (1.0 - in.texCoord);
    float vignette = vigUV.x * vigUV.y * 15.0;
    vignette = clamp(pow(vignette, 0.16), 0.0, 1.0);
    finalScene *= mix(0.70, 1.0, vignette);

    return float4(finalScene, 1.0);
}
