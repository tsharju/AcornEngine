#include "AcornRHI/AcornRHI.h"
#include "../AcornEngine/Renderer/Shaders/acorn_shared.h"

#include <NoGraphicsAPI/NoGraphicsAPI.hpp>
#include <NoGraphicsAPIUtility/bump_allocator.hpp>
#include <NoGraphicsAPIUtility/heap_allocator.hpp>
#include <NoGraphicsAPIUtility/texture_allocator.hpp>
#include <NoGraphicsAPIUtility/upload_queue.hpp>

#include <algorithm>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

static_assert(sizeof(AcornRHIGlobalUniforms) == sizeof(AcornGpuGlobalUniforms));
static_assert(sizeof(AcornRHISdfUniforms) == sizeof(AcornGpuSdfUniforms));
static_assert(sizeof(AcornRHISpriteUniforms) == sizeof(AcornGpuSpriteUniforms));
static_assert(sizeof(AcornRHIFrameUniforms) == sizeof(AcornGpuFrameUniforms));
static_assert(sizeof(AcornRHIMeshInstanceData) == sizeof(AcornGpuMeshInstanceData));
static_assert(sizeof(AcornRHISpriteFrameUniforms) == sizeof(AcornGpuSpriteFrameUniforms));
static_assert(sizeof(AcornRHISpriteInstanceData) == sizeof(AcornGpuSpriteInstanceData));
static_assert(sizeof(AcornRHIRoadUniforms) == sizeof(AcornGpuRoadUniforms));

namespace {

constexpr uint32 kFramesInFlight = 2;
constexpr uint64 kFrameHeapBytes = 8ull * 1024 * 1024;
constexpr uint64 kMeshSlabBytes = 32ull * 1024 * 1024;
constexpr uint64 kTextureSlabBytes = 128ull * 1024 * 1024;
constexpr uint64 kUploadQueueBytes = 32ull * 1024 * 1024;
constexpr uint32 kTextureDescriptorCapacity = 2048;
constexpr uint32 kSamplerDescriptorCapacity = 8;

constexpr uint32 kSamplerClampLinear = 0;
constexpr uint32 kSamplerRepeatLinear = 1;

void onGpuError(const char* message, bool fatal) noexcept {
    std::fprintf(stderr, "[NoGraphicsAPI%s] %s\n", fatal ? " FATAL" : "", message ? message : "(null)");
}

gpu::Format toGpuFormat(AcornRHIPixelFormat format) noexcept {
    switch (format) {
        case ACORN_RHI_PIXEL_FORMAT_BGRA8_UNORM: return gpu::Format::bgra8_unorm;
        case ACORN_RHI_PIXEL_FORMAT_BGRA8_SRGB:  return gpu::Format::bgra8_srgb;
        case ACORN_RHI_PIXEL_FORMAT_RGBA8_UNORM: return gpu::Format::rgba8_unorm;
        case ACORN_RHI_PIXEL_FORMAT_R8_UNORM:    return gpu::Format::r8_unorm;
    }
    return gpu::Format::bgra8_srgb;
}

uint32 bytesPerPixel(AcornRHIPixelFormat format) noexcept {
    switch (format) {
        case ACORN_RHI_PIXEL_FORMAT_R8_UNORM: return 1;
        case ACORN_RHI_PIXEL_FORMAT_BGRA8_UNORM:
        case ACORN_RHI_PIXEL_FORMAT_BGRA8_SRGB:
        case ACORN_RHI_PIXEL_FORMAT_RGBA8_UNORM: return 4;
    }
    return 4;
}

enum class DepthMode : uint8_t {
    unknown = 0,
    opaque3D,
    transparent2D,
    road,
};

struct MeshSlab {
    gpu::GpuHeap heap{};
    std::unique_ptr<gpu::HeapAllocator> allocator;
};

struct TextureSlab {
    gpu::TextureHeap heap{};
    std::unique_ptr<gpu::TextureAllocator> allocator;
};

struct PendingRetire {
    uint64 retireValue = 0;
    uint32 kind = 0; // 0 = mesh alloc, 1 = texture + view/descriptor, 2 = render view
    uint32 slabIndex = 0;
    gpu::HeapAllocation<byte> heapAlloc{};
    gpu::PlacedTexture placedTexture{};
    gpu::RenderView* renderView = nullptr;
    uint32 descriptorSlot = UINT32_MAX;
};

struct FrameSlot {
    gpu::CommandPool* commandPool = nullptr;
    gpu::GpuHeap bumpHeap{};
    std::unique_ptr<gpu::BumpAllocator> bumpAllocator;
    std::vector<gpu::GpuHeap> overflowHeaps;
    std::vector<std::unique_ptr<gpu::BumpAllocator>> overflowAllocators;
};

} // namespace

struct AcornRHIMesh {
    uint32 slabIndex = 0;
    gpu::HeapAllocation<byte> allocation{};
    void* vertexGpuPtr = nullptr;
    void* indexGpuPtr = nullptr;
    uint64 indexByteSize = 0;
    uint32 vertexCount = 0;
    uint32 indexCount = 0;
    bool isSkinned = false;
};

struct AcornRHITexture {
    uint32 slabIndex = 0;
    gpu::PlacedTexture placed{};
    uint32 descriptorIndex = UINT32_MAX;
    uint32 width = 0;
    uint32 height = 0;
};

struct AcornRHIFrame {
    uint32 slotIndex = 0;
    gpu::CommandBuffer* commands = nullptr;
    const gpu::PSO* activePSO = nullptr;
    DepthMode activeDepthMode = DepthMode::unknown;
    uint32 width = 0;
    uint32 height = 0;
};

struct AcornRHIDevice {
    std::mutex mutex;

    gpu::Device* device = nullptr;
    std::string deviceName;
    bool hasWindow = false;
    gpu::Format swapchainFormat = gpu::Format::bgra8_srgb;
    uint32 targetWidth = 256;
    uint32 targetHeight = 256;

    // Semaphores & command pools
    gpu::TimelineSemaphore* frameSemaphore = nullptr;
    uint64 latestSubmittedValue = 0;
    FrameSlot frames[kFramesInFlight]{};
    bool frameActive = false;
    AcornRHIFrame currentFrame{};

    gpu::CommandPool* initPool = nullptr;
    gpu::TimelineSemaphore* initSemaphore = nullptr;
    uint64 initSubmittedValue = 0;

    std::unique_ptr<gpu::UploadQueue> uploadQueue;

    // Allocator slabs
    std::vector<std::unique_ptr<MeshSlab>> meshSlabs;
    std::vector<std::unique_ptr<TextureSlab>> textureSlabs;

    // Descriptor heaps
    gpu::TextureDescriptorHeap* textureDescriptorHeap = nullptr;
    gpu::SamplerDescriptorHeap* samplerDescriptorHeap = nullptr;
    std::vector<uint32> freeDescriptorSlots;

    // Deferred retirement queue
    std::deque<PendingRetire> retireQueue;

