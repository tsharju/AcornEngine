# AcornEngine - 2D Game Development Roadmap & TODO List

This document tracks completed milestones, upcoming features, architectural improvements, and roadmap priorities for **AcornEngine**, with a dedicated focus on building a world-class **2D game engine** for Apple platforms (iOS, iPadOS, macOS) using Swift 6 and Metal.

---

## ✅ Completed Milestones

- [x] **Entity Component System (ECS) & Decoupled EventBus**
  - [x] Data-oriented component storage, entity lifecycle management, and system pipelines.
  - [x] Hierarchical parent-child transform propagation (`ParentComponent`).
  - [x] High-performance `EventBus` supporting immediate dispatches and frame-buffered queries.
- [x] **Unified Input Subsystem & Game Controllers**
  - [x] Unified `InputSystem` managing keyboard, mouse/trackpad pointer, scroll deltas, and multi-touch gestures.
  - [x] Apple `GameController` framework bridge supporting MFi, Xbox, and PlayStation gamepads.
- [x] **2D Physics Simulation & Contact Events (Box2D v3)**
  - [x] Native integration of Box2D v3 rigid body dynamics with ECS transform synchronization.
  - [x] Contact manifold events (`CollisionEnterEvent`, `CollisionStayEvent`, `CollisionExitEvent`).
  - [x] Non-solid trigger zones (`SensorTriggerComponent`, `SensorEnterEvent`, `SensorExitEvent`).
- [x] **Audio Subsystem (`AudioSystem`)**
  - [x] Native `AudioSystem` powered by `AVAudioEngine` with 2D panning and 3D spatial sound (`AVAudioEnvironmentNode`).
  - [x] `AudioSourceComponent` and `AudioListenerComponent` with volume, pitch, looping, and distance attenuation.
  - [x] Event-driven one-shot sound effects (`PlaySoundEvent`, `StopAllSoundsEvent`).
- [x] **Metal Graphics Backend & Hardware Instancing**
  - [x] Hardware-accelerated 2D sprite batching (`renderSpritesInstanced`) with dynamic instance buffers.
  - [x] Texture atlas and sprite sheet support (`SpriteSheet`) with trimmed and rotated frame decoding.
  - [x] Scalable Signed Distance Field (SDF) text rendering with outline and anti-aliasing shaders.
  - [x] Base 2D particle emitter entity pipeline (`ParticleEmitterComponent`, `ParticleSystem`).

---

## 🎯 Priority 1: Core 2D Animation, Layering & Camera Systems

- [x] **2D Sprite Flipbook Animation System**
  - [x] Create `SpriteAnimationComponent` with support for named animation clips (e.g. "idle", "run", "jump", "attack").
  - [x] Implement `SpriteAnimationSystem` handling frame timing (FPS), playback modes (`.once`, `.loop`, `.pingPong`), and state transitions.
  - [x] Support animation frame notification events (e.g. `AnimationFrameEvent` for syncing footstep sounds, attack hitboxes, and particle spawns).
- [ ] **Sprite Slicing (9-Slice / 3-Slice Scaling)**
  - [ ] Support 9-slice / 3-slice sprite borders and center tiling/stretching in `SpriteComponent`.
  - [ ] Generate 9-slice vertex geometry dynamically for scalable platforms, dialogue boxes, and UI panels without texture distortion.
- [ ] **2D Sprite Layering & Depth Sorting (Y-Sorting)**
  - [ ] Add `SortingLayerComponent` with customizable sorting layers (e.g., Background, Terrain, Characters, Foreground, UI) and integer `orderInLayer`.
  - [ ] Implement dynamic Y-sorting for top-down 2D games (entities lower on screen render in front of entities higher up).
  - [ ] Add Sprite Flip ($X/Y$ axes) and custom pivot/anchor offsets (e.g. bottom-center, top-left, center).
