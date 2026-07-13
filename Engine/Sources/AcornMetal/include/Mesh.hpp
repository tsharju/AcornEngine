#pragma once
#include <stdint.h>
#include <stddef.h>

namespace Acorn {
    class AcornMetalMesh {
    public:
        AcornMetalMesh(void* devicePtr, size_t vertexCount, void* vertexBufferPtr, void* indexBufferPtr = nullptr, size_t indexCount = 0);
        ~AcornMetalMesh();

        static AcornMetalMesh* create(void* devicePtr, size_t vertexCount, void* vertexBufferPtr, void* indexBufferPtr = nullptr, size_t indexCount = 0);
        void destroy();

        size_t getVertexCount() const { return vertexCount; }
        size_t getIndexCount() const { return indexCount; }
        void* getVertexBuffer() const { return vertexBuffer; }
        void* getIndexBuffer() const { return indexBuffer; }
        
        void setVertexDescriptor(void* desc);
        void* getVertexDescriptor() const { return vertexDescriptor; }

#ifndef NDEBUG
        // Editor needs access to raw vertex data for wireframe rendering
        void setDebugVertexData(const float* data, size_t count);
        const float* getDebugVertexData() const;
        size_t getDebugVertexDataCount() const;
        
        void setDebugIndexData(const uint32_t* data, size_t count);
        const uint32_t* getDebugIndexData() const;
        size_t getDebugIndexDataCount() const;
#endif

    private:
        size_t vertexCount;
        size_t indexCount;
        void* device;
        void* vertexBuffer;
        void* indexBuffer;
        void* vertexDescriptor;
        
#ifndef NDEBUG
        float* debugVertexData;
        size_t debugVertexCount;
        uint32_t* debugIndexData;
        size_t debugIndexCount;
#endif
    };
}