    // Offscreen / Depth attachments
    uint32 attachmentWidth = 0;
    uint32 attachmentHeight = 0;
    uint32 depthSlabIndex = 0;
    gpu::PlacedTexture depthPlaced{};
    gpu::RenderView* depthView = nullptr;
    uint32 headlessColorSlabIndex = 0;
    gpu::PlacedTexture headlessColorPlaced{};
    gpu::RenderView* headlessColorView = nullptr;

    // Default 1x1 white fallback texture
    AcornRHITexture* defaultWhiteTexture = nullptr;

    // Pipelines
    gpu::PSO* meshPSO = nullptr;
    gpu::PSO* skinnedMeshPSO = nullptr;
    gpu::PSO* instancedMeshPSO = nullptr;
    gpu::PSO* sdfTextPSO = nullptr;
    gpu::PSO* spritePSO = nullptr;
    gpu::PSO* instancedSpritePSO = nullptr;
    gpu::PSO* roadPSO = nullptr;

    template <typename T>
    gpu::GpuCpuRange<byte> allocateFrameBytes(FrameSlot& slot, uint64 byteSize) {
        static_assert(alignof(T) <= gpu::BumpAllocator::alignment);
        const uint64 alignedSize = std::max<uint64>(16, byteSize);
        auto res = slot.bumpAllocator->allocate(alignedSize);
        if (res.cpu) return res;

        for (auto& overflow : slot.overflowAllocators) {
            res = overflow->allocate(alignedSize);
            if (res.cpu) return res;
        }

        const uint64 heapSize = std::max<uint64>(kFrameHeapBytes, (alignedSize + 65535ull) & ~65535ull);
        gpu::GpuHeap extra = gpu::create_gpu_heap(device, heapSize, gpu::MemoryType::cpu_visible);
        if (!extra.owner) return {};
        auto alloc = std::make_unique<gpu::BumpAllocator>(extra.range);
        res = alloc->allocate(alignedSize);
        slot.overflowHeaps.push_back(extra);
        slot.overflowAllocators.push_back(std::move(alloc));
        return res;
    }

    template <typename T>
    gpu::GpuCpuRange<T> allocateFrameTyped(FrameSlot& slot, uint64 count = 1) {
        const auto bytes = allocateFrameBytes<T>(slot, count * sizeof(T));
        return {
            .cpu = reinterpret_cast<T*>(bytes.cpu),
            .gpu = reinterpret_cast<T*>(bytes.gpu),
            .size = bytes.size,
        };
    }

    bool ensureMeshSlabCapacity(uint64 byteSize, uint32& outSlabIndex, gpu::HeapAllocation<byte>& outAlloc) {
        for (size_t i = 0; i < meshSlabs.size(); ++i) {
            auto alloc = meshSlabs[i]->allocator->allocate(byteSize);
            if (alloc.range.gpu != nullptr) {
                outSlabIndex = static_cast<uint32>(i);
                outAlloc = alloc;
                return true;
            }
        }
        const uint64 slabBytes = std::max<uint64>(kMeshSlabBytes, ((byteSize + 65535ull) & ~65535ull) * 2);
        gpu::GpuHeap heap = gpu::create_gpu_heap(device, slabBytes, gpu::MemoryType::gpu_only);
        if (!heap.owner) return false;
        auto slab = std::make_unique<MeshSlab>();
        slab->heap = heap;
        slab->allocator = std::make_unique<gpu::HeapAllocator>(heap.range, 16384u);
        auto alloc = slab->allocator->allocate(byteSize);
        if (alloc.range.gpu == nullptr) {
            slab->allocator.reset();
            gpu::destroy_gpu_heap(heap);
            return false;
        }
        outSlabIndex = static_cast<uint32>(meshSlabs.size());
        outAlloc = alloc;
        meshSlabs.push_back(std::move(slab));
        return true;
    }

    bool allocateTextureFromSlabs(const gpu::TextureDesc& desc, uint32& outSlabIndex, gpu::PlacedTexture& outPlaced) {
        for (size_t i = 0; i < textureSlabs.size(); ++i) {
            gpu::PlacedTexture placed = textureSlabs[i]->allocator->allocate(desc);
            if (placed.texture != nullptr) {
                outSlabIndex = static_cast<uint32>(i);
                outPlaced = placed;
                return true;
            }
        }
        const gpu::SizeAlign sa = gpu::get_texture_size_align(device, desc);
        if (sa.size == 0) return false;
        const uint64 slabBytes = std::max<uint64>(kTextureSlabBytes, ((sa.size + 65535ull) & ~65535ull) * 2);
        gpu::TextureHeap heap = gpu::create_texture_heap(device, slabBytes);
        if (!heap.owner) return false;
        auto slab = std::make_unique<TextureSlab>();
        slab->heap = heap;
        slab->allocator = std::make_unique<gpu::TextureAllocator>(device, heap, 4096u);
        gpu::PlacedTexture placed = slab->allocator->allocate(desc);
        if (!placed.texture) {
            slab->allocator.reset();
            gpu::destroy_texture_heap(heap);
            return false;
        }
        outSlabIndex = static_cast<uint32>(textureSlabs.size());
        outPlaced = placed;
        textureSlabs.push_back(std::move(slab));
        return true;
    }

    void executeRetireItem(PendingRetire& item) noexcept {
        switch (item.kind) {
            case 0:
                if (item.slabIndex < meshSlabs.size() && item.heapAlloc.range.gpu) {
                    meshSlabs[item.slabIndex]->allocator->free(item.heapAlloc);
                }
                break;
            case 1:
                if (item.renderView) {
                    gpu::destroy_render_view(item.renderView);
                }
                if (item.placedTexture.texture && item.slabIndex < textureSlabs.size()) {
                    textureSlabs[item.slabIndex]->allocator->free(item.placedTexture);
                }
                if (item.descriptorSlot != UINT32_MAX) {
                    freeDescriptorSlots.push_back(item.descriptorSlot);
                }
                break;
            case 2:
                if (item.renderView) {
                    gpu::destroy_render_view(item.renderView);
                }
                break;
        }
    }

    void retireCompleted(bool drainAll = false) noexcept {
        const uint64 completed = drainAll ? UINT64_MAX : gpu::timeline_completed_value(frameSemaphore);
        while (!retireQueue.empty()) {
            PendingRetire& front = retireQueue.front();
            if (!drainAll && front.retireValue > completed) {
                break;
            }
            executeRetireItem(front);
            retireQueue.pop_front();
        }
    }

    uint64 pendingRetireValue() const noexcept {
        return frameActive ? (latestSubmittedValue + 1) : latestSubmittedValue;
    }

    bool initializeTextureSync(gpu::Texture* texture) noexcept {
        if (initSubmittedValue > 0) {
            gpu::wait_timeline({.semaphore = initSemaphore, .value = initSubmittedValue});
        }
        gpu::reset_command_pool(initPool);
        gpu::CommandBuffer* cmd = gpu::begin_commands(initPool);
        if (!cmd) return false;
        gpu::initialize_texture(cmd, texture);
        gpu::end_commands(cmd);
        ++initSubmittedValue;
        gpu::submit(device, {
            .commands = {&cmd, 1},
            .completion = {.semaphore = initSemaphore, .value = initSubmittedValue},
        }, 0);
        gpu::wait_timeline({.semaphore = initSemaphore, .value = initSubmittedValue});
        return true;
    }

