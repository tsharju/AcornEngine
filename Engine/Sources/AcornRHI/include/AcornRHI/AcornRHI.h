#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AcornRHIDevice AcornRHIDevice;
typedef struct AcornRHIMesh AcornRHIMesh;
typedef struct AcornRHITexture AcornRHITexture;
typedef struct AcornRHIFrame AcornRHIFrame;

/// Pixel formats supported across surfaces and textures.
typedef enum AcornRHIPixelFormat {
    ACORN_RHI_PIXEL_FORMAT_BGRA8_UNORM = 0,
    ACORN_RHI_PIXEL_FORMAT_BGRA8_SRGB = 1,
    ACORN_RHI_PIXEL_FORMAT_RGBA8_UNORM = 2,
    ACORN_RHI_PIXEL_FORMAT_R8_UNORM = 3,
} AcornRHIPixelFormat;

/// Surface configuration describing a native presentation layer or headless extent.
typedef struct AcornRHISurfaceDesc {
    void* nativeLayer; // CAMetalLayer* on Apple platforms, HWND/WSI elsewhere, or NULL for headless
    uint32_t width;
    uint32_t height;
    AcornRHIPixelFormat pixelFormat;
} AcornRHISurfaceDesc;

/// Compiled vertex + fragment shader bytecode pair for one pipeline.
typedef struct AcornRHIShaderBinary {
    const uint8_t* vertexCode;
    size_t vertexSize;
    const char* vertexEntry;
    const uint8_t* fragmentCode;
    size_t fragmentSize;
    const char* fragmentEntry;
} AcornRHIShaderBinary;

/// All seven graphics pipelines required by AcornEngine.
typedef struct AcornRHIShaderBundle {
    AcornRHIShaderBinary mesh;
    AcornRHIShaderBinary skinnedMesh;
    AcornRHIShaderBinary instancedMesh;
    AcornRHIShaderBinary sdfText;
    AcornRHIShaderBinary sprite;
    AcornRHIShaderBinary instancedSprite;
    AcornRHIShaderBinary road;
} AcornRHIShaderBundle;

// Row-major matrix uniform structs matching `acorn_shared.h` byte-for-byte.

typedef struct AcornRHIGlobalUniforms {
    float modelViewProjectionMatrix[16];
    float modelMatrix[16];
    float normalMatrix[16];
    float ambientLightColor[4];
    float directionalLightColor[4];
    float directionalLightDirection[4];
    float pointLightColor[4];
    float pointLightPosition[4];
    float meshColor[4];
} AcornRHIGlobalUniforms;

typedef struct AcornRHISdfUniforms {
    float textColor[4];
    float outlineColor[4];
    float outlineWidth;
    float edgeWidth;
    float _padding[2];
    float modelViewProjectionMatrix[16];
} AcornRHISdfUniforms;

typedef struct AcornRHISpriteUniforms {
    float modelViewProjectionMatrix[16];
    float colorTint[4];
} AcornRHISpriteUniforms;

typedef struct AcornRHIFrameUniforms {
    float viewProjectionMatrix[16];
    float ambientLightColor[4];
    float directionalLightColor[4];
    float directionalLightDirection[4];
    float pointLightColor[4];
    float pointLightPosition[4];
} AcornRHIFrameUniforms;

typedef struct AcornRHIMeshInstanceData {
    float modelMatrix[16];
    float normalMatrix[16];
    float color[4];
} AcornRHIMeshInstanceData;

typedef struct AcornRHISpriteFrameUniforms {
    float viewProjectionMatrix[16];
} AcornRHISpriteFrameUniforms;

typedef struct AcornRHISpriteInstanceData {
    float modelMatrix[16];
    float colorTint[4];
    float uvRect[4];
} AcornRHISpriteInstanceData;

typedef struct AcornRHIRoadUniforms {
    float modelViewProjectionMatrix[16];
    float outlineColor[4];
    float outlineWidth;
    float edgeWidth;
    float widthScale;
    float renderMode;
} AcornRHIRoadUniforms;

/// Creates an RHI device (windowed when `surface->nativeLayer != NULL`, otherwise headless).
AcornRHIDevice* acorn_rhi_create_device(
    const AcornRHISurfaceDesc* surface,
    const AcornRHIShaderBundle* shaders,
    bool enableValidation
);

/// Waits for all pending GPU work and destroys the device and owned allocators/PSOs.
void acorn_rhi_destroy_device(AcornRHIDevice* device);

/// Blocks until all previously submitted GPU work completes.
void acorn_rhi_wait_idle(AcornRHIDevice* device);

/// Updates cached drawable dimensions (recreates offscreen or depth attachments on next frame).
bool acorn_rhi_resize_surface(AcornRHIDevice* device, uint32_t width, uint32_t height);

