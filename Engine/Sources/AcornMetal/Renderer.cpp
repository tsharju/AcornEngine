#include "Renderer.hpp"
#include <Metal/Metal.hpp>
#include <iostream>

namespace Acorn {
    AcornMetalRenderer* AcornMetalRenderer::create(void* devicePtr, void* libraryPtr, unsigned long pixelFormat) {
        return new AcornMetalRenderer(devicePtr, libraryPtr, pixelFormat);
    }

    void AcornMetalRenderer::destroy() {
        delete this;
    }

    AcornMetalRenderer::AcornMetalRenderer(void* devicePtr, void* libraryPtr, unsigned long pixelFormat)
        : device((MTL::Device*)devicePtr), library((MTL::Library*)libraryPtr), pixelFormat(pixelFormat), defaultPipelineState(nullptr),
          instancedMeshPipelineState(nullptr), instancedSpritePipelineState(nullptr) {
        
        if (this->device) ((MTL::Device*)this->device)->retain();
        if (this->library) ((MTL::Library*)this->library)->retain();
        
        vertexFunction = ((MTL::Library*)library)->newFunction(NS::String::string("vertex_main", NS::UTF8StringEncoding));
        fragmentFunction = ((MTL::Library*)library)->newFunction(NS::String::string("fragment_main", NS::UTF8StringEncoding));
        
        MTL::RenderPipelineDescriptor* pipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
        pipelineDescriptor->setLabel(NS::String::string("Forward Pipeline", NS::UTF8StringEncoding));
        pipelineDescriptor->setVertexFunction((MTL::Function*)vertexFunction);
        pipelineDescriptor->setFragmentFunction((MTL::Function*)fragmentFunction);
        pipelineDescriptor->colorAttachments()->object(0)->setPixelFormat((MTL::PixelFormat)pixelFormat);
        pipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);
        
        NS::Error* error = nullptr;
        defaultPipelineState = ((MTL::Device*)device)->newRenderPipelineState(pipelineDescriptor, &error);
        if (error) {
            std::cerr << "Failed to create default pipeline state: " << error->localizedDescription()->utf8String() << std::endl;
        }
        pipelineDescriptor->release();
        
        MTL::DepthStencilDescriptor* depthStencilDesc = MTL::DepthStencilDescriptor::alloc()->init();
        depthStencilDesc->setDepthCompareFunction(MTL::CompareFunctionLess);
        depthStencilDesc->setDepthWriteEnabled(true);
        depthStencilState = ((MTL::Device*)device)->newDepthStencilState(depthStencilDesc);
        depthStencilDesc->release();
        
        MTL::DepthStencilDescriptor* transparentDepthDesc = MTL::DepthStencilDescriptor::alloc()->init();
        transparentDepthDesc->setDepthCompareFunction(MTL::CompareFunctionLess);
        transparentDepthDesc->setDepthWriteEnabled(false);
        transparentDepthStencilState = ((MTL::Device*)device)->newDepthStencilState(transparentDepthDesc);
        transparentDepthDesc->release();
        
        // SDF Pipeline
        MTL::Function* sdfVertexFunction = ((MTL::Library*)library)->newFunction(NS::String::string("sdf_vertex", NS::UTF8StringEncoding));
        MTL::Function* sdfFragmentFunction = ((MTL::Library*)library)->newFunction(NS::String::string("sdf_fragment", NS::UTF8StringEncoding));
        
        MTL::RenderPipelineDescriptor* sdfPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
        sdfPipelineDescriptor->setLabel(NS::String::string("SDF Text Pipeline", NS::UTF8StringEncoding));
        sdfPipelineDescriptor->setVertexFunction(sdfVertexFunction);
        sdfPipelineDescriptor->setFragmentFunction(sdfFragmentFunction);
        
        MTL::RenderPipelineColorAttachmentDescriptor* colorAttachment = sdfPipelineDescriptor->colorAttachments()->object(0);
        colorAttachment->setPixelFormat((MTL::PixelFormat)pixelFormat);
        colorAttachment->setBlendingEnabled(true);
        colorAttachment->setSourceRGBBlendFactor(MTL::BlendFactorSourceAlpha);
        colorAttachment->setDestinationRGBBlendFactor(MTL::BlendFactorOneMinusSourceAlpha);
        colorAttachment->setRgbBlendOperation(MTL::BlendOperationAdd);
        colorAttachment->setSourceAlphaBlendFactor(MTL::BlendFactorSourceAlpha);
        colorAttachment->setDestinationAlphaBlendFactor(MTL::BlendFactorOneMinusSourceAlpha);
        colorAttachment->setAlphaBlendOperation(MTL::BlendOperationAdd);
        
        sdfPipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);
        
        sdfTextPipelineState = ((MTL::Device*)device)->newRenderPipelineState(sdfPipelineDescriptor, &error);
        if (error) {
            std::cerr << "Failed to create SDF pipeline state: " << error->localizedDescription()->utf8String() << std::endl;
        }
        sdfPipelineDescriptor->release();
        sdfVertexFunction->release();
        sdfFragmentFunction->release();
        
        // Sprite Pipeline
        MTL::Function* spriteVertexFunction = ((MTL::Library*)library)->newFunction(NS::String::string("sprite_vertex", NS::UTF8StringEncoding));
        MTL::Function* spriteFragmentFunction = ((MTL::Library*)library)->newFunction(NS::String::string("sprite_fragment", NS::UTF8StringEncoding));
        
        MTL::RenderPipelineDescriptor* spritePipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
        spritePipelineDescriptor->setLabel(NS::String::string("Sprite Pipeline", NS::UTF8StringEncoding));
        spritePipelineDescriptor->setVertexFunction(spriteVertexFunction);
        spritePipelineDescriptor->setFragmentFunction(spriteFragmentFunction);
        
        MTL::RenderPipelineColorAttachmentDescriptor* spriteColorAttachment = spritePipelineDescriptor->colorAttachments()->object(0);
        spriteColorAttachment->setPixelFormat((MTL::PixelFormat)pixelFormat);
        spriteColorAttachment->setBlendingEnabled(true);
        spriteColorAttachment->setSourceRGBBlendFactor(MTL::BlendFactorSourceAlpha);
        spriteColorAttachment->setDestinationRGBBlendFactor(MTL::BlendFactorOneMinusSourceAlpha);
        spriteColorAttachment->setRgbBlendOperation(MTL::BlendOperationAdd);
        spriteColorAttachment->setSourceAlphaBlendFactor(MTL::BlendFactorSourceAlpha);
        spriteColorAttachment->setDestinationAlphaBlendFactor(MTL::BlendFactorOneMinusSourceAlpha);
        spriteColorAttachment->setAlphaBlendOperation(MTL::BlendOperationAdd);
        
        spritePipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);
        
        spritePipelineState = ((MTL::Device*)device)->newRenderPipelineState(spritePipelineDescriptor, &error);
        if (error) {
            std::cerr << "Failed to create Sprite pipeline state: " << error->localizedDescription()->utf8String() << std::endl;
        }
        spritePipelineDescriptor->release();
        spriteVertexFunction->release();
        spriteFragmentFunction->release();

        // Instanced Mesh Pipeline
        MTL::Function* instancedMeshVertexFunction = ((MTL::Library*)library)->newFunction(NS::String::string("instanced_vertex_main", NS::UTF8StringEncoding));
        MTL::Function* instancedMeshFragmentFunction = ((MTL::Library*)library)->newFunction(NS::String::string("instanced_fragment_main", NS::UTF8StringEncoding));
        
        MTL::RenderPipelineDescriptor* instancedMeshPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
        instancedMeshPipelineDescriptor->setLabel(NS::String::string("Instanced Mesh Pipeline", NS::UTF8StringEncoding));
        instancedMeshPipelineDescriptor->setVertexFunction(instancedMeshVertexFunction);
        instancedMeshPipelineDescriptor->setFragmentFunction(instancedMeshFragmentFunction);
        instancedMeshPipelineDescriptor->colorAttachments()->object(0)->setPixelFormat((MTL::PixelFormat)pixelFormat);
        instancedMeshPipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);
        
        instancedMeshPipelineState = ((MTL::Device*)device)->newRenderPipelineState(instancedMeshPipelineDescriptor, &error);
        if (error) {
            std::cerr << "Failed to create instanced mesh pipeline state: " << error->localizedDescription()->utf8String() << std::endl;
        }
        instancedMeshPipelineDescriptor->release();
        if (instancedMeshVertexFunction) instancedMeshVertexFunction->release();
        if (instancedMeshFragmentFunction) instancedMeshFragmentFunction->release();

        // Instanced Sprite Pipeline
        MTL::Function* instancedSpriteVertexFunction = ((MTL::Library*)library)->newFunction(NS::String::string("sprite_vertex_instanced", NS::UTF8StringEncoding));
        MTL::Function* instancedSpriteFragmentFunction = ((MTL::Library*)library)->newFunction(NS::String::string("sprite_fragment", NS::UTF8StringEncoding));
        
        MTL::RenderPipelineDescriptor* instancedSpritePipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
        instancedSpritePipelineDescriptor->setLabel(NS::String::string("Instanced Sprite Pipeline", NS::UTF8StringEncoding));
        instancedSpritePipelineDescriptor->setVertexFunction(instancedSpriteVertexFunction);
        instancedSpritePipelineDescriptor->setFragmentFunction(instancedSpriteFragmentFunction);
        
        MTL::RenderPipelineColorAttachmentDescriptor* instancedSpriteColorAttachment = instancedSpritePipelineDescriptor->colorAttachments()->object(0);
        instancedSpriteColorAttachment->setPixelFormat((MTL::PixelFormat)pixelFormat);
        instancedSpriteColorAttachment->setBlendingEnabled(true);
        instancedSpriteColorAttachment->setSourceRGBBlendFactor(MTL::BlendFactorSourceAlpha);
        instancedSpriteColorAttachment->setDestinationRGBBlendFactor(MTL::BlendFactorOneMinusSourceAlpha);
        instancedSpriteColorAttachment->setRgbBlendOperation(MTL::BlendOperationAdd);
        instancedSpriteColorAttachment->setSourceAlphaBlendFactor(MTL::BlendFactorSourceAlpha);
        instancedSpriteColorAttachment->setDestinationAlphaBlendFactor(MTL::BlendFactorOneMinusSourceAlpha);
        instancedSpriteColorAttachment->setAlphaBlendOperation(MTL::BlendOperationAdd);
        
        instancedSpritePipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);
        
        instancedSpritePipelineState = ((MTL::Device*)device)->newRenderPipelineState(instancedSpritePipelineDescriptor, &error);
        if (error) {
            std::cerr << "Failed to create instanced sprite pipeline state: " << error->localizedDescription()->utf8String() << std::endl;
        }
        instancedSpritePipelineDescriptor->release();
        if (instancedSpriteVertexFunction) instancedSpriteVertexFunction->release();
        if (instancedSpriteFragmentFunction) instancedSpriteFragmentFunction->release();
    }

    AcornMetalRenderer::~AcornMetalRenderer() {
        if (this->device) ((MTL::Device*)this->device)->release();
        if (this->library) ((MTL::Library*)this->library)->release();
        if (this->depthStencilState) ((MTL::DepthStencilState*)this->depthStencilState)->release();
        if (this->transparentDepthStencilState) ((MTL::DepthStencilState*)this->transparentDepthStencilState)->release();
        if (this->sdfTextPipelineState) ((MTL::RenderPipelineState*)this->sdfTextPipelineState)->release();
        if (this->spritePipelineState) ((MTL::RenderPipelineState*)this->spritePipelineState)->release();
        if (this->instancedMeshPipelineState) ((MTL::RenderPipelineState*)this->instancedMeshPipelineState)->release();
        if (this->instancedSpritePipelineState) ((MTL::RenderPipelineState*)this->instancedSpritePipelineState)->release();
        if (this->defaultPipelineState) ((MTL::RenderPipelineState*)this->defaultPipelineState)->release();
        if (this->vertexFunction) ((MTL::Function*)this->vertexFunction)->release();
        if (this->fragmentFunction) ((MTL::Function*)this->fragmentFunction)->release();
    }

    void* AcornMetalRenderer::getOrCreatePipelineState(void* vertexDescriptorPtr) {
        MTL::VertexDescriptor* vertexDescriptor = (MTL::VertexDescriptor*)vertexDescriptorPtr;
        if (!vertexDescriptor) {
            return defaultPipelineState;
        }
        // Ideally we would cache this using the vertexDescriptor as a key.
        // For simplicity, we just create a new one here if it doesn't match default.
        // In a real engine, we'd want a proper hash map.
        MTL::RenderPipelineDescriptor* pipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
        pipelineDescriptor->setLabel(NS::String::string("Forward Pipeline (Custom Vert)", NS::UTF8StringEncoding));
        pipelineDescriptor->setVertexFunction((MTL::Function*)vertexFunction);
        pipelineDescriptor->setFragmentFunction((MTL::Function*)fragmentFunction);
        pipelineDescriptor->colorAttachments()->object(0)->setPixelFormat((MTL::PixelFormat)pixelFormat);
        pipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);
        pipelineDescriptor->setVertexDescriptor(vertexDescriptor);
        
        NS::Error* error = nullptr;
        MTL::RenderPipelineState* state = ((MTL::Device*)device)->newRenderPipelineState(pipelineDescriptor, &error);
        pipelineDescriptor->release();
        
        return state; // Caller must release this or we leak. Proper caching needed.
    }

    void AcornMetalRenderer::render(AcornMetalMesh* mesh, AcornMetalTexture* texture, const GlobalUniforms& uniforms, void* encoderPtr) {
        MTL::RenderCommandEncoder* encoder = (MTL::RenderCommandEncoder*)encoderPtr;
        if (!mesh || !encoder) return;
        
        MTL::RenderPipelineState* state = (MTL::RenderPipelineState*)defaultPipelineState;
        bool customState = false;
        
        if (mesh->getVertexDescriptor()) {
            state = (MTL::RenderPipelineState*)getOrCreatePipelineState(mesh->getVertexDescriptor());
            customState = true;
        }
        
        encoder->setRenderPipelineState(state);
        encoder->setDepthStencilState((MTL::DepthStencilState*)depthStencilState);
        
        encoder->setVertexBuffer((MTL::Buffer*)mesh->getVertexBuffer(), 0, 0);
        
        encoder->setVertexBytes(&uniforms, sizeof(GlobalUniforms), 1);
        encoder->setFragmentBytes(&uniforms, sizeof(GlobalUniforms), 0);
        
        if (texture) {
            encoder->setFragmentTexture((MTL::Texture*)texture->getTexture(), 0);
        }
        
        if (mesh->getIndexBuffer()) {
            encoder->drawIndexedPrimitives(MTL::PrimitiveTypeTriangle, mesh->getIndexCount(), MTL::IndexTypeUInt32, (MTL::Buffer*)mesh->getIndexBuffer(), 0);
        } else {
            encoder->drawPrimitives(MTL::PrimitiveTypeTriangle, (NS::UInteger)0, (NS::UInteger)mesh->getVertexCount());
        }
        
        if (customState) {
            state->release();
        }
    }

    void AcornMetalRenderer::renderText(AcornMetalMesh* mesh, AcornMetalTexture* texture, const SDFUniforms& uniforms, void* encoderPtr) {
        MTL::RenderCommandEncoder* encoder = (MTL::RenderCommandEncoder*)encoderPtr;
        if (!mesh || !texture || !encoder) return;
        
        encoder->setRenderPipelineState((MTL::RenderPipelineState*)sdfTextPipelineState);
        encoder->setDepthStencilState((MTL::DepthStencilState*)transparentDepthStencilState);
        
        encoder->setVertexBuffer((MTL::Buffer*)mesh->getVertexBuffer(), 0, 0);
        
        // Bind the SDF Font texture atlas
        encoder->setFragmentTexture((MTL::Texture*)texture->getTexture(), 0);
        
        encoder->setVertexBytes(&uniforms, sizeof(SDFUniforms), 1);
        encoder->setFragmentBytes(&uniforms, sizeof(SDFUniforms), 0);
        
        encoder->drawPrimitives(MTL::PrimitiveTypeTriangle, (NS::UInteger)0, (NS::UInteger)mesh->getVertexCount());
    }

    void AcornMetalRenderer::renderSprite(AcornMetalMesh* mesh, AcornMetalTexture* texture, const SpriteUniforms& uniforms, void* encoderPtr) {
        MTL::RenderCommandEncoder* encoder = (MTL::RenderCommandEncoder*)encoderPtr;
        if (!mesh || !texture || !encoder) return;
        
        encoder->setRenderPipelineState((MTL::RenderPipelineState*)spritePipelineState);
        encoder->setDepthStencilState((MTL::DepthStencilState*)transparentDepthStencilState);
        
        encoder->setVertexBuffer((MTL::Buffer*)mesh->getVertexBuffer(), 0, 0);
        
        // Bind the sprite texture
        encoder->setFragmentTexture((MTL::Texture*)texture->getTexture(), 0);
        
        encoder->setVertexBytes(&uniforms, sizeof(SpriteUniforms), 1);
        
        encoder->drawPrimitives(MTL::PrimitiveTypeTriangle, (NS::UInteger)0, (NS::UInteger)mesh->getVertexCount());
    }

    void AcornMetalRenderer::renderInstanced(AcornMetalMesh* mesh, AcornMetalTexture* texture, const MeshInstanceData* instances, size_t instanceCount, const FrameUniforms& uniforms, void* encoderPtr) {
        MTL::RenderCommandEncoder* encoder = (MTL::RenderCommandEncoder*)encoderPtr;
        if (!mesh || !encoder || !instances || instanceCount == 0) return;
        
        encoder->setRenderPipelineState((MTL::RenderPipelineState*)instancedMeshPipelineState);
        encoder->setDepthStencilState((MTL::DepthStencilState*)depthStencilState);
        
        encoder->setVertexBuffer((MTL::Buffer*)mesh->getVertexBuffer(), 0, 0);
        size_t instancesByteSize = sizeof(MeshInstanceData) * instanceCount;
        if (instancesByteSize <= 4096) {
            encoder->setVertexBytes(instances, instancesByteSize, 1);
        } else {
            MTL::Buffer* instanceBuffer = ((MTL::Device*)device)->newBuffer(instances, instancesByteSize, MTL::ResourceStorageModeShared);
            encoder->setVertexBuffer(instanceBuffer, 0, 1);
            instanceBuffer->release();
        }
        encoder->setVertexBytes(&uniforms, sizeof(FrameUniforms), 2);
        encoder->setFragmentBytes(&uniforms, sizeof(FrameUniforms), 0);
        
        if (texture) {
            encoder->setFragmentTexture((MTL::Texture*)texture->getTexture(), 0);
        }
        
        if (mesh->getIndexBuffer()) {
            encoder->drawIndexedPrimitives(MTL::PrimitiveTypeTriangle, mesh->getIndexCount(), MTL::IndexTypeUInt32, (MTL::Buffer*)mesh->getIndexBuffer(), 0, instanceCount);
        } else {
            encoder->drawPrimitives(MTL::PrimitiveTypeTriangle, (NS::UInteger)0, (NS::UInteger)mesh->getVertexCount(), instanceCount);
        }
    }

    void AcornMetalRenderer::renderSpritesInstanced(AcornMetalMesh* mesh, AcornMetalTexture* texture, const SpriteInstanceData* instances, size_t instanceCount, const SpriteFrameUniforms& uniforms, void* encoderPtr) {
        MTL::RenderCommandEncoder* encoder = (MTL::RenderCommandEncoder*)encoderPtr;
        if (!mesh || !encoder || !instances || instanceCount == 0) return;
        
        encoder->setRenderPipelineState((MTL::RenderPipelineState*)instancedSpritePipelineState);
        encoder->setDepthStencilState((MTL::DepthStencilState*)transparentDepthStencilState);
        
        encoder->setVertexBuffer((MTL::Buffer*)mesh->getVertexBuffer(), 0, 0);
        size_t instancesByteSize = sizeof(SpriteInstanceData) * instanceCount;
        if (instancesByteSize <= 4096) {
            encoder->setVertexBytes(instances, instancesByteSize, 1);
        } else {
            MTL::Buffer* instanceBuffer = ((MTL::Device*)device)->newBuffer(instances, instancesByteSize, MTL::ResourceStorageModeShared);
            encoder->setVertexBuffer(instanceBuffer, 0, 1);
            instanceBuffer->release();
        }
        encoder->setVertexBytes(&uniforms, sizeof(SpriteFrameUniforms), 2);
        
        if (texture) {
            encoder->setFragmentTexture((MTL::Texture*)texture->getTexture(), 0);
        }
        
        encoder->drawPrimitives(MTL::PrimitiveTypeTriangle, (NS::UInteger)0, (NS::UInteger)mesh->getVertexCount(), instanceCount);
    }
}