    void bindPipelineAndDepth(AcornRHIFrame& frame, const gpu::PSO* pso, DepthMode depthMode) noexcept {
        if (frame.activePSO != pso) {
            gpu::bind_pso(frame.commands, pso);
            frame.activePSO = pso;
        }
        if (frame.activeDepthMode != depthMode) {
            gpu::DepthStencilState ds{};
            switch (depthMode) {
                case DepthMode::opaque3D:
                    ds = {.depth_test = true, .depth_write = true, .depth_compare = gpu::CompareOp::less_equal};
                    break;
                case DepthMode::transparent2D:
                    ds = {.depth_test = true, .depth_write = false, .depth_compare = gpu::CompareOp::less};
                    break;
                case DepthMode::road:
                    ds = {.depth_test = true, .depth_write = false, .depth_compare = gpu::CompareOp::less_equal};
                    break;
                case DepthMode::unknown:
                    break;
            }
            gpu::set_depth_stencil(frame.commands, ds);
            frame.activeDepthMode = depthMode;
        }
    }

    bool ensureRenderAttachments(gpu::CommandBuffer* cmd, uint32 width, uint32 height) noexcept {
        if (width == 0 || height == 0) return false;
        if (attachmentWidth == width && attachmentHeight == height && depthView && (hasWindow || headlessColorView)) {
            return true;
        }

        const uint64 retireAt = pendingRetireValue();
        if (depthPlaced.texture) {
            PendingRetire item{};
            item.retireValue = retireAt;
            item.kind = 1;
            item.slabIndex = depthSlabIndex;
            item.placedTexture = depthPlaced;
            item.renderView = depthView;
            retireQueue.push_back(item);
            depthPlaced = {};
            depthView = nullptr;
        }
        if (headlessColorPlaced.texture) {
            PendingRetire item{};
            item.retireValue = retireAt;
            item.kind = 1;
            item.slabIndex = headlessColorSlabIndex;
            item.placedTexture = headlessColorPlaced;
            item.renderView = headlessColorView;
            retireQueue.push_back(item);
            headlessColorPlaced = {};
            headlessColorView = nullptr;
        }

        const gpu::TextureDesc depthDesc{
            .type = gpu::TextureType::two_d,
            .extent = {.x = width, .y = height, .z = 1},
            .mip_levels = 1,
            .layer_count = 1,
            .format = gpu::Format::d32_float,
            .usage = gpu::TextureUsage::depth_stencil_attachment,
        };
        if (!allocateTextureFromSlabs(depthDesc, depthSlabIndex, depthPlaced)) {
            return false;
        }
        gpu::initialize_texture(cmd, depthPlaced.texture);
        depthView = gpu::create_render_view(depthPlaced.texture);
        if (!depthView) return false;

        if (!hasWindow) {
            const gpu::TextureDesc colorDesc{
                .type = gpu::TextureType::two_d,
                .extent = {.x = width, .y = height, .z = 1},
                .mip_levels = 1,
                .layer_count = 1,
                .format = swapchainFormat,
                .usage = gpu::TextureUsage::color_attachment | gpu::TextureUsage::sampled,
            };
            if (!allocateTextureFromSlabs(colorDesc, headlessColorSlabIndex, headlessColorPlaced)) {
                return false;
            }
            gpu::initialize_texture(cmd, headlessColorPlaced.texture);
            headlessColorView = gpu::create_render_view(headlessColorPlaced.texture);
            if (!headlessColorView) return false;
        }

        attachmentWidth = width;
        attachmentHeight = height;
        return true;
    }
};

namespace {

gpu::PSO* buildPSO(gpu::Device* device, const AcornRHIShaderBinary& shader, gpu::Format colorFormat, bool blendEnabled) noexcept {
    if (!shader.vertexCode || shader.vertexSize == 0 || !shader.fragmentCode || shader.fragmentSize == 0) {
        return nullptr;
    }

    gpu::BlendState blend{};
    if (blendEnabled) {
        blend = {
            .enabled = true,
            .color = {
                .source = gpu::BlendFactor::source_alpha,
                .destination = gpu::BlendFactor::one_minus_source_alpha,
                .operation = gpu::BlendOp::add,
            },
            .alpha = {
                .source = gpu::BlendFactor::source_alpha,
                .destination = gpu::BlendFactor::one_minus_source_alpha,
                .operation = gpu::BlendOp::add,
            },
        };
    }

    const gpu::ColorTargetDesc target{
        .format = colorFormat,
        .blend = blend,
        .write_mask = 0xf,
    };

    const gpu::GraphicsPSODesc psoDesc{
        .vertex = {
            .code = {shader.vertexCode, shader.vertexSize},
            .entry_point = shader.vertexEntry ? shader.vertexEntry : "vertexMain",
        },
        .fragment = {
            .code = {shader.fragmentCode, shader.fragmentSize},
            .entry_point = shader.fragmentEntry ? shader.fragmentEntry : "fragmentMain",
        },
        .color_targets = {&target, 1},
        .depth_format = gpu::Format::d32_float,
        .rasterization = {.cull = gpu::CullMode::none},
    };
    return gpu::create_graphics_pso(device, psoDesc);
}

AcornRHITexture* createTextureLocked(
    AcornRHIDevice* rhi,
    uint32_t width,
    uint32_t height,
    AcornRHIPixelFormat format,
    const uint8_t* pixels,
    size_t byteCount
) {
    if (!rhi || !rhi->device || width == 0 || height == 0 || !pixels) return nullptr;
    const uint32 bpp = bytesPerPixel(format);
    const size_t expectedSize = size_t(width) * size_t(height) * size_t(bpp);
    if (byteCount != expectedSize) return nullptr;

    if (rhi->freeDescriptorSlots.empty()) {
        std::fprintf(stderr, "[AcornRHI] Texture descriptor heap capacity exhausted\n");
        return nullptr;
    }

    const gpu::TextureDesc desc{
        .type = gpu::TextureType::two_d,
        .extent = {.x = width, .y = height, .z = 1},
        .mip_levels = 1,
        .layer_count = 1,
        .format = toGpuFormat(format),
        .usage = gpu::TextureUsage::sampled | gpu::TextureUsage::transfer_destination,
    };

    uint32 slabIndex = 0;
    gpu::PlacedTexture placed{};
    if (!rhi->allocateTextureFromSlabs(desc, slabIndex, placed)) {
        return nullptr;
    }

    if (!rhi->initializeTextureSync(placed.texture)) {
        rhi->textureSlabs[slabIndex]->allocator->free(placed);
        return nullptr;
    }

    const uint32 slot = rhi->freeDescriptorSlots.back();
    rhi->freeDescriptorSlots.pop_back();

    gpu::write_texture_descriptor(
        rhi->textureDescriptorHeap,
        slot,
        placed.texture,
        gpu::TextureDescriptorType::sampled
    );

    rhi->uploadQueue->upload_texture(placed.texture, {pixels, byteCount});

    auto* tex = new AcornRHITexture();
    tex->slabIndex = slabIndex;
    tex->placed = placed;
    tex->descriptorIndex = slot;
    tex->width = width;
    tex->height = height;
    return tex;
}

} // namespace

