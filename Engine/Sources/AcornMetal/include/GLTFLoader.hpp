#pragma once
#include <string>
#include <vector>
#include "Mesh.hpp"

namespace Acorn {
    class GLTFLoader {
    public:
        static std::vector<AcornMetalMesh*> load(const std::string& path, void* devicePtr);
    };
}
