#pragma once
#include <string>
#include <vector>
#include <stdint.h>
#include "Mesh.hpp"

namespace Acorn {
    struct GLTFNodeData {
        char name[64];
        int meshIndex;     // -1 if none
        int parentIndex;   // -1 if none
        int skinIndex;     // -1 if none
        float translation[3];
        float rotation[4]; // x, y, z, w
        float scale[3];
    };

    enum class GLTFAnimationPath : uint8_t {
        Translation = 1,
        Rotation = 2,
        Scale = 3,
        Weights = 4
    };

    enum class GLTFInterpolation : uint8_t {
        Linear = 0,
        Step = 1,
        CubicSpline = 2
    };

    struct GLTFChannelData {
        int nodeIndex; // Index into outNodes
        uint8_t path;  // 1: Translation, 2: Rotation, 3: Scale, 4: Weights
        uint8_t interpolation; // 0: Linear, 1: Step, 2: CubicSpline
        int keyframeCount;
        const float* timestamps;
        const float* values;
        int valuesPerKeyframe;
    };

    struct GLTFAnimationData {
        char name[64];
        float duration;
        int channelCount;
        GLTFChannelData* channels;
    };

    struct GLTFAnimationContainer {
        int animationCount;
        GLTFAnimationData* animations;
    };

    struct GLTFSkinData {
        char name[64];
        int jointCount;
        int* jointNodeIndices;
        float* inverseBindMatrices; // 16 floats per joint
    };

    struct GLTFSkinContainer {
        int skinCount;
        GLTFSkinData* skins;
    };

    class GLTFLoader {
    public:
        static std::vector<AcornMetalMesh*> load(
            const std::string& path, 
            void* devicePtr, 
            std::vector<GLTFNodeData>& outNodes,
            const void** outTextureData = nullptr, 
            int* outTextureSize = nullptr,
            GLTFAnimationContainer* outAnimations = nullptr,
            GLTFSkinContainer* outSkins = nullptr
        );
        
        static int loadRaw(
            const char* path, 
            void* devicePtr, 
            void** outMeshes, 
            int maxMeshes, 
            GLTFNodeData* outNodes, 
            int maxNodes, 
            int* outNodeCount,
            const void** outTextureData, 
            int* outTextureSize,
            GLTFAnimationContainer* outAnimations = nullptr,
            GLTFSkinContainer* outSkins = nullptr
        );

        static void freeAnimationContainer(GLTFAnimationContainer* container);
        static void freeSkinContainer(GLTFSkinContainer* container);
    };
}