extern "C" AcornRHIDevice* acorn_rhi_create_device(
    const AcornRHISurfaceDesc* surface,
    const AcornRHIShaderBundle* shaders,
    bool enableValidation
) {
    (void)enableValidation; // Reserved for future explicit validation toggles if NoGraphicsAPI exposes DeviceDesc flags
    if (!shaders) return nullptr;

    gpu::set_error_callback(onGpuError);

    const gpu::Format swapFormat = surface ? toGpuFormat(surface->pixelFormat) : gpu::Format::bgra8_srgb;
    const gpu::DeviceDesc devDesc{
        .window = surface ? surface->nativeLayer : nullptr,
        .swapchain_format = swapFormat,
        .swapchain_color_space = gpu::ColorSpace::srgb,
        .desired_swapchain_image_count = kFramesInFlight,
        .desired_queue_count = 1,
    };

    const gpu::DeviceInit init = gpu::create_device(devDesc);
    if (!init.device || init.error != gpu::Error::none) {
        return nullptr;
    }

    auto rhi = std::make_unique<AcornRHIDevice>();
    rhi->device = init.device;
    const gpu::DeviceCaps& caps = gpu::get_device_caps(rhi->device);
    rhi->deviceName = caps.device_name ? caps.device_name : "NoGraphicsAPI Device";
    rhi->hasWindow = (surface && surface->nativeLayer != nullptr);
    rhi->swapchainFormat = swapFormat;
    if (surface && surface->width > 0 && surface->height > 0) {
        rhi->targetWidth = surface->width;
        rhi->targetHeight = surface->height;
    }

    rhi->frameSemaphore = gpu::create_timeline_semaphore(rhi->device, 0);
    rhi->initPool = gpu::create_command_pool(rhi->device, 0);
    rhi->initSemaphore = gpu::create_timeline_semaphore(rhi->device, 0);
    if (!rhi->frameSemaphore || !rhi->initPool || !rhi->initSemaphore) {
        acorn_rhi_destroy_device(rhi.release());
        return nullptr;
    }

    for (uint32 i = 0; i < kFramesInFlight; ++i) {
        rhi->frames[i].commandPool = gpu::create_command_pool(rhi->device, 0);
        rhi->frames[i].bumpHeap = gpu::create_gpu_heap(rhi->device, kFrameHeapBytes, gpu::MemoryType::cpu_visible);
        if (!rhi->frames[i].commandPool || !rhi->frames[i].bumpHeap.owner) {
            acorn_rhi_destroy_device(rhi.release());
            return nullptr;
        }
        rhi->frames[i].bumpAllocator = std::make_unique<gpu::BumpAllocator>(rhi->frames[i].bumpHeap.range);
    }

    rhi->uploadQueue = std::make_unique<gpu::UploadQueue>(rhi->device, kUploadQueueBytes, 0u, kFramesInFlight);
    if (!rhi->uploadQueue->valid()) {
        acorn_rhi_destroy_device(rhi.release());
        return nullptr;
    }

    rhi->textureDescriptorHeap = gpu::create_texture_descriptor_heap(rhi->device, kTextureDescriptorCapacity);
    rhi->samplerDescriptorHeap = gpu::create_sampler_descriptor_heap(rhi->device, kSamplerDescriptorCapacity);
    if (!rhi->textureDescriptorHeap || !rhi->samplerDescriptorHeap) {
        acorn_rhi_destroy_device(rhi.release());
        return nullptr;
    }

    rhi->freeDescriptorSlots.reserve(kTextureDescriptorCapacity);
    for (int32_t i = static_cast<int32_t>(kTextureDescriptorCapacity) - 1; i >= 0; --i) {
        rhi->freeDescriptorSlots.push_back(static_cast<uint32>(i));
    }

    gpu::write_sampler_descriptor(rhi->samplerDescriptorHeap, kSamplerClampLinear, {
        .min_filter = gpu::Filter::linear,
        .mag_filter = gpu::Filter::linear,
        .mip_filter = gpu::Filter::linear,
        .address_u = gpu::AddressMode::clamp_to_edge,
        .address_v = gpu::AddressMode::clamp_to_edge,
        .address_w = gpu::AddressMode::clamp_to_edge,
    });
    gpu::write_sampler_descriptor(rhi->samplerDescriptorHeap, kSamplerRepeatLinear, {
        .min_filter = gpu::Filter::linear,
        .mag_filter = gpu::Filter::linear,
        .mip_filter = gpu::Filter::linear,
        .address_u = gpu::AddressMode::repeat,
        .address_v = gpu::AddressMode::repeat,
        .address_w = gpu::AddressMode::repeat,
    });

    rhi->meshPSO = buildPSO(rhi->device, shaders->mesh, swapFormat, false);
    rhi->skinnedMeshPSO = buildPSO(rhi->device, shaders->skinnedMesh, swapFormat, false);
    rhi->instancedMeshPSO = buildPSO(rhi->device, shaders->instancedMesh, swapFormat, false);
    rhi->sdfTextPSO = buildPSO(rhi->device, shaders->sdfText, swapFormat, true);
    rhi->spritePSO = buildPSO(rhi->device, shaders->sprite, swapFormat, true);
    rhi->instancedSpritePSO = buildPSO(rhi->device, shaders->instancedSprite, swapFormat, true);
    rhi->roadPSO = buildPSO(rhi->device, shaders->road, swapFormat, true);

    if (!rhi->meshPSO || !rhi->skinnedMeshPSO || !rhi->instancedMeshPSO ||
        !rhi->sdfTextPSO || !rhi->spritePSO || !rhi->instancedSpritePSO || !rhi->roadPSO) {
        acorn_rhi_destroy_device(rhi.release());
        return nullptr;
    }

    const uint8_t whitePixel[4] = {255, 255, 255, 255};
    rhi->defaultWhiteTexture = createTextureLocked(
        rhi.get(), 1, 1, ACORN_RHI_PIXEL_FORMAT_RGBA8_UNORM, whitePixel, sizeof(whitePixel)
    );
    if (!rhi->defaultWhiteTexture) {
        acorn_rhi_destroy_device(rhi.release());
        return nullptr;
    }

    return rhi.release();
}

