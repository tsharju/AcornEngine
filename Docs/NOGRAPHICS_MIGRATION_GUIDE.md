# Migration & API Reference Guide: NoGraphicsAPI Integration

This document outlines the architectural changes, API evolution, and migration steps for adopting the **NoGraphicsAPI** rendering backend in AcornEngine.

---

## 1. Executive Summary & Compatibility Notice

Starting in this release, AcornEngine replaces the legacy `AcornMetal` / `MetalRenderer` subsystem with **`NoGraphicsAPI`** (Metal 4 on Apple Silicon, Slang shaders, and future Vulkan 1.4 support).

> [!WARNING]
> **Breaking Changes**: This update contains major breaking changes.
> * Minimum target platforms are raised to **iOS 26.0+** and **macOS 26.0+**.
> * Legacy Apple platforms (iOS < 26, macOS < 26), Intel Macs, and iOS Simulators are **unsupported** by the Metal 4 backend (`MTLGPUFamilyApple7` and `MTLGPUFamilyMetal4` hardware required).
> * The `AcornMetal` module, `MetalRenderer`, `MetalMesh`, and `MetalTexture` types have been removed.
> * Integration views have migrated from `MTKView` to `RenderSurfaceView`.

---

## 2. API Replacement Cheat Sheet

| Legacy API (`AcornMetal`) | New API (`NoGraphicsAPI` / `AcornRHI`) | Notes |
| :--- | :--- | :--- |
| `MetalRenderer` | `NoGraphicsRenderer` | Implements `Renderer` protocol |
| `MetalMesh` | `NoGraphicsMesh` | Wraps `AcornRHIMesh` |
| `MetalTexture` | `NoGraphicsTexture` | Wraps `AcornRHITexture` |
| `MTKView` | `RenderSurfaceView` | Backed by `CAMetalLayer` and surface callbacks |
| `MTKViewDelegate` | `onRenderFrame` / `onDrawableSizeChanged` closures | Configured directly on `RenderSurfaceView` |
| `Shaders.metal` | `*.slang` compiled to `.metallib` / `.spv` | Slang shaders compiled via `./Engine/Scripts/compile_shaders.sh` |
| `PostProcessShaders.metal` | `Samples/Acorn3DSample/Shaders/postprocess.slang` | Fullscreen triangle post-processing pipeline |
| Custom offscreen passes | `OffscreenRenderTarget` / `PostProcessPipeline` | Standardized two-pass color + sampled-depth pipeline |

---

## 3. Detailed Subsystem Changes

### 3.1. Surface & View Integration (`RenderSurfaceView`)

In previous versions, iOS and macOS sample apps embedded an `MTKView` and implemented `MTKViewDelegate.draw(in:)`.

Under `NoGraphicsAPI`, apps embed `RenderSurfaceView`, which encapsulates swapchain presentation, surface creation, and display link rendering loops.

#### Setup in `UIViewController` (iOS)

```swift
import UIKit
import AcornEngine

class GameViewController: UIViewController {
    private var surfaceView: RenderSurfaceView!
    private var renderer: NoGraphicsRenderer!
    private var engine: Engine!

    override func loadView() {
        surfaceView = RenderSurfaceView(frame: UIScreen.main.bounds)
        self.view = surfaceView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // 1. Initialize renderer with surface descriptor
        do {
            renderer = try NoGraphicsRenderer(surface: surfaceView.surfaceDescriptor)
        } catch {
            fatalError("Failed to initialize NoGraphicsRenderer: \(error)")
        }

        // 2. Initialize Engine
        engine = Engine(renderer: renderer)

        // 3. Setup lifecycle closures
        surfaceView.onDrawableSizeChanged = { [weak self] newSize in
            self?.handleResize(newSize)
        }

        surfaceView.onRenderFrame = { [weak self] in
            self?.renderFrame()
        }
    }

    private func renderFrame() {
        guard let context = renderer.beginFrame(clearColor: surfaceView.clearColor) else {
            return // Skip if drawable is not yet ready or minimized
        }
        engine.tick(deltaTime: 1.0 / 60.0)
        engine.render(context: context)
        renderer.endFrame(context: context)
    }

    private func handleResize(_ size: CGSize) {
        // Update projection matrices or camera aspect ratios
    }
}
```

---

### 3.2. Headless Rendering & Testing

`NoGraphicsRenderer` can be instantiated without a window surface for headless GPU execution and offscreen rendering (e.g. in unit tests or compute tasks):

