<p align="center">
  <a href="file:///Users/tsharju/Code/AcornEngine/Samples/AcornSampleApp/AcornSampleApp/Assets.xcassets/AppIcon.appiconset/AcornEngine-Icon-1024x1024.png">
    <img src="Samples/AcornSampleApp/AcornSampleApp/Assets.xcassets/AppIcon.appiconset/AcornEngine-Icon-1024x1024.png" alt="AcornEngine Logo" width="180" height="180">
  </a>
</p>

# AcornEngine


AcornEngine is a modern, high-performance 2D/3D game engine targetting Apple platforms (**iOS 16+** and **macOS 13+**). It is built from the ground up using **Swift 6** with strict concurrency safety (`Sendable` conformance and `@MainActor` isolation where appropriate) and leverages the **Metal** graphics API for hardware-accelerated rendering.

---

## Key Features

* **Entity Component System (ECS)**: Type-safe, data-oriented architecture designed with strict separation between data ([Component](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/ECS/Component.swift) structs) and logic ([System](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/ECS/System.swift) classes). The ECS [World](file:///Users/tsharju/Code/AcornEngine/Engine/Sources/AcornEngine/ECS/World.swift) handles thread-safe lifecycle ticks and queries.
* **Metal Rendering Backend**: Low-overhead hardware-accelerated graphics API. Includes optimized shader pipelines for:
  - Standard 3D mesh rendering with vertex colors.
  - Trimmed, rotated, and tinted 2D sprites backed by packed sprite sheets.
  - High-quality, scalable **Signed Distance Field (SDF) Text Rendering** supporting runtime font generation, outlines, and anti-aliasing.
* **2D Physics Engine**: Direct native integration of the industry-standard **Box2D v3** library, driving fast rigid body dynamics with automatic synchronization back to ECS transforms.
* **2D Particle System**: Fully integrated with the ECS & Physics system. Particles are fully realized entities that can collide with physical geometry and bounce, scale, or fade dynamically.
* **Native macOS Editor**: A companion Cocoa desktop editor rendering interactive scene trees, editable inspectors, and 3D line grids using **Dear ImGui** (wrapped using Swift C++ interop).
* **Metal-Optimized Math**: Coordinate transformations and perspective/orthographic projections tailored for Metal's standard NDC depth ranges ($[0, 1]$).

---

## Directory Structure

```
AcornEngine/
├── Engine/                 # Core AcornEngine package
│   ├── Sources/            # ECS, Metal Renderer, Math, Box2D bindings, and Systems
│   └── Tests/              # Comprehensive test coverage using Swift Testing
├── Editor/                 # Native macOS desktop editor
│   ├── Sources/AcornEditor # Editor entry point, Cocoa windowing, and panels
│   └── Sources/ImGui       # Dear ImGui C++ source wrap
├── Samples/                # Sample demonstration projects
│   ├── AcornSampleApp/     # General feature showcase (iOS & macOS target)
│   └── MatchAcorn/         # 2D physics-based game built with AcornEngine
└── README.md               # Repository introduction (This file)
```

---

## Documentation Links

For more details on how to build, run, and modify individual components, refer to their respective READMEs:

* [Engine Documentation](file:///Users/tsharju/Code/AcornEngine/Engine/README.md) – Deep dive into the Entity Component System, Metal Renderer pipelines, Box2D physics simulation, 2D particle emitter, and coordinate geometry math.
* [Editor Documentation](file:///Users/tsharju/Code/AcornEngine/Editor/README.md) – In-depth guide on the macOS desktop workspace, Dear ImGui interop structure, Cocoa and Metal integration delegates, and interactive line-projection drawing.

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

The sample applications are standard Xcode projects located in the `Samples/` directory.
- Open [AcornSampleApp.xcodeproj](file:///Users/tsharju/Code/AcornEngine/Samples/AcornSampleApp/AcornSampleApp.xcodeproj) or [MatchAcorn.xcodeproj](file:///Users/tsharju/Code/AcornEngine/Samples/MatchAcorn/MatchAcorn.xcodeproj) in Xcode.
- Configure active schemes for macOS or iOS simulators, and click **Run**.