extern "C" void acorn_rhi_destroy_device(AcornRHIDevice* device) {
    if (!device) return;

    if (device->device) {
        if (device->frameActive && device->currentFrame.commands) {
            gpu::end_render_pass(device->currentFrame.commands);
            gpu::end_commands(device->currentFrame.commands);
            device->frameActive = false;
            device->currentFrame = {};
        }
        if (device->uploadQueue && device->uploadQueue->valid()) {
            device->uploadQueue->wait();
        }
        gpu::wait_idle(device->device);
        device->retireCompleted(true);

        if (device->defaultWhiteTexture) {
            if (device->defaultWhiteTexture->placed.texture &&
                device->defaultWhiteTexture->slabIndex < device->textureSlabs.size()) {
                device->textureSlabs[device->defaultWhiteTexture->slabIndex]->allocator->free(
                    device->defaultWhiteTexture->placed
                );
            }
            delete device->defaultWhiteTexture;
            device->defaultWhiteTexture = nullptr;
        }

        if (device->depthView) gpu::destroy_render_view(device->depthView);
        if (device->depthPlaced.texture && device->depthSlabIndex < device->textureSlabs.size()) {
            device->textureSlabs[device->depthSlabIndex]->allocator->free(device->depthPlaced);
        }
        if (device->headlessColorView) gpu::destroy_render_view(device->headlessColorView);
        if (device->headlessColorPlaced.texture && device->headlessColorSlabIndex < device->textureSlabs.size()) {
            device->textureSlabs[device->headlessColorSlabIndex]->allocator->free(device->headlessColorPlaced);
        }

        if (device->uploadQueue) {
            device->uploadQueue->destroy();
            device->uploadQueue.reset();
        }

        for (auto& frame : device->frames) {
            if (frame.commandPool) gpu::destroy_command_pool(frame.commandPool);
            frame.bumpAllocator.reset();
            frame.overflowAllocators.clear();
            for (const auto& oh : frame.overflowHeaps) {
                if (oh.owner) gpu::destroy_gpu_heap(oh);
            }
            if (frame.bumpHeap.owner) gpu::destroy_gpu_heap(frame.bumpHeap);
        }

        if (device->initPool) gpu::destroy_command_pool(device->initPool);
        if (device->initSemaphore) gpu::destroy_timeline_semaphore(device->initSemaphore);
        if (device->frameSemaphore) gpu::destroy_timeline_semaphore(device->frameSemaphore);

        gpu::destroy_pso(device->roadPSO);
        gpu::destroy_pso(device->instancedSpritePSO);
        gpu::destroy_pso(device->spritePSO);
        gpu::destroy_pso(device->sdfTextPSO);
        gpu::destroy_pso(device->instancedMeshPSO);
        gpu::destroy_pso(device->skinnedMeshPSO);
        gpu::destroy_pso(device->meshPSO);

        if (device->textureDescriptorHeap) gpu::destroy_texture_descriptor_heap(device->textureDescriptorHeap);
        if (device->samplerDescriptorHeap) gpu::destroy_sampler_descriptor_heap(device->samplerDescriptorHeap);

        for (auto& slab : device->textureSlabs) {
            slab->allocator.reset();
            if (slab->heap.owner) gpu::destroy_texture_heap(slab->heap);
        }
        device->textureSlabs.clear();

        for (auto& slab : device->meshSlabs) {
            slab->allocator.reset();
            if (slab->heap.owner) gpu::destroy_gpu_heap(slab->heap);
        }
        device->meshSlabs.clear();

        gpu::destroy_device(device->device);
        device->device = nullptr;
    }

    delete device;
}

extern "C" void acorn_rhi_wait_idle(AcornRHIDevice* device) {
    if (!device || !device->device) return;
    std::lock_guard<std::mutex> lock(device->mutex);
    if (device->uploadQueue && device->uploadQueue->valid()) {
        device->uploadQueue->wait();
    }
    gpu::wait_idle(device->device);
    device->retireCompleted(true);
}

extern "C" bool acorn_rhi_resize_surface(AcornRHIDevice* device, uint32_t width, uint32_t height) {
    if (!device || width == 0 || height == 0) return false;
    std::lock_guard<std::mutex> lock(device->mutex);
    device->targetWidth = width;
    device->targetHeight = height;
    return true;
}

extern "C" bool acorn_rhi_attach_surface(AcornRHIDevice* device, const AcornRHISurfaceDesc* surface) {
    (void)surface;
    if (!device || !device->device) return false;
    // NoGraphicsAPI binds the native presentation layer at device creation time.
    return device->hasWindow;
}

extern "C" const char* acorn_rhi_get_device_name(const AcornRHIDevice* device) {
    if (!device) return "";
    return device->deviceName.c_str();
}

namespace {

AcornRHIMesh* createMeshCommon(
    AcornRHIDevice* rhi,
    const void* vertexData,
    uint64 vertexStride,
    uint32_t vertexCount,
    const uint32_t* indices,
    uint32_t indexCount,
    bool isSkinned
) {
    if (!rhi || !rhi->device || !vertexData || vertexCount == 0) return nullptr;
    std::lock_guard<std::mutex> lock(rhi->mutex);

    const uint64 vertexBytes = uint64(vertexCount) * vertexStride;
    const uint64 alignedVertexBytes = (vertexBytes + 15ull) & ~15ull;
    const uint64 indexBytes = (indices && indexCount > 0) ? (uint64(indexCount) * sizeof(uint32_t)) : 0;
    const uint64 totalBytes = std::max<uint64>(16, alignedVertexBytes + indexBytes);

    uint32 slabIndex = 0;
    gpu::HeapAllocation<byte> alloc{};
    if (!rhi->ensureMeshSlabCapacity(totalBytes, slabIndex, alloc)) {
        return nullptr;
    }

    byte* gpuBase = alloc.range.gpu;
    rhi->uploadQueue->upload_buffer(
        {.gpu = gpuBase, .size = vertexBytes},
        {static_cast<const uint8_t*>(vertexData), vertexBytes}
    );

    void* indexGpuPtr = nullptr;
    if (indexBytes > 0) {
        indexGpuPtr = gpuBase + alignedVertexBytes;
        rhi->uploadQueue->upload_buffer(
            {.gpu = indexGpuPtr, .size = indexBytes},
            {reinterpret_cast<const uint8_t*>(indices), indexBytes}
        );
    }

    auto* mesh = new AcornRHIMesh();
    mesh->slabIndex = slabIndex;
    mesh->allocation = alloc;
    mesh->vertexGpuPtr = gpuBase;
    mesh->indexGpuPtr = indexGpuPtr;
    mesh->indexByteSize = indexBytes;
    mesh->vertexCount = vertexCount;
    mesh->indexCount = indexBytes > 0 ? indexCount : 0;
    mesh->isSkinned = isSkinned;
    return mesh;
}

} // namespace

extern "C" AcornRHIMesh* acorn_rhi_create_mesh(
    AcornRHIDevice* device,
    const void* vertices64B,
    uint32_t vertexCount,
    const uint32_t* indices,
    uint32_t indexCount
) {
    return createMeshCommon(device, vertices64B, sizeof(AcornGpuVertex), vertexCount, indices, indexCount, false);
}

extern "C" AcornRHIMesh* acorn_rhi_create_skinned_mesh(
    AcornRHIDevice* device,
    const void* skinnedVertices80B,
    uint32_t vertexCount,
    const uint32_t* indices,
    uint32_t indexCount
) {
    return createMeshCommon(device, skinnedVertices80B, sizeof(AcornGpuSkinnedVertex), vertexCount, indices, indexCount, true);
}