/// Attaches or replaces a presentation surface target on an existing device.
/// Wait-idles the device if a previous surface existed. Returns false if unsupported.
bool acorn_rhi_attach_surface(AcornRHIDevice* device, const AcornRHISurfaceDesc* surface);

/// Returns a static/device-lifetime human-readable adapter name string.
const char* acorn_rhi_get_device_name(const AcornRHIDevice* device);

/// Creates a GPU-resident mesh from 64-byte `Vertex` structs and optional 32-bit indices.
AcornRHIMesh* acorn_rhi_create_mesh(
    AcornRHIDevice* device,
    const void* vertices64B,
    uint32_t vertexCount,
    const uint32_t* indices,
    uint32_t indexCount
);

/// Creates a GPU-resident skinned mesh from 80-byte skinned vertices and optional 32-bit indices.
AcornRHIMesh* acorn_rhi_create_skinned_mesh(
    AcornRHIDevice* device,
    const void* skinnedVertices80B,
    uint32_t vertexCount,
    const uint32_t* indices,
    uint32_t indexCount
);

/// Defers freeing GPU allocations for `mesh` until in-flight frames finish, and deletes the handle.
void acorn_rhi_destroy_mesh(AcornRHIDevice* device, AcornRHIMesh* mesh);

uint32_t acorn_rhi_mesh_vertex_count(const AcornRHIMesh* mesh);
uint32_t acorn_rhi_mesh_index_count(const AcornRHIMesh* mesh);
bool acorn_rhi_mesh_is_skinned(const AcornRHIMesh* mesh);

/// Creates and uploads a 2D GPU texture and assigns a bindless descriptor index.
AcornRHITexture* acorn_rhi_create_texture(
    AcornRHIDevice* device,
    uint32_t width,
    uint32_t height,
    AcornRHIPixelFormat format,
    const uint8_t* pixels,
    size_t byteCount
);

/// Defers freeing GPU texture storage and descriptor index, and deletes the handle.
void acorn_rhi_destroy_texture(AcornRHIDevice* device, AcornRHITexture* texture);

uint32_t acorn_rhi_texture_width(const AcornRHITexture* texture);
uint32_t acorn_rhi_texture_height(const AcornRHITexture* texture);

/// Begins recording a frame and its primary color+depth render pass.
/// Returns NULL if the swapchain drawable is currently unavailable (e.g. zero extent).
AcornRHIFrame* acorn_rhi_begin_frame(
    AcornRHIDevice* device,
    float clearR,
    float clearG,
    float clearB,
    float clearA
);

/// Ends the render pass, flushes pending uploads, submits commands, and presents (if windowed).
void acorn_rhi_end_frame(AcornRHIDevice* device, AcornRHIFrame* frame);

void acorn_rhi_draw_mesh(
    AcornRHIDevice* device,
    AcornRHIFrame* frame,
    const AcornRHIMesh* mesh,
    const AcornRHITexture* texture,
    const AcornRHIGlobalUniforms* uniforms
);

void acorn_rhi_draw_skinned_mesh(
    AcornRHIDevice* device,
    AcornRHIFrame* frame,
    const AcornRHIMesh* mesh,
    const AcornRHITexture* texture,
    const AcornRHIGlobalUniforms* uniforms,
    const float* jointMatricesRowMajor16,
    uint32_t jointCount
);

void acorn_rhi_draw_instanced(
    AcornRHIDevice* device,
    AcornRHIFrame* frame,
    const AcornRHIMesh* mesh,
    const AcornRHITexture* texture,
    const AcornRHIMeshInstanceData* instances,
    uint32_t instanceCount,
    const AcornRHIFrameUniforms* uniforms
);

void acorn_rhi_draw_sdf_text(
    AcornRHIDevice* device,
    AcornRHIFrame* frame,
    const AcornRHIMesh* mesh,
    const AcornRHITexture* texture,
    const AcornRHISdfUniforms* uniforms
);

void acorn_rhi_draw_sprite(
    AcornRHIDevice* device,
    AcornRHIFrame* frame,
    const AcornRHIMesh* mesh,
    const AcornRHITexture* texture,
    const AcornRHISpriteUniforms* uniforms
);

void acorn_rhi_draw_sprites_instanced(
    AcornRHIDevice* device,
    AcornRHIFrame* frame,
    const AcornRHIMesh* mesh,
    const AcornRHITexture* texture,
    const AcornRHISpriteInstanceData* instances,
    uint32_t instanceCount,
    const AcornRHISpriteFrameUniforms* uniforms
);

void acorn_rhi_draw_roads(
    AcornRHIDevice* device,
    AcornRHIFrame* frame,
    const AcornRHIMesh* mesh,
    const AcornRHITexture* textureOrNull,
    const AcornRHIRoadUniforms* uniforms
);

#ifdef __cplusplus
}
#endif
