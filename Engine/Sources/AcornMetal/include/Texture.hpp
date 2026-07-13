#pragma once

namespace Acorn {
    class AcornMetalTexture {
    public:
        AcornMetalTexture(void* texturePtr);
        ~AcornMetalTexture();

        static AcornMetalTexture* create(void* texturePtr);
        void destroy();

        void* getTexture() const { return texture; }
        int getWidth() const { return width; }
        int getHeight() const { return height; }

    private:
        void* texture;
        int width;
        int height;
    };
}
