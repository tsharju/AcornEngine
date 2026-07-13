#include "Mesh.hpp"
#include <Metal/Metal.hpp>
#include <algorithm>

namespace Acorn {
    AcornMetalMesh* AcornMetalMesh::create(void* devicePtr, size_t vertexCount, void* vertexBufferPtr, void* indexBufferPtr, size_t indexCount) {
        return new AcornMetalMesh(devicePtr, vertexCount, vertexBufferPtr, indexBufferPtr, indexCount);
    }

    void AcornMetalMesh::destroy() {
        delete this;
    }

    AcornMetalMesh::AcornMetalMesh(void* devicePtr, size_t vertexCount, void* vertexBufferPtr, void* indexBufferPtr, size_t indexCount)
        : device(devicePtr), vertexCount(vertexCount), vertexBuffer(vertexBufferPtr), indexBuffer(indexBufferPtr), indexCount(indexCount), vertexDescriptor(nullptr) {
#ifndef NDEBUG
        debugVertexData = nullptr;
        debugVertexCount = 0;
        debugIndexData = nullptr;
        debugIndexCount = 0;
#endif
        if (this->device) {
            ((MTL::Device*)this->device)->retain();
        }
        if (this->vertexBuffer) {
            ((MTL::Buffer*)this->vertexBuffer)->retain();
        }
        if (this->indexBuffer) {
            ((MTL::Buffer*)this->indexBuffer)->retain();
        }
    }

    AcornMetalMesh::~AcornMetalMesh() {
        if (this->device) ((MTL::Device*)this->device)->release();
        if (this->vertexBuffer) ((MTL::Buffer*)this->vertexBuffer)->release();
        if (this->indexBuffer) ((MTL::Buffer*)this->indexBuffer)->release();
        if (this->vertexDescriptor) ((MTL::VertexDescriptor*)this->vertexDescriptor)->release();
#ifndef NDEBUG
        if (debugVertexData) delete[] debugVertexData;
        if (debugIndexData) delete[] debugIndexData;
#endif
    }

    void AcornMetalMesh::setVertexDescriptor(void* descPtr) {
        MTL::VertexDescriptor* desc = (MTL::VertexDescriptor*)descPtr;
        if (this->vertexDescriptor) {
            ((MTL::VertexDescriptor*)this->vertexDescriptor)->release();
        }
        this->vertexDescriptor = desc;
        if (this->vertexDescriptor) {
            ((MTL::VertexDescriptor*)this->vertexDescriptor)->retain();
        }
    }

#ifndef NDEBUG
    void AcornMetalMesh::setDebugVertexData(const float* data, size_t count) {
        if (debugVertexData) delete[] debugVertexData;
        debugVertexData = new float[count];
        std::copy(data, data + count, debugVertexData);
        debugVertexCount = count;
    }
    
    const float* AcornMetalMesh::getDebugVertexData() const {
        return debugVertexData;
    }
    
    size_t AcornMetalMesh::getDebugVertexDataCount() const {
        return debugVertexCount;
    }
    
    void AcornMetalMesh::setDebugIndexData(const uint32_t* data, size_t count) {
        if (debugIndexData) delete[] debugIndexData;
        debugIndexData = new uint32_t[count];
        std::copy(data, data + count, debugIndexData);
        debugIndexCount = count;
    }
    
    const uint32_t* AcornMetalMesh::getDebugIndexData() const {
        return debugIndexData;
    }
    
    size_t AcornMetalMesh::getDebugIndexDataCount() const {
        return debugIndexCount;
    }
#endif
}
