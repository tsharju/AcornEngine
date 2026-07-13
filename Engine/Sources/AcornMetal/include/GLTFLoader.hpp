#pragma once
#include <string>
#include <vector>
#include "Mesh.hpp"

namespace Acorn {
    class GLTFLoader {
    public:
        static std::vector<AcornMetalMesh*> load(const std::string& path, void* devicePtr, const void** outTextureData = nullptr, int* outTextureSize = nullptr);
        static int loadRaw(const char* path, void* devicePtr, void** outMeshes, int maxMeshes, const void** outTextureData, int* outTextureSize);
    };
}