extern "C" void acorn_rhi_destroy_mesh(AcornRHIDevice* device, AcornRHIMesh* mesh) {
    if (!mesh) return;
    if (device && device->device) {
        std::lock_guard<std::mutex> lock(device->mutex);
        PendingRetire item{};
        item.retireValue = device->pendingRetireValue();
        item.kind = 0;
        item.slabIndex = mesh->slabIndex;
        item.heapAlloc = mesh->allocation;
        device->retireQueue.push_back(item);
    }
    delete mesh;
}

extern "C" uint32_t acorn_rhi_mesh_vertex_count(const AcornRHIMesh* mesh) {
    return mesh ? mesh->vertexCount : 0;
}

extern "C" uint32_t acorn_rhi_mesh_index_count(const AcornRHIMesh* mesh) {
    return mesh ? mesh->indexCount : 0;
}

extern "C" bool acorn_rhi_mesh_is_skinned(const AcornRHIMesh* mesh) {
    return mesh ? mesh->isSkinned : false;
}

extern "C" AcornRHITexture* acorn_rhi_create_texture(
    AcornRHIDevice* device,
    uint32_t width,
    uint32_t height,
    AcornRHIPixelFormat format,
    const uint8_t* pixels,
    size_t byteCount
) {
    if (!device) return nullptr;
    std::lock_guard<std::mutex> lock(device->mutex);
    return createTextureLocked(device, width, height, format, pixels, byteCount);
}

extern "C" void acorn_rhi_destroy_texture(AcornRHIDevice* device, AcornRHITexture* texture) {
    if (!texture) return;
    if (device && device->device) {
        std::lock_guard<std::mutex> lock(device->mutex);
        PendingRetire item{};
        item.retireValue = device->pendingRetireValue();
        item.kind = 1;
        item.slabIndex = texture->slabIndex;
        item.placedTexture = texture->placed;
        item.descriptorSlot = texture->descriptorIndex;
        device->retireQueue.push_back(item);
    }
    delete texture;
}

extern "C" uint32_t acorn_rhi_texture_width(const AcornRHITexture* texture) {
    return texture ? texture->width : 0;
}

extern "C" uint32_t acorn_rhi_texture_height(const AcornRHITexture* texture) {
    return texture ? texture->height : 0;
}

extern "C" AcornRHIFrame* acorn_rhi_begin_frame(
    AcornRHIDevice* device,
    float clearR,
    float clearG,
    float clearB,
    float clearA
) {
    if (!device || !device->device) return nullptr;
    std::lock_guard<std::mutex> lock(device->mutex);
    if (device->frameActive) return nullptr;

    if (device->latestSubmittedValue >= kFramesInFlight) {
        gpu::wait_timeline({
            .semaphore = device->frameSemaphore,
            .value = device->latestSubmittedValue - kFramesInFlight + 1,
        });
    }
    device->retireCompleted(false);
    device->uploadQueue->reclaim();

    const uint32 slotIdx = static_cast<uint32>(device->latestSubmittedValue % kFramesInFlight);
    FrameSlot& slot = device->frames[slotIdx];
    gpu::reset_command_pool(slot.commandPool);
    slot.bumpAllocator->reset();
    for (auto& overflow : slot.overflowAllocators) {
        overflow->reset();
    }

    gpu::CommandBuffer* cmd = gpu::begin_commands(slot.commandPool);
    if (!cmd) return nullptr;

    gpu::RenderView* colorView = nullptr;
    uint32 width = device->targetWidth;
    uint32 height = device->targetHeight;

    if (device->hasWindow) {
        const gpu::SwapchainFrame swap = gpu::acquire(cmd);
        if (!swap.render_view) {
            gpu::end_commands(cmd);
            return nullptr;
        }
        colorView = swap.render_view;
        width = swap.extent.x;
        height = swap.extent.y;
    }

    if (!device->ensureRenderAttachments(cmd, width, height)) {
        gpu::end_commands(cmd);
        return nullptr;
    }
    if (!device->hasWindow) {
        colorView = device->headlessColorView;
    }

    gpu::set_texture_descriptor_heap(cmd, device->textureDescriptorHeap);
    gpu::set_sampler_descriptor_heap(cmd, device->samplerDescriptorHeap);

    const gpu::ColorAttachment colorAttachment{
        .render_view = colorView,
        .load = gpu::LoadOp::clear,
        .store = gpu::StoreOp::store,
        .clear = {.x = clearR, .y = clearG, .z = clearB, .w = clearA},
    };
    const gpu::RenderingDesc passDesc{
        .colors = {&colorAttachment, 1},
        .depth = {
            .render_view = device->depthView,
            .load = gpu::LoadOp::clear,
            .store = gpu::StoreOp::discard,
            .clear = 1.0f,
        },
    };
    gpu::begin_render_pass(cmd, passDesc);

    device->frameActive = true;
    device->currentFrame = {
        .slotIndex = slotIdx,
        .commands = cmd,
        .activePSO = nullptr,
        .activeDepthMode = DepthMode::unknown,
        .width = width,
        .height = height,
    };
    return &device->currentFrame;
}

extern "C" void acorn_rhi_end_frame(AcornRHIDevice* device, AcornRHIFrame* frame) {
    if (!device || !device->device || !frame) return;
    std::lock_guard<std::mutex> lock(device->mutex);
    if (!device->frameActive || frame != &device->currentFrame) return;

    gpu::end_render_pass(frame->commands);
    gpu::end_commands(frame->commands);

    const gpu::TimelinePoint uploadPoint = device->uploadQueue->flush();
    device->latestSubmittedValue++;

    gpu::SubmitDesc submitDesc{
        .commands = {&frame->commands, 1},
        .completion = {.semaphore = device->frameSemaphore, .value = device->latestSubmittedValue},
    };
    if (uploadPoint.semaphore != nullptr && uploadPoint.value > 0) {
        submitDesc.waits = {&uploadPoint, 1};
    }

    if (device->hasWindow) {
        gpu::submit_and_present(device->device, submitDesc);
    } else {
        gpu::submit(device->device, submitDesc, 0);
    }

    device->frameActive = false;
    device->currentFrame = {};
}

extern "C" void acorn_rhi_draw_mesh(
    AcornRHIDevice* device,
    AcornRHIFrame* frame,
    const AcornRHIMesh* mesh,
    const AcornRHITexture* texture,
    const AcornRHIGlobalUniforms* uniforms
) {
    if (!device || !frame || !mesh || !uniforms || mesh->vertexCount == 0 || mesh->isSkinned) return;
    std::lock_guard<std::mutex> lock(device->mutex);
    if (!device->frameActive || frame != &device->currentFrame) return;

    FrameSlot& slot = device->frames[frame->slotIndex];
    auto uniformAlloc = device->allocateFrameTyped<AcornGpuGlobalUniforms>(slot, 1);
    auto rootAlloc = device->allocateFrameTyped<AcornMeshRoot>(slot, 1);
    if (!uniformAlloc.cpu || !rootAlloc.cpu) return;

    std::memcpy(uniformAlloc.cpu, uniforms, sizeof(AcornGpuGlobalUniforms));
    const AcornRHITexture* resolvedTex = texture ? texture : device->defaultWhiteTexture;
    *rootAlloc.cpu = {
        .vertices = reinterpret_cast<AcornGpuVertex*>(mesh->vertexGpuPtr),
        .uniforms = uniformAlloc.gpu,
        .textureIndex = resolvedTex->descriptorIndex,
        .samplerIndex = kSamplerClampLinear,
    };

    device->bindPipelineAndDepth(*frame, device->meshPSO, DepthMode::opaque3D);
    if (mesh->indexCount > 0) {
        gpu::draw_indexed(frame->commands, rootAlloc.gpu, {.gpu = mesh->indexGpuPtr, .size = mesh->indexByteSize},
                          gpu::IndexType::uint32, mesh->indexCount);
    } else {
        gpu::draw(frame->commands, rootAlloc.gpu, mesh->vertexCount);
    }
}

