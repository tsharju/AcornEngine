#pragma once
#include "Mesh.hpp"
#include "Texture.hpp"
#include "Uniforms.hpp"

namespace Acorn {
    class AcornMetalRenderer {
    public:
        AcornMetalRenderer(void* devicePtr, void* libraryPtr, unsigned long pixelFormat = 80); // 80 is MTL::PixelFormatBGRA8Unorm_sRGB
        ~AcornMetalRenderer();

        static AcornMetalRenderer* create(void* devicePtr, void* libraryPtr, unsigned long pixelFormat = 80);
        void destroy();

        void render(AcornMetalMesh* mesh, const GlobalUniforms& uniforms, void* encoderPtr);
        void renderText(AcornMetalMesh* mesh, AcornMetalTexture* texture, const SDFUniforms& uniforms, void* encoderPtr);
        void renderSprite(AcornMetalMesh* mesh, AcornMetalTexture* texture, const SpriteUniforms& uniforms, void* encoderPtr);

    private:
        void* device;
        void* library;
        unsigned long pixelFormat;
        
        void* depthStencilState;
        void* transparentDepthStencilState;
        
        void* sdfTextPipelineState;
        void* spritePipelineState;
        void* defaultPipelineState;
        
        void* vertexFunction;
        void* fragmentFunction;
        
        void* getOrCreatePipelineState(void* vertexDescriptor);
    };
}
