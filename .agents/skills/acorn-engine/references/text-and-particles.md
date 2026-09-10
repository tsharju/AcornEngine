# AcornEngine Text & Particles Guide

AcornEngine includes scalable Signed Distance Field (SDF) text rendering and an entity-based 2D particle system fully integrated with physics.

---

## 1. Signed Distance Field (SDF) Text Rendering

SDF text rendering ensures pixel-perfect clarity, smooth anti-aliased edges, and custom outlines across arbitrary zoom levels and camera distances.

### Generating a Font Atlas
Font atlases are generated dynamically at runtime from TrueType / OpenType fonts using CoreText:

```swift
import AcornEngine

guard let fontURL = Bundle.main.url(forResource: "JetBrainsMono-Bold", withExtension: "ttf") else {
    fatalError("Missing font file")
}

// Generate SDF atlas texture & glyph metrics
let fontAtlas = try SDFFontAtlasGenerator.generateAtlas(
    from: fontURL,
    fontSize: 48.0,
    searchRadius: 8,
    renderer: renderer
)
```

### Rendering Text (`TextComponent`)
Attach a `TextComponent` to an entity:

```swift
let labelEntity = world.createEntity()
world.addComponent(TransformComponent(position: [0.0, 5.0, 0.0]), to: labelEntity)

let textComp = TextComponent(
    text: "ACORN ENGINE",
    fontAtlas: fontAtlas,
    textColor: SIMD4<Float>(1.0, 1.0, 1.0, 1.0),      // Crisp white
    outlineColor: SIMD4<Float>(0.0, 0.0, 0.0, 0.8),   // Dark outline
    outlineWidth: 0.15,                               // Outline thickness [0.0 - 0.5]
    edgeWidth: 0.05                                   // Anti-aliasing sharpness
)

world.addComponent(textComp, to: labelEntity)
```

### Updating Text Dynamically
To update text (e.g. for score displays), mutate the component and set `isDirty = true`:

```swift
world.mutateComponent(ofType: TextComponent.self, for: labelEntity) { comp in
    comp.text = "SCORE: \(currentScore)"
    comp.isDirty = true // Signals the RenderSystem to rebuild the mesh
}
```

---

## 2. 2D Particle System

Particles in AcornEngine are **first-class ECS entities**. This enables particles to interact with Box2D physics colliders, bounce off floors, receive lighting, or trigger contacts.

### Registering `ParticleSystem`
```swift
let particleSystem = ParticleSystem()
engine.world.registerSystem(particleSystem)
```

### Creating an Emitter (`ParticleEmitterComponent`)
```swift
let emitterEntity = world.createEntity()
world.addComponent(TransformComponent(position: [0.0, 0.0, 0.0]), to: emitterEntity)

// Particle meshes
let sparkMesh = BasicShapeGenerator.generatePlane(width: 0.1, length: 0.1)
guard let mesh = renderer.createMesh(vertices: sparkMesh) else { return }

let emitter = ParticleEmitterComponent(
    isEmitting: true,
    emitRate: 40.0,                      // Spawn 40 particles per second
    meshes: [mesh],
    lifetime: 0.8...1.5,                 // Lifetime range in seconds
    linearVelocityX: -3.0...3.0,         // Initial horizontal velocity range
    linearVelocityY: 5.0...10.0,         // Initial upward launch speed
    angularVelocity: -4.0...4.0,         // Rotation speed
    scale: 0.05...0.15                   // Randomized scale
)

world.addComponent(emitter, to: emitterEntity)
```

### Particle Lifecycle
- `ParticleSystem` automatically spawns new particle entities based on `emitRate`.
- Each particle receives a `ParticleComponent`, `TransformComponent`, `MeshComponent`, and optionally `PhysicsBodyComponent`.
- Expired particles are automatically destroyed via `world.destroyEntity()`, seamlessly reclaiming Box2D bodies and GPU buffers.
