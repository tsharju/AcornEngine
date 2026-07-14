# AcornEngine Documentation

AcornEngine is a modern, high-performance 2D/3D game engine targetting Apple platforms (**iOS 16+** and **macOS 13+**). It is built using **Swift 6** with strict concurrency safety (`Sendable` conformance and `@MainActor` isolation where appropriate) and leverages the **Metal** graphics API for hardware-accelerated rendering.

---

## Architecture Overview

AcornEngine is designed around a modular architecture:
```mermaid
graph TD
    Engine[Engine Coordinator] --> World[ECS World]
    Engine --> Renderer[Renderer Backend]
    
    World --> Entity[Entity Registry]
    World --> Component[Component Stores]
    World --> System[Systems List]
    
    RenderSystem[Render System] --> World
    RenderSystem --> Renderer
    
    subgraph ECS Loop
        World
    end
    
    subgraph Graphics Pipeline
        Renderer
    end
```

The engine uses three main pillars:
1. **ECS (Entity Component System)**: High-performance data separation where entities are simple IDs, components are pure data structs, and systems contain the logic.
2. **Metal Rendering Backend**: Low-overhead hardware-accelerated graphics pipeline supporting standard meshes, textured sprites, tilemaps, and high-quality Signed Distance Field (SDF) text.
3. **Engine Coordinator**: Manages the game loop by ticking the ECS world (`update`) and triggering the render pass (`render`).

---

## 1. Entity Component System (ECS)

Located under [Engine/Sources/AcornEngine/ECS](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/ECS):

### [Entity](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/ECS/Entity.swift)
A lightweight, unique identifier representing an object in the world.
* **Type**: `struct`
* **Conformances**: `Hashable`, `Sendable`
* **Properties**:
  * `id: UInt64`: The unique ID assigned to the entity.

### [Component](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/ECS/Component.swift)
A marker protocol that all components must conform to.
* **Type**: `protocol`
* **Conformances**: `Sendable`
* **Design Guideline**: Components should contain only raw data and state, leaving logic entirely to systems.

### [System](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/ECS/System.swift)
A protocol representing logic that runs on entities and components.
* **Type**: `protocol`
* **Isolation**: `@MainActor`
* **Requirements**:
  * `func update(world: World, deltaTime: Double)`: Performs logic updates on the world state.

### [World](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/ECS/World.swift)
The central registry that manages the lifetime of entities, component storage, and the execution order of systems.
* **Type**: `class`
* **Isolation**: `@MainActor`
* **Key Features**:
  * **Entity Lifetimes**: Creates (`createEntity()`) and destroys (`destroyEntity()`) entities. Destroying an entity automatically cleans up all associated components.
  * **Component Management**: Add, remove, or retrieve components dynamically for any entity via type-safe generics:
    * `addComponent<T: Component>(_ component: T, to entity: Entity)`
    * `removeComponent<T: Component>(ofType type: T.Type, from entity: Entity)`
    * `component<T: Component>(ofType type: T.Type, for entity: Entity) -> T?`
  * **Entity Queries**: Retrieve lists of entities possessing a specific component type via `entities(with type: T.Type)`.
  * **System Registration**: Systems are executed in the order they are registered via `registerSystem(_:)` whenever `update(deltaTime:)` is called.

---

## 2. Rendering & Graphics Pipeline

Located under [Engine/Sources/AcornEngine/Renderer](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Renderer):

```mermaid
graph TD
    Renderer[Renderer Protocol]
    MetalRenderer[MetalRenderer] -.->|Implements| Renderer
    
    MetalRenderer --> PipelineState[Standard Mesh Pipeline]
    MetalRenderer --> SpriteState[Sprite Blending Pipeline]
    MetalRenderer --> TextState[SDF Text Blending Pipeline]
    
    Shaders[Shaders.metal] --> PipelineState
    Shaders --> SpriteState
    Shaders --> TextState
```

