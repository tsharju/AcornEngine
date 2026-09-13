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

## 2. Loading glTF / GLB Models & Animation

AcornEngine includes a high-performance glTF parser powered by `fastgltf` and `simdjson`.

### One-Line Instantiation with `GLTFModel.instantiate`
The easiest way to load and instantiate a glTF model hierarchy with mesh nodes and animations:

```swift
let loader = GLTFModelLoader(renderer: renderer)
let model = try loader.loadModel(from: modelURL)

// Automatically creates root entity, child node entities with ParentComponent,
// binds rest transforms, attaches MeshComponents, and sets up ModelAnimationComponent
let modelRoot = model.instantiate(in: world)
world.mutateComponent(ofType: TransformComponent.self, for: modelRoot) { t in
    t.position = [0, 0, 0]
    t.scale = [1, 1, 1]
}
```

### Manual Node Extraction
Alternatively, inspect or build entities manually:

```swift
let result = try loader.load(from: modelURL)

let rootEntity = world.createEntity()
world.addComponent(TransformComponent(), to: rootEntity)

for node in result.nodes {
    let nodeEntity = world.createEntity()
    world.addComponent(TransformComponent(
        position: node.translation,
        rotation: quaternionToEuler(node.rotation),
        scale: node.scale,
        orientation: node.rotation
    ), to: nodeEntity)
    world.addComponent(ParentComponent(parent: rootEntity), to: nodeEntity)
    
    if let meshIdx = node.meshIndex {
        world.addComponent(MeshComponent(mesh: result.meshes[meshIdx]), to: nodeEntity)
    }
}
```

---

## 3. 3D Model Animation & Cross-Fade Blending

Model skeletal and hierarchical node animation is managed by `ModelAnimationComponent` and driven by `ModelAnimationSystem` (automatically registered in `Engine`).

### Playback Modes & Controls
```swift
guard var anim = world.component(ofType: ModelAnimationComponent.self, for: modelRoot) else { return }

// 1. Play immediate clip
anim.play(clipNamed: "Run", mode: .loop)

// 2. Smooth Cross-Fade Transition (SLERP quaternion blend + LERP translation/scale)
anim.transition(to: "Walk", duration: 0.3, mode: .loop)

// 3. Playback Controls
anim.speed = 1.5 // 1.5x speed
anim.pause()
anim.resume()
anim.stop()

world.addComponent(anim, to: modelRoot)
```

### Listening to Animation Events via `EventBus`
```swift
world.eventBus.subscribe(ModelAnimationStartedEvent.self) { event in
    print("Animation \(event.clipName) started on entity \(event.entity)")
}

world.eventBus.subscribe(ModelAnimationLoopedEvent.self) { event in
    print("Animation \(event.clipName) looped")
}

world.eventBus.subscribe(ModelAnimationTransitionCompletedEvent.self) { event in
    print("Cross-fade transition completed to \(event.clipName)")
}
```

---

## 4. Automatic GPU Instanced Rendering

When multiple entities share the same `(mesh, texture)` pair:
- `RenderSystem` automatically aggregates them into instance batches every frame.
- Packs per-instance model matrices, normal matrices, and colors into a single instance buffer.
- Submits a single `renderInstanced` GPU draw call (`drawIndexedPrimitives:instanceCount:`).
- Zero code changes required—simply assign the same `Mesh` reference to multiple `MeshComponent` entities!

---

## 5. Lighting (`LightComponent`)

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

## 6. Cameras & Controllers

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