extern "C" void acorn_rhi_draw_skinned_mesh(
    AcornRHIDevice* device,
    AcornRHIFrame* frame,
    const AcornRHIMesh* mesh,
    const AcornRHITexture* texture,
    const AcornRHIGlobalUniforms* uniforms,
    const float* jointMatricesRowMajor16,
    uint32_t jointCount
) {
    if (!device || !frame || !mesh || !uniforms || mesh->vertexCount == 0 || !mesh->isSkinned) return;
    std::lock_guard<std::mutex> lock(device->mutex);
    if (!device->frameActive || frame != &device->currentFrame) return;

    FrameSlot& slot = device->frames[frame->slotIndex];
    const uint32 effectiveJointCount = (jointMatricesRowMajor16 && jointCount > 0) ? jointCount : 1u;
    auto uniformAlloc = device->allocateFrameTyped<AcornGpuGlobalUniforms>(slot, 1);
    auto jointsAlloc = device->allocateFrameTyped<float4x4>(slot, effectiveJointCount);
    auto rootAlloc = device->allocateFrameTyped<AcornSkinnedMeshRoot>(slot, 1);
    if (!uniformAlloc.cpu || !jointsAlloc.cpu || !rootAlloc.cpu) return;

    std::memcpy(uniformAlloc.cpu, uniforms, sizeof(AcornGpuGlobalUniforms));
    if (jointMatricesRowMajor16 && jointCount > 0) {
        std::memcpy(jointsAlloc.cpu, jointMatricesRowMajor16, size_t(jointCount) * sizeof(float4x4));
    } else {
        float4x4 identity{};
        identity.rows[0] = {1.0f, 0.0f, 0.0f, 0.0f};
        identity.rows[1] = {0.0f, 1.0f, 0.0f, 0.0f};
        identity.rows[2] = {0.0f, 0.0f, 1.0f, 0.0f};
        identity.rows[3] = {0.0f, 0.0f, 0.0f, 1.0f};
        *jointsAlloc.cpu = identity;
    }

    const AcornRHITexture* resolvedTex = texture ? texture : device->defaultWhiteTexture;
    *rootAlloc.cpu = {
        .vertices = reinterpret_cast<AcornGpuSkinnedVertex*>(mesh->vertexGpuPtr),
        .uniforms = uniformAlloc.gpu,
        .jointMatrices = jointsAlloc.gpu,
        .textureIndex = resolvedTex->descriptorIndex,
        .samplerIndex = kSamplerClampLinear,
    };

    device->bindPipelineAndDepth(*frame, device->skinnedMeshPSO, DepthMode::opaque3D);
    if (mesh->indexCount > 0) {
        gpu::draw_indexed(frame->commands, rootAlloc.gpu, {.gpu = mesh->indexGpuPtr, .size = mesh->indexByteSize},
                          gpu::IndexType::uint32, mesh->indexCount);
    } else {
        gpu::draw(frame->commands, rootAlloc.gpu, mesh->vertexCount);
    }
}

extern "C" void acorn_rhi_draw_instanced(
    AcornRHIDevice* device,
    AcornRHIFrame* frame,
    const AcornRHIMesh* mesh,
    const AcornRHITexture* texture,
    const AcornRHIMeshInstanceData* instances,
    uint32_t instanceCount,
    const AcornRHIFrameUniforms* uniforms
) {
    if (!device || !frame || !mesh || !instances || instanceCount == 0 || !uniforms || mesh->vertexCount == 0 || mesh->isSkinned) {
        return;
    }
    std::lock_guard<std::mutex> lock(device->mutex);
    if (!device->frameActive || frame != &device->currentFrame) return;

    FrameSlot& slot = device->frames[frame->slotIndex];
    auto uniformAlloc = device->allocateFrameTyped<AcornGpuFrameUniforms>(slot, 1);
    auto instAlloc = device->allocateFrameTyped<AcornGpuMeshInstanceData>(slot, instanceCount);
    auto rootAlloc = device->allocateFrameTyped<AcornInstancedMeshRoot>(slot, 1);
    if (!uniformAlloc.cpu || !instAlloc.cpu || !rootAlloc.cpu) return;

    std::memcpy(uniformAlloc.cpu, uniforms, sizeof(AcornGpuFrameUniforms));
    std::memcpy(instAlloc.cpu, instances, size_t(instanceCount) * sizeof(AcornGpuMeshInstanceData));

    const AcornRHITexture* resolvedTex = texture ? texture : device->defaultWhiteTexture;
    *rootAlloc.cpu = {
        .vertices = reinterpret_cast<AcornGpuVertex*>(mesh->vertexGpuPtr),
        .uniforms = uniformAlloc.gpu,
        .instances = instAlloc.gpu,
        .textureIndex = resolvedTex->descriptorIndex,
        .samplerIndex = kSamplerClampLinear,
    };

    device->bindPipelineAndDepth(*frame, device->instancedMeshPSO, DepthMode::opaque3D);
    if (mesh->indexCount > 0) {
        gpu::draw_indexed(frame->commands, rootAlloc.gpu, {.gpu = mesh->indexGpuPtr, .size = mesh->indexByteSize},
                          gpu::IndexType::uint32, mesh->indexCount, instanceCount);
    } else {
        gpu::draw(frame->commands, rootAlloc.gpu, mesh->vertexCount, instanceCount);
    }
}

