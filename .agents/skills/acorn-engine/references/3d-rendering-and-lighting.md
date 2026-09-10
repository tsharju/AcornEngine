# AcornEngine 3D Rendering & Lighting Guide

AcornEngine provides a hardware-accelerated 3D graphics pipeline supporting glTF model loading, procedural primitives, dynamic lighting, and automatic GPU instanced batching.

---

## 1. Mesh Primitives & `MeshComponent`

Static 3D geometry is attached using `MeshComponent`.

### Procedural Shapes (`BasicShapeGenerator`)
```swift
import AcornEngine

// Generate primitive vertices
let cubeVertices = BasicShapeGenerator.generateCube(size: 1.0)
let sphereVertices = BasicShapeGenerator.generateSphere(radius: 0.5, segments: 16)
let planeVertices = BasicShapeGenerator.generatePlane(width: 10.0, length: 10.0)

// Upload to GPU buffer
guard let mesh = renderer.createMesh(vertices: cubeVertices) else {
    fatalError("Failed to allocate vertex buffer")
}

// Create entity
let cubeEntity = world.createEntity()
world.addComponent(TransformComponent(position: [0, 1, 0]), to: cubeEntity)
world.addComponent(
    MeshComponent(
        mesh: mesh,
        texture: optionalTexture,
        color: SIMD4<Float>(0.8, 0.2, 0.2, 1.0) // Red tint
    ),
    to: cubeEntity
)
```

---

## 2. Loading glTF / GLB Models

AcornEngine includes a high-performance glTF parser powered by `fastgltf` and `simdjson`:

```swift
guard let modelURL = Bundle.main.url(forResource: "character", withExtension: "glb") else {
    fatalError("Model not found")
}

// Load mesh, materials, and hierarchy
let model = try GLTFModelLoader.load(from: modelURL, renderer: renderer)

// Spawn model root entity
let modelEntity = world.createEntity()
world.addComponent(TransformComponent(position: [0, 0, 0], scale: [1, 1, 1]), to: modelEntity)

for node in model.nodes {
    let nodeEntity = world.createEntity()
    world.addComponent(node.transform, to: nodeEntity)
    world.addComponent(ParentComponent(parent: modelEntity), to: nodeEntity)
    
    if let mesh = node.mesh {
        world.addComponent(MeshComponent(mesh: mesh, texture: node.texture), to: nodeEntity)
    }
}
```

---

## 3. Automatic GPU Instanced Rendering

When multiple entities share the same `(mesh, texture)` pair:
- `RenderSystem` automatically aggregates them into instance batches every frame.
- Packs per-instance model matrices, normal matrices, and colors into a single instance buffer.
- Submits a single `renderInstanced` GPU draw call (`drawIndexedPrimitives:instanceCount:`).
- Zero code changes required—simply assign the same `Mesh` reference to multiple `MeshComponent` entities!

---

## 4. Lighting (`LightComponent`)

The renderer supports ambient, directional (sun), and point lights:

```swift
// 1. Ambient Light (uniform environment illumination)
let ambientEntity = world.createEntity()
world.addComponent(
    LightComponent(
        type: .ambient,
        color: SIMD3<Float>(0.25, 0.25, 0.30),
        intensity: 1.0
    ),
    to: ambientEntity
)

// 2. Directional Light (Sunlight with cast angle)
let sunEntity = world.createEntity()
var sunTransform = TransformComponent()
sunTransform.rotation = SIMD3<Float>(-.pi / 4.0, -.pi / 3.5, 0.0) // Direction vector
world.addComponent(sunTransform, to: sunEntity)
world.addComponent(
    LightComponent(
        type: .directional,
        color: SIMD3<Float>(1.0, 0.95, 0.85),
        intensity: 1.2
    ),
    to: sunEntity
)

// 3. Point Light (Localized omnidirectional emitter)
let torchEntity = world.createEntity()
world.addComponent(TransformComponent(position: [5, 2, 5]), to: torchEntity)
world.addComponent(
    LightComponent(
        type: .point,
        color: SIMD3<Float>(1.0, 0.6, 0.1),
        intensity: 2.0
    ),
    to: torchEntity
)
```

---

## 5. Cameras & Controllers

AcornEngine includes three camera components driven by `CameraSystem`:

### 1. Basic Camera (`CameraComponent`)
```swift
let cameraEntity = world.createEntity()
world.addComponent(TransformComponent(position: [0, 5, -10]), to: cameraEntity)
world.addComponent(
    CameraComponent(
        projectionType: .perspective, // or .orthographic
        fovY: Float.pi / 3.0,          // 60 degrees
        nearZ: 0.1,
        farZ: 1000.0,
        aspectRatio: 16.0 / 9.0
    ),
    to: cameraEntity
)
```

### 2. Smooth Follow Camera (`CameraTrackingComponent`)
Smoothly tracks a moving focal target with linear interpolation (LERP):
```swift
world.addComponent(
    CameraTrackingComponent(
        target: playerEntity,
        offset: SIMD3<Float>(0, 4, -8),
        smoothing: 0.1 // Clamped [0.001 ... 1.0], lower = smoother delay
    ),
    to: cameraEntity
)
```

### 3. Orbiting Camera (`CameraOrbitComponent`)
Performs continuous or swaying orbital movement around a target:
```swift
world.addComponent(
    CameraOrbitComponent(
        target: playerEntity,
        radius: 12.0,
        speed: 0.5,             // Radians per second
        baseHeight: 4.0,
        bobbingAmplitude: 0.2,   // Vertical oscillation
        swayAmplitude: 0.1       // Horizontal sway
    ),
    to: cameraEntity
)
```