### [Renderer (Protocol)](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Renderer/Renderer.swift)
An abstraction over the graphic device APIs, facilitating potential future multi-backend support.
* **Key Methods**:
  * `createMesh(vertices: [Vertex]) -> Mesh?`: Generates a hardware vertex buffer.
  * `render(mesh: Mesh, uniforms: GlobalUniforms, context: RenderContext)`: Draws a standard 3D mesh.
  * `renderText(mesh: Mesh, texture: any Texture, uniforms: SDFUniforms, context: RenderContext)`: Draws text using the SDF shader.
  * `renderSprite(mesh: Mesh, texture: any Texture, uniforms: SpriteUniforms, context: RenderContext)`: Draws sprites or tile maps using sprite shaders.

### [MetalRenderer](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Renderer/MetalRenderer.swift)
The concrete implementation of the renderer using Apple's Metal API.
* **Pipelines**: Initializes three separate pipeline states from [Shaders.metal](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Renderer/Shaders.metal):
  1. **Standard Pipeline**: 3D mesh rendering supporting vertex colors, textures, and diffuse lighting (Ambient + multiple Point Lights).
  2. **Sprite Pipeline**: Alpha-blended 2D texture rendering with color tints.
  3. **SDF Text Pipeline**: Alpha-blended rendering mapping distance values to smooth characters and outlines.
* **Context**: Uses `MetalRenderContext` to hold the current command buffer and render pass descriptor. It safely manages a command encoder per frame using locking.

### Texture & Data Loading
* **[Texture (Protocol)](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Renderer/Texture.swift)**: Common interface for texture resources.
* **[MetalTexture](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Renderer/MetalTexture.swift)**: Wraps a Metal `MTLTexture`.
* **[TextureLoader](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Renderer/TextureLoader.swift)**: Decodes images asynchronously from `URL` or `Data` using `MTKTextureLoader`, or uploads raw `[UInt8]` pixel arrays (supporting single-channel `.r8Unorm` for fonts or 4-channel `.rgba8Unorm` formats).

### [GLTFModelLoader](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Renderer/GLTFModelLoader.swift)
Responsible for parsing and loading glTF models (`.glb` / `.gltf`) from disk.
* **Implementation**: Wraps a C++ backend (`AcornMetal` parser) built on top of `fastgltf` and `simdjson`.
* **Output**: Extracts arrays of `MetalMesh` buffers, `GLTFNode` structural configurations (translation, rotation, scale, parents), and embedded texture image binary payloads.

### Mesh & Geometry Basics
* **[Vertex](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Renderer/Vertex.swift)**: A struct containing:
  * `position: SIMD3<Float>`: 3D position vector.
  * `color: SIMD4<Float>`: Vertex RGBA color.
  * `texCoord: SIMD2<Float>`: Texture coordinate (UV) for model mapping.
  * `normal: SIMD3<Float>`: 3D normal vector for surface shading calculations.
* **[MetalMesh](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Renderer/MetalMesh.swift)**: Implements the opaque `Mesh` protocol, managing an underlying `MTLBuffer` with shared storage.

---

## 3. Advanced Renderer Features

AcornEngine includes highly optimized implementations for sprite sheets, tilemaps, and signed distance field text.

### Sprite Sheets & Tilemaps

```
+---------------------------------------------+
| Sprite Sheet Texture                        |
|                                             |
|   +-----------+         +---------------+   |
|   | Frame "A" |         | Frame "B"     |   |
|   +-----------+         +---------------+   |
+---------------------------------------------+
```

* **[SpriteSheet](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Renderer/SpriteSheet.swift)**: Stores a compiled texture atlas along with its layout metadata (decoded from standard TexturePacker JSON array/hash structures). Supports trimmed and rotated frames, calculating precise UV rects.
* **[SpriteMeshGenerator](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Renderer/SpriteMeshGenerator.swift)**:
  * Generates centered quads matching a sprite's source aspect ratio and offset metrics.
  * Generates optimized grid vertices for `TileMapComponent` instances by skipping empty tiles and batching them into a single mesh.

