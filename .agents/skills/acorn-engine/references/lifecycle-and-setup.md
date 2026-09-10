# AcornEngine Lifecycle & Setup Guide

This guide details how to configure the engine lifecycle, set up an `MTKView`, handle application suspension/resumption, and manage render surface availability.

---

## 1. Engine Initialization

`Engine` is the core coordinator holding the `World`, `Renderer`, `InputSystem`, `RenderSystem`, `AudioSystem`, and `SpriteAnimationSystem`. All engine types operate under `@MainActor`.

```swift
import UIKit
import MetalKit
import AcornEngine

@MainActor
public class GameViewController: UIViewController, MTKViewDelegate {
    private var engine: Engine!
    private var renderer: MetalRenderer!
    private var commandQueue: MTLCommandQueue!
    private var lastRenderTime: CFTimeInterval = 0

    override public func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = view as? MTKView else {
            fatalError("Root view must be an MTKView")
        }

        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        guard let queue = defaultDevice.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }
        self.commandQueue = queue

        // Configure MTKView
        mtkView.device = defaultDevice
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0.08, green: 0.12, blue: 0.16, alpha: 1.0)
        mtkView.delegate = self

        do {
            // Initialize MetalRenderer & Engine
            self.renderer = try MetalRenderer(device: defaultDevice)
            self.engine = Engine(renderer: self.renderer)

            // Register additional game systems
            self.engine.world.registerSystem(PhysicsSystem())
            self.engine.world.registerSystem(PlayerMovementSystem())
            
            // Initial camera & scene configuration
            setupCamera(for: mtkView.bounds.size)
        } catch {
            print("Failed to initialize MetalRenderer: \(error)")
        }
    }
}
```

---

## 2. Game Loop (`tick` & `render`)

AcornEngine strictly decouples logical ticks (`tick(deltaTime:)`) from hardware rendering (`render(context:)`).

```swift
// MARK: - MTKViewDelegate

public func draw(in view: MTKView) {
    guard let engine = engine,
          let queue = commandQueue,
          let drawable = view.currentDrawable,
          let descriptor = view.currentRenderPassDescriptor,
          let commandBuffer = queue.makeCommandBuffer() else {
        return
    }

    // 1. Calculate delta time
    let currentTime = CACurrentMediaTime()
    let dt = lastRenderTime == 0 ? (1.0 / 60.0) : (currentTime - lastRenderTime)
    lastRenderTime = currentTime

    // 2. Advance logical simulation (ECS systems, input transitions)
    // Note: engine.tick clamps dt to engine.maxDeltaTime (default 0.1s)
    engine.tick(deltaTime: dt)

    // 3. Render hardware pass
    let context = MetalRenderContext(
        renderPassDescriptor: descriptor,
        commandBuffer: commandBuffer
    )
    _ = context.getOrCreateEncoder()
    engine.render(context: context)
    context.endEncoding()

    // 4. Present drawable and commit GPU buffer
    commandBuffer.present(drawable)
    commandBuffer.commit()
}
```

---

## 3. Surface & Application Lifecycle

When an app is suspended or moves to the background, `MTKView` draw calls stop or render passes may fail. `Engine` provides explicit hooks to manage surface availability and prevent delta-time spikes:

```swift
// When app resigns active or pauses:
engine.pause() 
// Halts world tick updates, resets active inputs, and publishes `AppPauseEvent`

// When app resumes active:
engine.resume() 
// Resumes tick updates and publishes `AppResumeEvent`

// When MTKView surface is invalid (e.g. view disappeared):
engine.surfaceDestroyed() 
// Halts render() execution and publishes `SurfaceDestroyedEvent`

// When MTKView surface is restored:
engine.surfaceCreated() 
// Re-enables render() and publishes `SurfaceCreatedEvent`
```

### Delta Time Clamping
When returning from background or breakpoints, delta time can spike to several seconds, which could explode physics simulations or particle emitters. `Engine.maxDeltaTime` (default `0.1`s) automatically clamps `deltaTime`:
```swift
engine.maxDeltaTime = 0.05 // Limit maximum step to 50ms
```

---

## 4. Viewport & Aspect Ratio Resizing

Whenever the view size changes (orientation change, window resize), update the camera component's aspect ratio:

```swift
public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    guard let engine = engine else { return }
    let aspect = Float(max(size.width, 1.0) / max(size.height, 1.0))

    // Update active camera's aspect ratio
    if let (cameraEntity, mutCamera) = engine.world.firstEntity(with: CameraComponent.self) {
        var camera = mutCamera
        camera.aspectRatio = aspect
        engine.world.addComponent(camera, to: cameraEntity)
    }
}
```