```swift
// Initializes a headless device without a swapchain
let headlessRenderer = try NoGraphicsRenderer()

if let context = headlessRenderer.beginFrame(clearColor: SIMD4<Float>(0, 0, 0, 1)) {
    // Record draws into offscreen headless color buffer
    headlessRenderer.endFrame(context: context)
}
```

---

### 3.3. Two-Pass Offscreen & Post-Processing API

AcornEngine now exposes first-class abstractions for multi-pass rendering pipelines requiring sampled depth (such as Screen-Space Ambient Occlusion, depth-based atmospheric fog, or screen distortion).

#### Protocols (`Renderer.swift`)
* `OffscreenRenderTarget`: Abstract handle managing offscreen color and depth texture allocations.
* `PostProcessPipeline`: Precompiled fullscreen post-processing pipeline state.

#### Creating Targets & Pipelines

```swift
// 1. Create a resizable offscreen target (color + sampled D32F depth)
let offscreenTarget = renderer.createOffscreenRenderTarget(
    width: Int(view.bounds.width),
    height: Int(view.bounds.height)
)

// 2. Compile a fullscreen post-process pipeline from compiled Slang metallib / SPV binaries
let pipeline = renderer.createPostProcessPipeline(
    vertexShaderData: vertexData,
    fragmentShaderData: fragmentData,
    vertexEntry: "vertexMain",
    fragmentEntry: "fragmentMain"
)
```

#### Executing the Two-Pass Frame

```swift
// Pass 1: Render scene geometry into offscreen color + depth targets
guard let sceneContext = renderer.beginOffscreenFrame(
    target: offscreenTarget,
    clearColor: SIMD4<Float>(0.1, 0.1, 0.1, 1.0)
) else { return }

engine.render(context: sceneContext)

// Transition: Insert GPU execution barrier (color/depth write -> fragment shader read)
// and begin fullscreen post-process pass targeting the swapchain drawable
renderer.beginPostProcessPass(context: sceneContext)

// Pass 2: Draw fullscreen triangle with custom uniforms reading offscreen attachments
renderer.renderPostProcess(
    pipeline: pipeline,
    target: offscreenTarget,
    uniforms: postProcessUniforms,
    context: sceneContext
)

// Present swapchain
renderer.endFrame(context: sceneContext)
```

---

### 3.4. Slang Shader Pipeline & Layout Validation

All rendering pipelines are authored in **Slang** under `Engine/Sources/AcornEngine/Renderer/Shaders/` (and sample-specific shaders such as `Samples/Acorn3DSample/Shaders/postprocess.slang`).

* **Shader Compilation**: Run `./Engine/Scripts/compile_shaders.sh` to compile Slang source files to:
  * Metal 4 bytecodes (`.metallib`) for iOS and macOS.
  * SPIR-V bytecodes (`.spv`) for Vulkan.
* **Layout Parity Checker**: `compile_shaders.sh` automatically runs `check_root_layouts.py` to assert strict struct byte size and field offset matching across C++, Slang, SPIR-V, and Metal roots.

#### Struct Memory Layout Guidelines:
* Custom uniforms passed to shaders must be 16-byte aligned.
* When uploading matrices to Slang shaders, use `NoGraphicsRenderer.packRowMajor(_:flipClipY:)` to pack column-major `Matrix4x4` into a row-major 16-element tuple (`NoGraphicsRenderer.RowMajorFloat4x4`).

```swift
let gpuPackedMatrix = NoGraphicsRenderer.packRowMajor(matrix, flipClipY: false)
```

---

## 4. Migration Checklist

1. [ ] **Update OS Targets**: Ensure your Xcode projects and `Package.swift` specify minimum deployment target iOS 26.0+ / macOS 26.0+.
2. [ ] **Remove `import Metal` / `import MetalKit`**: Replace with `import AcornEngine` and `import AcornMath`.
3. [ ] **Replace Storyboard / XIB Views**: Change any `MTKView` custom classes in Interface Builder to standard `UIView` / `RenderSurfaceView`.
4. [ ] **Update View Controllers**:
   * Switch `renderer` property from `MetalRenderer` to `NoGraphicsRenderer`.
   * Switch presentation view to `RenderSurfaceView`.
   * Move frame drawing logic from `MTKViewDelegate.draw(in:)` to `surfaceView.onRenderFrame`.
5. [ ] **Compile Shaders**: If adding or altering shaders, execute `./Engine/Scripts/compile_shaders.sh` before building.
6. [ ] **Physical Hardware Testing**: Test on physical Apple Silicon iOS 26+ hardware (`xcrun devicectl`); iOS Simulator is unsupported.