### Signed Distance Field (SDF) Text Rendering

SDF text rendering maintains extreme sharpness and legibility even when scaled or viewed at steep angles, bypassing the pixelation typical of pixel-map text.

```
Grayscale Raster Glyphs ===(SDF Search Radius)===> Distance Field Texture (1 Channel)
```

* **[SDFFontAtlasGenerator](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Renderer/SDFFontAtlasGenerator.swift)**: Generates font atlases dynamically at runtime using CoreText.
  1. Renders glyph contours onto a high-resolution grayscale bitmap.
  2. Runs a 2D bounding distance search inside/outside glyph edges up to a specified search radius.
  3. Packages distance values into a single-channel `.r8Unorm` atlas texture.
  4. Calculates metrics (`size`, `offset`, `xAdvance`, `lineHeight`) for layout.
* **[TextMeshGenerator](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Renderer/TextMeshGenerator.swift)**: Evaluates glyph sequences, handles carriage returns (`\n`), wraps tabs/spaces, and constructs a contiguous triangle stream (quads) in local space.
* **SDF Shader**: Processes distance values inside [Shaders.metal](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Renderer/Shaders.metal#L61-L83) using `smoothstep` edge thresholds:
  * **Anti-aliasing**: Interpolates using a configurable `edgeWidth`.
  * **Outlines**: Employs an `outlineWidth` and `outlineColor` layer rendered underneath the core text body.

---

## 4. Components

Located under [Engine/Sources/AcornEngine/Core/Components](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Components):

### [TransformComponent](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Components/TransformComponent.swift)
Stores the physical placement of an entity in the virtual world.
* **Properties**:
  * `position: SIMD3<Float>`: Coordinates in 3D space.
  * `rotation: SIMD3<Float>`: Euler rotation angles in radians.
  * `scale: SIMD3<Float>`: Scaling factor (default is `[1.0, 1.0, 1.0]`).
  * `matrix: simd_float4x4`: Derived 4x4 model matrix computed via Translation * Rotation * Scale.

### [ParentComponent](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Components/ParentComponent.swift)
Establishes a hierarchical relationship between entities, forming a scene tree hierarchy.
* **Properties**:
  * `parent: Entity`: The parent entity to inherit world transformations from.

### [MeshComponent](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Components/MeshComponent.swift)
Assigns a pre-built static 3D geometry to an entity for rendering.
* **Properties**:
  * `mesh: any Mesh`: An opaque GPU mesh resource.

### [SpriteComponent](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Components/SpriteComponent.swift)
Configures an entity to render as a 2D textured quad.
* **Properties**:
  * `spriteSheet: SpriteSheet`: The underlying atlas.
  * `frameName: String`: Name of the frame within the sheet.
  * `color: SIMD4<Float>`: Tint color (multiplied during rendering).
  * `mesh: (any Mesh)?`: Cached mesh buffer.
  * `isDirty: Bool`: Flag signaling the RenderSystem to rebuild the geometry when frame or color parameters change.

### [TileMapComponent](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Components/TileMapComponent.swift)
Draws a large grid of static sprite tiles.
* **Properties**:
  * `spriteSheet: SpriteSheet`: Atlas containing the tile textures.
  * `columns: Int` / `rows: Int`: Horizontal/vertical tile counts.
  * `tileSize: SIMD2<Float>`: Dimensions of each tile in world units.
  * `tiles: [String]`: Row-major array storing frame names (empty string = empty tile).
  * `color: SIMD4<Float>`: Global tile map tint color.
  * `mesh: (any Mesh)?`: Cached unified grid geometry.
  * `isDirty: Bool`: Indicates if the mesh requires regeneration.
* **Key Methods**:
  * `mutating func setTile(column: Int, row: Int, frameName: String)`: Safely replaces tile reference and marks the grid dirty.

### [TextComponent](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Components/TextComponent.swift)
Enables rendering of rich 3D labels.
* **Properties**:
  * `text: String`: The message to display.
  * `fontAtlas: FontAtlas`: Reference font details.
  * `textColor: SIMD4<Float>`: Primary text body color.
  * `outlineColor: SIMD4<Float>`: Surrounding outline color.
  * `outlineWidth: Float`: Thickness of the outline boundary `[0.0 - 0.5]`.
  * `edgeWidth: Float`: Smoothness factor for anti-aliasing.
  * `mesh: (any Mesh)?`: Cached vertex buffer.
  * `isDirty: Bool`: Indicates if the text mesh must be regenerated.

### [CameraComponent](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Components/CameraComponent.swift)
Declares viewport and projection matrices for rendering.
* **Properties**:
  * `projectionType: ProjectionType`: `.orthographic` or `.perspective`.
  * `orthographicSize: Float`: Vertical half-size for ortho mode.
  * `fovY: Float`: Vertical field of view in radians for perspective mode.
  * `nearZ` / `farZ`: Clipping bounds.
  * `aspectRatio: Float`: Screen aspect ratio.
* **Key Methods**:
  * `func projectionMatrix() -> simd_float4x4`: Returns a matrix optimized for Metal's `[0, 1]` depth range.

### [CameraTrackingComponent](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Components/CameraTrackingComponent.swift)
Commands a camera entity to follow another entity smoothly.
* **Properties**:
  * `target: Entity`: The target entity.
  * `offset: SIMD3<Float>`: Static relative tracking offset.
  * `smoothing: Float`: Interpolation coefficient clamped between `[0.001 - 1.0]` (lower means smoother delay).

### [CameraOrbitComponent](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Components/CameraOrbitComponent.swift)
Commands a camera entity to perform floating orbits around a focal target.
* **Properties**:
  * `target: Entity`: Focal point.
  * `radius: Float`: Distance from the target.
  * `speed: Float`: Orbital rotation speed (rad/s).
  * `baseHeight: Float`: Default height offset.
  * `bobbingAmplitude` / `bobbingSpeed`: Height bobbing oscillation values.
  * `swayAmplitude` / `swaySpeed`: Horizontal sway oscillation values.
  * `useAngleSway: Bool`: If true, sways back-and-forth instead of doing a complete orbit.
  * `swayAngleAmplitude: Float`: Magnitude of back-and-forth angle sway.
  * `time: Double`: Accumulator tracking duration.
  * `angle: Float`: Base rotation angle.

### [PhysicsBodyComponent](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Physics/PhysicsBodyComponent.swift)
Defines physical dynamics properties for an ECS entity to participate in the simulation.
* **Properties**:
  * `type: BodyType`: `.staticBody`, `.kinematicBody`, or `.dynamicBody`.
  * `isAwake: Bool`: Simulation sleep state control.
  * `linearVelocity: SIMD2<Float>` / `angularVelocity: Float`: Velocity vectors.
  * `linearDamping: Float` / `angularDamping: Float`: Energy loss coefficients.
  * `gravityScale: Float`: Multiplier for standard gravity.
  * `isBullet: Bool`: High-speed CCD (Continuous Collision Detection) toggle.
  * `fixedRotation: Bool`: Lock angular motion.

### [PhysicsColliderComponent](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Physics/PhysicsColliderComponent.swift)
Defines physical bounds and collision shape configurations.
* **Properties**:
  * `shapeType: ShapeType`: `.box(width:height:)` or `.circle(radius:)`.
  * `friction: Float`: Resistance to sliding.
  * `restitution: Float`: Bounciness coefficient.
  * `density: Float`: Mass-per-unit-area coefficient.

### [ParticleComponent](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Components/ParticleComponent.swift)
Identifies a particle entity and tracks its age limit.
* **Properties**:
  * `lifetime: Double`: Duration in seconds before deletion.
  * `age: Double`: Elapsed lifespan in seconds.

### [ParticleEmitterComponent](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Components/ParticleEmitterComponent.swift)
Describes particle spawning behavior and randomized template ranges.
* **Properties**:
  * `isEmitting: Bool`: Activity switch.
  * `emitRate: Double`: Particles spawned per second.
  * `meshes: [any Mesh]`: Candidate geometries selected randomly.
  * `lifetime: ClosedRange<Double>`: Lifespan bounds.
  * `linearVelocityX` / `linearVelocityY`: Initialization speed bounds.
  * `angularVelocity: ClosedRange<Float>`: Initial rotation velocity bounds.
  * `scale: ClosedRange<Float>`: Unified scale boundaries.

### [GPSPositionComponent](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Components/GPSPositionComponent.swift)
Tracks an entity's real-world geographical coordinates.
* **Properties**:
  * `coordinate: GPSCoordinate`: The latitude, longitude, and altitude of the entity.

### [LightComponent](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Components/LightComponent.swift)
Defines a light source used for 3D shading calculations.
* **Properties**:
  * `type: LightType`: The type of light source (`.ambient`, `.directional`, or `.point`).
  * `color: SIMD3<Float>`: The color of the light (RGB).
  * `intensity: Float`: The intensity/brightness of the light source.

---

## 5. ECS Systems

Located under [Engine/Sources/AcornEngine/Core/Systems](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Systems) and [Engine/Sources/AcornEngine/Physics](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Physics):

### [CameraSystem](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Systems/CameraSystem.swift)
Updates camera positions and orientations.
* **Operation**:
  * **Standard Tracking**: For entities with `CameraTrackingComponent` and `TransformComponent`, it fetches the target's transform and linearly interpolates (LERP) the camera's position:
    $$\vec{p}_{cam} = \text{mix}(\vec{p}_{cam}, \vec{p}_{target} + \vec{o}_{offset}, s_{smoothing})$$
    If the target is part of a hierarchy, tracking calculates coordinates using the accumulated world position `worldPosition(for:)`.
  * **Orbit & Sway**: For entities with `CameraOrbitComponent` and `TransformComponent`, it accumulates elapsed time, calculates orbit angles, applies vertical bobbing/horizontal sway offsets, and positions the camera. Finally, it calculates pitch and yaw Euler angles to keep the camera pointing directly at the target (using world positions if nested).

### [GPSCoordinateSystem](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Systems/GPSCoordinateSystem.swift)
Coordinates real-world GPS coordinates with local game transforms.
* **Operation**:
  * **Two-way Sync**: Detects changes between `TransformComponent` positions and `GPSPositionComponent` GPS coordinates. If an entity moves in the local world, it translates the coordinates back to GPS. If the GPS coordinates are modified, it updates the transform.
  * **Web Mercator Projection**: Projects latitude and longitude coordinates onto a 2D plane relative to a reference coordinate origin representing $(0,0,0)$ in the game world.

### [RenderSystem](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Systems/RenderSystem.swift)
The pipeline bridge that retrieves visible components, updates dynamic buffers, and builds render commands.
* **Operation**:
  1. **View-Projection Extraction**: Searches for the first active `CameraComponent` in the world. If present, it retrieves its parent entity's world matrix via `worldMatrix(for:)`, takes its inverse to produce the *View Matrix*, and multiplies it by the camera's *Projection Matrix* to get the combined `viewProjectionMatrix`.
  2. **Mesh Rebuilding**: Inspects all `SpriteComponent`, `TextComponent`, and `TileMapComponent` entities. If the `isDirty` flag is true, it triggers generation algorithms to produce a new set of vertices, uploads them to the GPU via `renderer.createMesh(vertices:)`, caches the returned mesh, and resets the dirty flag.
  3. **Z-Sorting Support**: Prior to generating draw commands, the `RenderSystem` automatically queries all `SpriteComponent` entities and sorts them based on their Z coordinate in `TransformComponent` (ascending). This provides correct back-to-front rendering order for 2D sprites.
  4. **Light Gathering**: Collects all active `LightComponent` entities, extracting their positions (via `worldPosition(for:)`) and properties to populate the lighting uniforms passed to the Metal shaders.
  5. **Uniform Packaging & Drawing**:
     * Iterates over `MeshComponent` entities, calculates the MVP matrix utilizing `worldMatrix(for:)` to correctly apply hierarchical parent transforms, and submits them to `renderer.render`.
     * Iterates over `TextComponent` entities, scales them down by a base scaling factor (`0.003`), binds the atlas texture, packages outline parameters into `SDFUniforms`, and calls `renderer.renderText`.
     * Iterates over `SpriteComponent` and `TileMapComponent` entities, binds their sprite sheet texture, packages colors into `SpriteUniforms`, and calls `renderer.renderSprite`.

### [PhysicsSystem](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Physics/PhysicsSystem.swift)
Orchestrates Box2D physics updates and ECS synchronization.
* **Operation**:
  1. **Body Creation**: Automatically constructs Box2D `b2BodyId` and `b2ShapeId` wrappers for entities newly receiving a `PhysicsBodyComponent` and optionally a `PhysicsColliderComponent`.
  2. **Simulation Step**: Advances the Box2D engine context via `b2World_Step` using a set `timeStep` (default `1/60`s) and `subStepCount` (default `4`).
  3. **Transform Sync**: Copies physical states (2D positions and rotations) back to the entities' local `TransformComponent` after simulation steps. If the entity has a parent, it converts the Box2D world position back to parent-relative local coordinates before updating the `TransformComponent`.

### [ParticleSystem](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Systems/ParticleSystem.swift)
Manages dynamic lifecycle loops for emission particles.
* **Operation**:
  1. **Lifecycle Limits**: Traverses `ParticleComponent` records, increments their age by `deltaTime`, and destroys entities that exceed their configured lifetime.
  2. **Emission Intervals**: Evaluates `ParticleEmitterComponent` rate settings, spawns particle entities at emitter coordinate origins, sets random physical velocities, limits, and sizes, and automatically adds Box2D physical bodies and shape colliders.

---

## 6. 2D Physics System (Box2D Integration)

AcornEngine integrates the industry-standard **Box2D v3** library natively. This provides stable, rigid-body dynamics for 2D gameplay.

```mermaid
graph LR
    ECSWorld[ECS World] -->|Updates components| PhysSystem[Physics System]
    PhysSystem -->|Sync positions| B2World[Box2D World]
    B2World -->|Step simulation| B2World
    B2World -->|Sync back| ECSWorld
```

* **World Context**: Handled in `@MainActor` isolation inside `PhysicsSystem`.
* **Timestepping**: Uses fixed-rate updates (`b2World_Step`) to avoid numerical instability under varying frame rates.
* **Collision Shapes**: Supports box quads and circles, scaling geometry dynamically using densities and frictions.
* **Physics State Ownership**: Box2D owns the position and rotation state of active bodies. Manual changes to `TransformComponent` on the Swift side are overwritten by Box2D once simulated, ensuring simulation consistency.

### Usage Example:
```swift
// Create a dynamic physics-enabled block
let block = world.createEntity()
world.addComponent(TransformComponent(position: [0.0, 5.0, 0.0]), to: block)
world.addComponent(PhysicsBodyComponent(type: .dynamicBody), to: block)
world.addComponent(PhysicsColliderComponent(
    shapeType: .box(width: 1.0, height: 1.0),
    friction: 0.2,
    restitution: 0.5
), to: block)
```

---

## 7. 2D Particle System

The Particle System leverages ECS architecture and the Physics System to create high-performance dynamic effects (such as explosions, sparks, or ambient debris).

```mermaid
graph TD
    Emitter[Emitter Component] -->|Tick emitRate| PartSystem[Particle System]
    PartSystem -->|Create Entity| NewPart[New Particle Entity]
    NewPart --> Transform[TransformComponent]
    NewPart --> PartComp[ParticleComponent]
    NewPart --> MeshComp[MeshComponent]
    NewPart --> PhysBody[PhysicsBodyComponent]
    NewPart --> PhysCollider[PhysicsColliderComponent]
```

* **Entity-Based Particles**: Unlike vertex-only particle pools, particles in AcornEngine are fully fledged ECS entities. This allows particles to seamlessly interact with Box2D collision geometry, wind/forces, or even receive specialized rendering/shader behaviors.
* **Automatic Cleanup**: Since particles have `ParticleComponent` and optionally physics attachments, the `ParticleSystem` handles age increments, and when they expire, `world.destroyEntity()` automatically tears down the associated Box2D physical bodies and shapes.

### Usage Example:
```swift
// Set up a continuous fire/spark emitter
let emitter = world.createEntity()
world.addComponent(TransformComponent(position: [0.0, 0.0, 0.0]), to: emitter)
world.addComponent(ParticleEmitterComponent(
    isEmitting: true,
    emitRate: 30.0,
    meshes: [starMesh, squareMesh],
    lifetime: 0.5...1.5,
    linearVelocityX: -2.0...2.0,
    linearVelocityY: 3.0...6.0,
    angularVelocity: -5.0...5.0,
    scale: 0.02...0.08
), to: emitter)
```

---

## 8. Core Math Extensions

Located under [Engine/Sources/AcornEngine/Core/Math.swift](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Math.swift):

Extends `simd_float4x4` with projection and transform helpers tailored for Metal (where Normalized Device Coordinates mapping for Z is $[0, 1]$):
* **Identity**: `simd_float4x4.identity` returns `matrix_identity_float4x4`.
* **Translation**: `init(translation: SIMD3<Float>)`
* **Scale**: `init(scale: SIMD3<Float>)`
* **Rotations**: Individual axis matrix initialization (`init(rotationX:)`, `init(rotationY:)`, `init(rotationZ:)`) and composite Euler angles (`init(rotation:)`).
* **Model Matrix**: `init(position:rotation:scale:)` combining Translation * Rotation * Scale matrices.
* **Orthographic Projection**: 
  $$\mathbf{P}_{ortho} = \begin{bmatrix} \frac{2}{r-l} & 0 & 0 & -\frac{r+l}{r-l} \\ 0 & \frac{2}{t-b} & 0 & -\frac{t+b}{t-b} \\ 0 & 0 & \frac{1}{f-n} & -\frac{n}{f-n} \\ 0 & 0 & 0 & 1 \end{bmatrix}$$
* **Perspective Projection**:
  $$\mathbf{P}_{persp} = \begin{bmatrix} \frac{1}{a \tan(\theta/2)} & 0 & 0 & 0 \\ 0 & \frac{1}{\tan(\theta/2)} & 0 & 0 \\ 0 & 0 & \frac{f}{f-n} & 1 \\ 0 & 0 & -\frac{n f}{f-n} & 0 \end{bmatrix}$$
  *(Note the transposed columns layout mapping to SIMD structures)*

### GPS Web Mercator Projection
Located under [GPSCoordinateSystem.swift](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Core/Systems/GPSCoordinateSystem.swift), latitude ($\phi$) and longitude ($\lambda$) in radians are projected using:
$$x = R \lambda$$
$$y = R \ln\left(\tan\left(\frac{\pi}{4} + \frac{\phi}{2}\right)\right)$$
where $R = 6378137.0$ meters represents the equatorial radius of the Earth.

Inverse Web Mercator projection maps local projected coordinate positions back into geographical coordinates via:
$$\lambda = \frac{x}{R}$$
$$\phi = 2 \arctan\left(e^{y/R}\right) - \frac{\pi}{2}$$
