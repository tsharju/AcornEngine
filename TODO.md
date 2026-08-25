# AcornEngine - Development Roadmap & TODO List

This document tracks upcoming features, architectural improvements, and roadmap milestones for **AcornEngine**.

---

## 🎯 Priority 1: Core Systems & Foundational Gameplay

- [x] **Unified Input System & Event Dispatcher**
  - [x] Implement `InputSystem` managing keyboard, mouse, and touch pointer states.
  - [x] Integrate Apple's `GameController` framework for MFi, Xbox, and PlayStation gamepads.
  - [x] Add an ECS `EventBus` / message stream for decoupled event handling (e.g. input actions, lifecycle events).
- [x] **Physics Contact Events & Callbacks**
  - [x] Bridge Box2D v3 contact events (`b2ContactEvents`) into Swift ECS.
  - [x] Add `CollisionEnterEvent`, `CollisionStayEvent`, and `CollisionExitEvent`.
  - [x] Implement `SensorTriggerComponent` for trigger zones and non-solid volume queries.
- [x] **Audio Subsystem (`AudioSystem`)**
  - [x] Implement `AudioSystem` backed by `AVAudioEngine`.
  - [x] Create `AudioSourceComponent` (audio clips, volume, pitch, looping, spatial 3D attenuation).
  - [x] Create `AudioListenerComponent` attached to the active camera or player entity.

---

## 🚀 Priority 2: Rendering Pipeline & Performance

- [x] **Instanced Rendering & Draw Call Batching**
  - [x] Implement dynamic instance buffers for `SpriteComponent` and `ParticleEmitterComponent`.
  - [x] Add instanced mesh rendering (`drawIndexedPrimitives:instanceCount:`) for repeated 3D geometry.
- [ ] **Physically Based Rendering (PBR) & Multi-Light Support**
  - [ ] Implement glTF 2.0 Metallic-Roughness PBR pipeline in Metal shaders.
  - [ ] Support normal maps, roughness/metallic maps, ambient occlusion (AO), and emissive textures.
  - [ ] Implement dynamic light buffers supporting multiple point, directional, and spot lights.
- [ ] **Frustum & Occlusion Culling**
  - [ ] Calculate Axis-Aligned Bounding Boxes (AABB) and bounding spheres for meshes and sprite batches.
  - [ ] Implement camera frustum culling to skip off-screen draw calls in `RenderSystem`.
- [ ] **Shadow Mapping**
  - [ ] Add shadow map render passes for directional lights (with depth bias & PCF soft shadows).
  - [ ] Implement Cascaded Shadow Maps (CSM) for large outdoor scenes.

---

## 🛠️ Priority 3: Asset Pipeline & Editor Tooling

- [ ] **Scene Serialization & Prefabs**
  - [ ] Implement `Codable` conformance across standard ECS components.
  - [ ] Create `.acornscene` and `.acornprefab` JSON/binary file format support for saving and loading worlds.
- [ ] **Interactive 3D Viewport Gizmos**
  - [ ] Add 3D translation, rotation, and scale transform gizmos in the editor viewport.
  - [ ] Implement mouse-raycast entity picking in the 3D scene view.
- [ ] **Editor Simulation State Controller**
  - [ ] Add Play, Pause, and Single-Step execution controls in `MacEditor`.
  - [ ] Implement scene snapshot and restore on play/stop.
- [ ] **Asset Management Panel**
  - [ ] Add project directory asset browser in Dear ImGui.
  - [ ] Support drag-and-drop asset assignment for textures, glTF models, and audio clips into inspector fields.

---

## 🔮 Priority 4: Advanced Engine Features

- [ ] **3D Skeletal Animation & Skinning**
  - [ ] Load skinning joints and inverse bind matrices from glTF models via `fastgltf`.
  - [ ] Evaluate animation channels (translation, rotation, scale keyframes) with interpolation.
  - [ ] Compute bone matrices on GPU in vertex shaders.
- [ ] **3D Physics & Spatial Queries**
  - [ ] Integrate 3D collision detection and raycasting (e.g. Jolt Physics or lightweight custom 3D collider system).
  - [ ] Add 3D character controller component.
- [ ] **Post-Processing Pipeline**
  - [ ] Implement render-to-texture multi-pass pipeline.
  - [ ] Add Bloom, ACES Tonemapping, Color Grading, and FXAA anti-aliasing passes.
- [ ] **In-Game 2D UI & Canvas Framework**
  - [ ] Implement anchor-based 2D UI canvas with layout hierarchies.
  - [ ] Add interactive UI components (Buttons, Sliders, Progress Bars, Text Labels).
