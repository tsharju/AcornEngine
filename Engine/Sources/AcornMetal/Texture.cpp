#include "Texture.hpp"
#include <Metal/Metal.hpp>

namespace Acorn {
    AcornMetalTexture* AcornMetalTexture::create(void* texturePtr) {
        return new AcornMetalTexture(texturePtr);
    }

    void AcornMetalTexture::destroy() {
        delete this;
    }

    AcornMetalTexture::AcornMetalTexture(void* texturePtr) : texture(texturePtr), width(0), height(0) {
        if (this->texture) {
            ((MTL::Texture*)this->texture)->retain();
            width = ((MTL::Texture*)this->texture)->width();
            height = ((MTL::Texture*)this->texture)->height();
        }
    }

    AcornMetalTexture::~AcornMetalTexture() {
        if (this->texture) {
            ((MTL::Texture*)this->texture)->release();
        }
    }
}