- [ ] **Dedicated 2D Camera Controller & Effects**
  - [ ] Implement `Camera2DComponent` and `Camera2DSystem` with target deadzones (bounding box where movement doesn't shift the camera).
  - [ ] Add camera bounding box clamping (restricting camera movement within level boundaries).
  - [ ] Implement screen shake & trauma system (decaying positional/rotational camera kick on impacts).
  - [ ] Add pixel-perfect orthographic projection and integer scaling modes to eliminate sub-pixel jitter in retro 2D pixel art.

---

## 🗺️ Priority 2: Tilemaps, World Building & Level Design

- [ ] **Multi-Layer Tilemap Architecture**
  - [ ] Extend `TileMapComponent` to support multiple distinct layers (Background, Midground/Walls, Foreground, Collision).
  - [ ] Add per-layer opacity, tint color, and parallax scroll rate factors.
- [ ] **Automated Tilemap Collider Generator (Box2D)**
  - [ ] Implement automatic Box2D static collider generation from solid tilemap cells.
  - [ ] Merge contiguous adjacent tiles into composite polygon / edge chains to prevent "ghost collisions" (catching on internal tile seams).
- [ ] **Parallax Scrolling Background System**
  - [ ] Implement `ParallaxBackgroundComponent` and `ParallaxSystem` with infinite horizontal/vertical texture repeating.
  - [ ] Support configurable velocity factors per layer relative to active camera motion.
- [ ] **2D Level Data Importers (Tiled / LDtk)**
  - [ ] Add parser for LDtk (`.ldtk`) and Tiled (`.tmj` / `.tmx`) JSON map formats.
  - [ ] Automatically instantiate tile layers, entity spawn points, collision geometry, and custom layer metadata into ECS worlds.
- [ ] **Autotiling & Animated Tile Support**
  - [ ] Add animated tile frame sequences (e.g., flowing water, torches, lava).
  - [ ] Support rule-based autotiling (bitmask 16-pipe / 47-pipe auto-connections for terrain edges and corners).

---

## 🕹️ Priority 3: 2D Character Controllers, Gameplay & Physics

- [ ] **2D Kinematic Character Controller**
  - [ ] Implement `KinematicCharacterController2D` system for responsive, precise platformer and top-down character movement.
  - [ ] Handle one-way / jump-through platforms (allowing characters to jump up through floors and drop down with a down-jump input).
  - [ ] Implement slope handling (walking up and down angled surfaces smoothly without bouncing or slipping).
  - [ ] Add ground checks, wall-slide detection, and ledge-climbing raycast helpers.
- [ ] **Expanded 2D Physics Colliders & Joint Constraints**
  - [ ] Add 2D Capsule colliders (crucial for smooth character movement over irregular terrain).
  - [ ] Add Convex Polygon colliders and Chain / Edge loop colliders in `PhysicsColliderComponent`.
  - [ ] Bridge Box2D v3 joints: `DistanceJointComponent`, `RevoluteJointComponent` (pivots/hinges), `PrismaticJointComponent` (pistons/elevators), and `MotorJointComponent`.
- [ ] **2D Spatial Queries & Raycasting API**
  - [ ] Implement `world.raycast2D(from:to:mask:)` returning raycast hit points, surface normals, fractions, and hit entities.
  - [ ] Add AABB shape overlap queries and circle sweep casts for explosion blast radii and proximity detection.
- [ ] **Collision Filtering & Layer Matrix**
  - [ ] Add `CollisionFilterComponent` with 16-bit category bits, mask bits, and group indices.
  - [ ] Implement a global collision matrix configuration to define which layers interact (e.g., Player vs Enemy vs PlayerBullets vs Terrain).

---

## 🎨 Priority 4: 2D Visual Effects, Shaders & 2D Lighting

- [ ] **2D Sprite Shaders & Blend Modes**
  - [ ] Support GPU blend modes in `SpriteComponent`: Alpha Blended, Additive (fire/glow), Multiply (shadows/fog), and Screen.
  - [ ] Add built-in sprite effect shaders: Hit-Flash (solid white/color damage flash), Sprite Outline, Desaturation / Grayscale, and Color Grading LUTs.
- [ ] **High-Performance 2D Particle System Enhancements**
  - [ ] Add GPU-batched 2D particle emitter (`Particle2DComponent`) bypassing heavyweight entity overhead for large particle counts.
  - [ ] Support color-over-lifetime (RGBA gradients), size-over-lifetime curves, and radial/tangential acceleration.
  - [ ] Add burst emission triggers and sub-emitter events (e.g. spawn smoke trails or explosion debris upon particle death).
- [ ] **2D Lighting & Shadow Casters**
  - [ ] Implement 2D Point Lights, Spot Lights / Cones (e.g., flashlights, streetlamps) in Metal shaders.
  - [ ] Implement 2D shadow casting via 1D shadow map passes or polygon shadow volume extrusion.
  - [ ] Add ambient lighting layer and day/night cycle color grading.
- [ ] **2D Ribbon / Trail Renderer**
  - [ ] Implement `TrailRendererComponent` generating dynamic quad strips for sword swings, bullet traces, and dash shadows.

---

## 🖼️ Priority 5: In-Game 2D UI & HUD Framework

- [ ] **Anchor-Based 2D UI Canvas**
  - [ ] Implement screen-space and world-space UI canvas hierarchy (`UIElementComponent`, `CanvasComponent`).
  - [ ] Support flexible layout anchors (top-left, center, bottom-stretch, fill) with automatic safe-area margin handling for iOS / iPadOS notches and dynamic islands.
- [ ] **Interactive 2D UI Widgets**
  - [ ] 9-Slice Sprite Buttons with normal, hover, pressed, and disabled visual states.
  - [ ] Progress / Health Bars with foreground filling, background backing, and smooth animated value interpolation.
  - [ ] Text labels integrated with SDF Font rendering, alignment (left/center/right), and auto-wrapping.
  - [ ] Slider, Toggle / Checkbox, and Scroll View containers.
- [ ] **Pointer & Touch UI Event Dispatcher**
  - [ ] Add UI hit testing and pointer event propagation (`UIPointerDownEvent`, `UIPointerUpEvent`, `UIClickEvent`).
  - [ ] Implement UI input sinking (preventing touches/clicks on UI buttons from triggering gameplay actions in the world beneath).

---

## 🧩 Priority 6: Scene Management, AI & 2D Game Utilities

- [ ] **Scene Lifecycle & Screen Transitions**
  - [ ] Implement `SceneManager` with support for loading, unloading, and additive scene loading.
  - [ ] Add built-in screen transitions: Fade to Black / Color, Cross-Dissolve, Slide, and Wipe shaders.
- [ ] **2D Grid Pathfinding (A* / NavGrid)**
  - [ ] Implement 2D A* pathfinding system for tilemaps and grid-based movement.
  - [ ] Support dynamic obstacle tagging, diagonal movement toggles, and terrain movement cost weights.
- [ ] **Finite State Machine (FSM) & Behavior Trees**
  - [ ] Provide lightweight generic `StateMachine` and `StateComponent` for character states (Idle, Walk, Jump, Fall, Attack, Hurt, Dead).
- [ ] **2D Audio Management & SFX Utilities**
  - [ ] Add background music (BGM) playlist player with cross-fading and looping.
  - [ ] Add random pitch and volume variation on SFX playback to prevent sound fatigue during repetitive actions (e.g. footsteps, gunshots).

---

## 🛠️ Priority 7: 2D-Focused Editor Tooling & Developer Experience

- [ ] **2D Editor Viewport Mode**
  - [ ] Add dedicated 2D mode toggle in `MacEditor` with orthographic pan (middle mouse / trackpad) and zoom controls.
  - [ ] Add 2D background grid overlay with configurable grid cell sizing and snapping.
- [ ] **2D Transform & Bounds Gizmo**
  - [ ] Implement 2D translation and scale/resize handles in the editor viewport.
  - [ ] Add interactive pivot/anchor point visual manipulation.
- [ ] **Visual Tilemap Palette & Painting Tool**
  - [ ] Create Dear ImGui tile palette inspector displaying sprite sheet tiles.
  - [ ] Implement interactive viewport painting tools: Pencil/Brush, Rectangle Fill, Eraser, and Bucket Fill directly into `TileMapComponent`.
- [ ] **Physics & Collider Debug Visualizer**
  - [ ] Add toggleable wireframe debug overlay rendering Box2D colliders (boxes, circles, capsules, polygons, sensors) and contact points.
  - [ ] Render velocity vectors and raycast query lines in real-time.
- [ ] **Sprite Animation Previewer & Hitbox Editor**
  - [ ] Add timeline scrubber and animation preview window in the editor.
  - [ ] Provide interactive visual editor for defining attack hitboxes and hurtboxes per animation frame.
- [ ] **Scene & Prefab Serialization**
  - [ ] Implement `Codable` conformance across standard 2D ECS components.
  - [ ] Create `.acornscene` and `.acornprefab` JSON format support for saving, loading, and instantiating 2D game worlds.

---

## 📦 Future & Secondary: 3D / Hybrid Engine Extensions

- [ ] **glTF 2.0 PBR & Multi-Light Rendering**: Metallic-Roughness PBR pipeline, normal maps, dynamic light buffers.
- [ ] **3D Skeletal Animation**: Joint skinning and GPU bone matrix calculation via `fastgltf`.
- [ ] **3D Physics & Character Controllers**: Jolt Physics integration or lightweight 3D collider system.
- [ ] **Post-Processing Pass Pipeline**: Bloom, ACES Tonemapping, Color Grading, and FXAA anti-aliasing.

