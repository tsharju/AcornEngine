<p align="center">
  <a href="file:///Users/tsharju/Code/AcornEngine/Samples/AcornSampleApp/AcornSampleApp/Assets.xcassets/AppIcon.appiconset/AcornEngine-Icon-1024x1024.png">
    <img src="Samples/AcornSampleApp/AcornSampleApp/Assets.xcassets/AppIcon.appiconset/AcornEngine-Icon-1024x1024.png" alt="AcornEngine Logo" width="180" height="180">
  </a>
</p>

# AcornEngine


AcornEngine is a modern, high-performance 2D/3D game engine targeting Apple platforms (**iOS 16+** and **macOS 13+**). It is built from the ground up using **Swift 6** with strict concurrency safety (`Sendable` conformance and `@MainActor` isolation where appropriate) and leverages the **Metal** graphics API for hardware-accelerated rendering.

---

## Key Features

* **Entity Component System (ECS) & Decoupled EventBus**:
  - Type-safe, data-oriented architecture strictly separating data ([Component](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/ECS/Component.swift) structs) and logic ([System](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/ECS/System.swift) classes).
  - Hierarchical **Parent-Child Transform System** (`ParentComponent`) for tree-like coordinate propagation.
  - High-performance, decoupled **[EventBus](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/ECS/EventBus.swift)** supporting type-safe event subscriptions (`subscribe`), immediate dispatches (`publish`), and per-frame event buffering (`events(ofType:)`).
* **Metal Rendering Backend & GPU Instancing**:
  - Low-overhead hardware-accelerated graphics API supporting textured 3D meshes with lighting (ambient, directional, and point light sources).
  - **GPU Instanced Rendering & Draw Call Batching**: Batches repeated 3D meshes (`renderInstanced`) and 2D sprite entities (`renderSpritesInstanced`) into single hardware draw calls using dynamic instance buffers.
  - High-performance **glTF (.gltf / .glb) model loading** with texture maps and parent-child node structures.
  - Trimmed, rotated, and tinted 2D sprites backed by packed sprite sheets with automatic Z-sorting.
  - High-quality, scalable **Signed Distance Field (SDF) Text Rendering** supporting runtime font generation, outlines, and anti-aliasing.
* **Unified Input Subsystem & Game Controllers**:
  - Consolidated **[InputSystem](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Input/InputSystem.swift)** and `InputState` providing unified tracking across keyboard, mouse/trackpad pointer & scroll deltas, and multi-touch gestures.
  - Native integration with Apple's **GameController** framework (`GameControllerBridge`) supporting MFi, Xbox, and PlayStation gamepads with thumbstick analog axes, D-pad, and pressure buttons.
* **3D Spatial Audio Subsystem**:
  - Native **[AudioSystem](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/Audio/AudioSystem.swift)** powered by `AVAudioEngine` and `AVAudioEnvironmentNode`.
  - Positional 3D audio listener (`AudioListenerComponent`) and audio sources (`AudioSourceComponent`) with attenuation, pitch, volume, looping, reverb blend, and multiple spatial rendering algorithms (Equal Power Panning, Spherical Head, HRTF, Sound Field).
  - Event-driven playback support via `PlaySoundEvent` and `StopAllSoundsEvent`.
* **2D Physics Engine & Contact Events**:
  - Direct native integration of the industry-standard **Box2D v3** library, driving rigid body dynamics synchronized back to ECS transforms.
  - **Contact Events & Callbacks**: Bridges Box2D contact manifolds into ECS events (`CollisionEnterEvent`, `CollisionStayEvent`, `CollisionExitEvent`).
  - **Sensor & Trigger Volumes**: Non-solid `SensorTriggerComponent` supporting trigger zones and overlap tracking (`SensorEnterEvent`, `SensorStayEvent`, `SensorExitEvent`).