extern "C" void acorn_rhi_draw_sdf_text(
    AcornRHIDevice* device,
    AcornRHIFrame* frame,
    const AcornRHIMesh* mesh,
    const AcornRHITexture* texture,
    const AcornRHISdfUniforms* uniforms
) {
    if (!device || !frame || !mesh || !texture || !uniforms || mesh->vertexCount == 0 || mesh->isSkinned) return;
    std::lock_guard<std::mutex> lock(device->mutex);
    if (!device->frameActive || frame != &device->currentFrame) return;

    FrameSlot& slot = device->frames[frame->slotIndex];
    auto uniformAlloc = device->allocateFrameTyped<AcornGpuSdfUniforms>(slot, 1);
    auto rootAlloc = device->allocateFrameTyped<AcornSdfRoot>(slot, 1);
    if (!uniformAlloc.cpu || !rootAlloc.cpu) return;

    std::memcpy(uniformAlloc.cpu, uniforms, sizeof(AcornGpuSdfUniforms));
    *rootAlloc.cpu = {
        .vertices = reinterpret_cast<AcornGpuVertex*>(mesh->vertexGpuPtr),
        .uniforms = uniformAlloc.gpu,
        .textureIndex = texture->descriptorIndex,
        .samplerIndex = kSamplerClampLinear,
    };

    device->bindPipelineAndDepth(*frame, device->sdfTextPSO, DepthMode::transparent2D);
    if (mesh->indexCount > 0) {
        gpu::draw_indexed(frame->commands, rootAlloc.gpu, {.gpu = mesh->indexGpuPtr, .size = mesh->indexByteSize},
                          gpu::IndexType::uint32, mesh->indexCount);
    } else {
        gpu::draw(frame->commands, rootAlloc.gpu, mesh->vertexCount);
    }
}

extern "C" void acorn_rhi_draw_sprite(
    AcornRHIDevice* device,
    AcornRHIFrame* frame,
    const AcornRHIMesh* mesh,
    const AcornRHITexture* texture,
    const AcornRHISpriteUniforms* uniforms
) {
    if (!device || !frame || !mesh || !texture || !uniforms || mesh->vertexCount == 0 || mesh->isSkinned) return;
    std::lock_guard<std::mutex> lock(device->mutex);
    if (!device->frameActive || frame != &device->currentFrame) return;

    FrameSlot& slot = device->frames[frame->slotIndex];
    auto uniformAlloc = device->allocateFrameTyped<AcornGpuSpriteUniforms>(slot, 1);
    auto rootAlloc = device->allocateFrameTyped<AcornSpriteRoot>(slot, 1);
    if (!uniformAlloc.cpu || !rootAlloc.cpu) return;

    std::memcpy(uniformAlloc.cpu, uniforms, sizeof(AcornGpuSpriteUniforms));
    *rootAlloc.cpu = {
        .vertices = reinterpret_cast<AcornGpuVertex*>(mesh->vertexGpuPtr),
        .uniforms = uniformAlloc.gpu,
        .textureIndex = texture->descriptorIndex,
        .samplerIndex = kSamplerClampLinear,
    };

    device->bindPipelineAndDepth(*frame, device->spritePSO, DepthMode::transparent2D);
    if (mesh->indexCount > 0) {
        gpu::draw_indexed(frame->commands, rootAlloc.gpu, {.gpu = mesh->indexGpuPtr, .size = mesh->indexByteSize},
                          gpu::IndexType::uint32, mesh->indexCount);
    } else {
        gpu::draw(frame->commands, rootAlloc.gpu, mesh->vertexCount);
    }
}

extern "C" void acorn_rhi_draw_sprites_instanced(
    AcornRHIDevice* device,
    AcornRHIFrame* frame,
    const AcornRHIMesh* mesh,
    const AcornRHITexture* texture,
    const AcornRHISpriteInstanceData* instances,
    uint32_t instanceCount,
    const AcornRHISpriteFrameUniforms* uniforms
) {
    if (!device || !frame || !mesh || !texture || !instances || instanceCount == 0 || !uniforms ||
        mesh->vertexCount == 0 || mesh->isSkinned) {
        return;
    }
    std::lock_guard<std::mutex> lock(device->mutex);
    if (!device->frameActive || frame != &device->currentFrame) return;

    FrameSlot& slot = device->frames[frame->slotIndex];
    auto uniformAlloc = device->allocateFrameTyped<AcornGpuSpriteFrameUniforms>(slot, 1);
    auto instAlloc = device->allocateFrameTyped<AcornGpuSpriteInstanceData>(slot, instanceCount);
    auto rootAlloc = device->allocateFrameTyped<AcornInstancedSpriteRoot>(slot, 1);
    if (!uniformAlloc.cpu || !instAlloc.cpu || !rootAlloc.cpu) return;

    std::memcpy(uniformAlloc.cpu, uniforms, sizeof(AcornGpuSpriteFrameUniforms));
    std::memcpy(instAlloc.cpu, instances, size_t(instanceCount) * sizeof(AcornGpuSpriteInstanceData));
    *rootAlloc.cpu = {
        .vertices = reinterpret_cast<AcornGpuVertex*>(mesh->vertexGpuPtr),
        .uniforms = uniformAlloc.gpu,
        .instances = instAlloc.gpu,
        .textureIndex = texture->descriptorIndex,
        .samplerIndex = kSamplerClampLinear,
    };

    device->bindPipelineAndDepth(*frame, device->instancedSpritePSO, DepthMode::transparent2D);
    if (mesh->indexCount > 0) {
        gpu::draw_indexed(frame->commands, rootAlloc.gpu, {.gpu = mesh->indexGpuPtr, .size = mesh->indexByteSize},
                          gpu::IndexType::uint32, mesh->indexCount, instanceCount);
    } else {
        gpu::draw(frame->commands, rootAlloc.gpu, mesh->vertexCount, instanceCount);
    }
}

extern "C" void acorn_rhi_draw_roads(
    AcornRHIDevice* device,
    AcornRHIFrame* frame,
    const AcornRHIMesh* mesh,
    const AcornRHITexture* textureOrNull,
    const AcornRHIRoadUniforms* uniforms
) {
    if (!device || !frame || !mesh || !uniforms || mesh->vertexCount == 0 || mesh->isSkinned) return;
    std::lock_guard<std::mutex> lock(device->mutex);
    if (!device->frameActive || frame != &device->currentFrame) return;

    FrameSlot& slot = device->frames[frame->slotIndex];
    auto uniformAlloc = device->allocateFrameTyped<AcornGpuRoadUniforms>(slot, 1);
    auto rootAlloc = device->allocateFrameTyped<AcornRoadRoot>(slot, 1);
    if (!uniformAlloc.cpu || !rootAlloc.cpu) return;

    std::memcpy(uniformAlloc.cpu, uniforms, sizeof(AcornGpuRoadUniforms));
    const bool hasRealTex = (textureOrNull != nullptr);
    const AcornRHITexture* resolvedTex = hasRealTex ? textureOrNull : device->defaultWhiteTexture;
    *rootAlloc.cpu = {
        .vertices = reinterpret_cast<AcornGpuVertex*>(mesh->vertexGpuPtr),
        .uniforms = uniformAlloc.gpu,
        .textureIndex = resolvedTex->descriptorIndex,
        .samplerIndex = kSamplerRepeatLinear,
        .hasTexture = hasRealTex ? 1u : 0u,
    };

    device->bindPipelineAndDepth(*frame, device->roadPSO, DepthMode::road);
    if (mesh->indexCount > 0) {
        gpu::draw_indexed(frame->commands, rootAlloc.gpu, {.gpu = mesh->indexGpuPtr, .size = mesh->indexByteSize},
                          gpu::IndexType::uint32, mesh->indexCount);
    } else {
        gpu::draw(frame->commands, rootAlloc.gpu, mesh->vertexCount);
    }
}
