#pragma once
#include <string>
#include <vector>
#include "Mesh.hpp"

namespace Acorn {
    struct GLTFNodeData {
        char name[64];
        int meshIndex;     // -1 if none
        int parentIndex;   // -1 if none
        float translation[3];
        float rotation[4]; // x, y, z, w
        float scale[3];
    };

    class GLTFLoader {
    public:
        static std::vector<AcornMetalMesh*> load(
            const std::string& path, 
            void* devicePtr, 
            std::vector<GLTFNodeData>& outNodes,
            const void** outTextureData = nullptr, 
            int* outTextureSize = nullptr
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
            int* outTextureSize
        );
    };
}