* **2D Particle System**: Fully integrated with the ECS & Physics system. Particles are fully realized entities that can collide with physical geometry and bounce, scale, or fade dynamically.
* **GPS Coordinate Mapping**: Real-world geographical location sync (`GPSPositionComponent` and `GPSCoordinateSystem`) converting latitude, longitude, and altitude to 3D world coordinates using the Web Mercator projection.
* **Native macOS & iOS Editor**: A companion Dear ImGui editor featuring scene hierarchies, editable inspectors, dynamic component injection (including transform, lights, audio, and physics), and 3D line grids. Supports macOS and iPad builds with UIKit touch-to-mouse mapping, Retina display scaling, and safe area layouts.
* **Metal-Optimized Math**: Coordinate transformations and perspective/orthographic projections tailored for Metal's standard NDC depth ranges ($[0, 1]$).

---

## Directory Structure

```
AcornEngine/
├── Engine/                 # Core AcornEngine package
│   ├── Sources/            # ECS, EventBus, Input, Audio, Renderer, Math, Box2D bindings, and Systems
│   └── Tests/              # Comprehensive test coverage using Swift Testing
├── Editor/                 # Native macOS & iOS desktop/tablet editor
│   ├── Sources/AcornEditor # Editor entry point, Cocoa windowing, and inspector panels
│   ├── AcornEditoriOS/     # Native iPad UIKit editor target
│   └── Sources/ImGui       # Dear ImGui C++ source wrap
├── Samples/                # Sample demonstration projects
│   ├── AcornSampleApp/     # General feature showcase (iOS & macOS target)
│   ├── MatchAcorn/         # 2D physics-based match puzzle game
│   ├── AcornJump/          # 2D physics platformer demo (contacts, sensors, input, audio)
│   └── Acorn3DSample/      # 3D glTF model showcase and orbit camera demo
└── README.md               # Repository introduction (This file)
```

---

## Documentation Links

For more details on how to build, run, and modify individual components, refer to their respective READMEs:

* [Engine Documentation](Engine/README.md) – Deep dive into the Entity Component System, EventBus, Unified Input, 3D Spatial Audio, Metal Renderer & Instancing, Box2D physics simulation & contacts, 2D particle emitter, and coordinate geometry math.
* [Editor Documentation](Editor/README.md) – In-depth guide on the macOS desktop workspace, Dear ImGui interop structure, Cocoa and Metal integration delegates, inspectable components, and interactive line-projection drawing.
* [Roadmap & TODO List](TODO.md) – Feature roadmap, technical priorities, and planned subsystems.

---

## Getting Started

### Building the Engine Target

1. Navigate to the core Engine package:
   ```bash
   cd Engine
   ```
2. Build the package library:
   ```bash
   swift build
   ```
3. Run the automated suite:
   ```bash
   swift test
   ```

### Running the macOS Editor

1. Navigate to the Editor folder:
   ```bash
   cd Editor
   ```
2. Run the application:
   ```bash
   swift run
   ```

### Running the Samples

The sample applications are standard Xcode projects located in the `Samples/` directory:
- [AcornSampleApp.xcodeproj](file:///Users/tsharju/Code/AcornEngine/Samples/AcornSampleApp/AcornSampleApp.xcodeproj) – General engine feature showcase.
- [MatchAcorn.xcodeproj](file:///Users/tsharju/Code/AcornEngine/Samples/MatchAcorn/MatchAcorn.xcodeproj) – Physics-driven match game.
- [AcornJump.xcodeproj](file:///Users/tsharju/Code/AcornEngine/Samples/AcornJump/AcornJump.xcodeproj) – Platformer demonstrating physics contacts, sensor triggers, game controllers, and audio.
- [Acorn3DSample.xcodeproj](file:///Users/tsharju/Code/AcornEngine/Samples/Acorn3DSample/Acorn3DSample.xcodeproj) – 3D glTF model viewer with lighting and textures.

Open any project in Xcode, select an active macOS or iOS simulator scheme, and click **Run**.
