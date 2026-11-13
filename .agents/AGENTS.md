# AcornEngine - Development Rules

This file outlines the development rules, directory conventions, and coding style requirements for the **AcornEngine** project. All agents and developers must adhere to these guidelines.

---

## 1. Project Overview & Tech Stack
* **Language**: Swift (targeting Swift 6.2+ with Strict Concurrency enabled).
* **Dependency Manager**: Swift Package Manager (SPM).
* **Testing Framework**: Swift Testing (`Testing` library) for all new unit and integration tests. (Do not use `XCTest` unless writing UI tests).

---

## 2. Directory Structure Conventions
As the codebase grows, organize modules and sources using the following standard layout:
* `/Sources/` - Main library/executable target sources.
  * Group by feature area or architectural layers (e.g., `Core/`, `Engine/`, `Math/`).
* `/Tests/` - Test targets matching the structure of `Sources`.
* `/.agents/` - Agent customization root (skills and rules).

---

## 3. Style & Coding Guidelines

### AcornEngine Architecture & APIs
* Refer to the local [acorn-engine](file://.agents/skills/acorn-engine/SKILL.md) skill for architecture, ECS patterns, EventBus, 2D flipbook animation, 3D rendering, Box2D physics, spatial audio, unified input, and implementation recipes.

### Swift API Design
* Follow the Swift API Design Guidelines strictly. Refer to the local [swift-api-design-guidelines-skill](file://.agents/skills/swift-api-design-guidelines-skill/SKILL.md) for details on naming, parameter labeling, and fluency.
* Write concise documentation comments for every public/internal type and function.

### Swift Concurrency
* Avoid legacy concurrency patterns (e.g., completion handlers, manual dispatch queues). Use modern async/await, Tasks, and Actors.
* Refer to the local [swift-concurrency-pro](file://.agents/skills/swift-concurrency-pro/SKILL.md) skill to ensure correct actor-isolation and avoid data races.

### Formatting & Types
* Prefer `struct` over `class` by default for data models and stateless logic.
* Use modern Swift `FormatStyle` APIs for string formatting. Refer to [swift-format-style](file://.agents/skills/swift-format-style/SKILL.md).

---

## 4. Testing Requirements
* Every new feature or fix must be accompanied by unit tests.
* Write tests using the `struct`-based Swift Testing model. Refer to the local [swift-testing-pro](file://.agents/skills/swift-testing-pro/SKILL.md) skill.
* Ensure tests run and pass locally before proposing or committing changes.

---

## 5. Development Workflows
* **Build Command**: `swift build`
* **Test Command**: `swift test`

---

## 6. Agent Orchestration & Task Decomposition
* **Task Delegation**: For any non-trivial task, aggressively split work across subagents by invoking parallel subagents (e.g., separating research, refactoring, writing unit tests, and validation). Always attempt to delegate isolated sub-tasks to specialized subagents to parallelize work and maintain clean context boundaries.

---

## 7. Visual Verification & Automated Feedback Loop
For any visual, rendering, or shader-related changes (e.g., changes to `NoGraphicsRenderer`, `AcornRHI`, `RenderSurfaceView`, Slang shader definitions under `Engine/Sources/AcornEngine/Renderer/Shaders/`, Signed Distance Fields, Camera, or UI systems), agents must verify compilation and GPU execution on Metal 4 (`Apple7+` / iOS 26+ / macOS 26+ ARM64 physical hardware; iOS Simulator is unsupported by `NoGraphicsAPI`):
1. **Recompile Shaders & Run Headless GPU Tests (macOS 26+)**: Run `./Engine/Scripts/compile_shaders.sh` to update `.metallib` artifacts, then run `swift test` to execute headless `NoGraphicsRenderer` GPU verification tests across all pipelines.
2. **Identify Connected Physical iOS 26+ Device**: Run `xcrun devicectl list devices` (or `xcrun xctrace list devices`) to check for a connected, unlocked physical Apple Silicon iOS device running iOS 26+ (`MTLGPUFamilyApple7` + `MTLGPUFamilyMetal4`).
3. **Build the Sample App for Device**: Compile using `xcodebuild -project Samples/AcornSampleApp/AcornSampleApp.xcodeproj -scheme AcornSampleApp -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build_output build`.
4. **Install on Physical Device**: Install the built `.app` bundle via `xcrun devicectl device install app --device <device-id> build_output/Build/Products/Debug-iphoneos/AcornSampleApp.app`.
5. **Launch & Inspect on Physical Device**: Start the app with `xcrun devicectl device process launch --device <device-id> im.teemu.AcornSampleApp` (optionally `--console`), capture or collect the on-device visual verification screenshot/logs when a device is attached, and verify rendering, alignment, colors, and clean frame presentation.
6. **Iterative Feedback Loop**: If shader compilation, device tests, or on-device inspection reveal issues, update the shader/renderer/sample code, recompile shaders, and repeat steps 1-5 until verified cleanly (clean up temporary `build_output` directories afterward).
7. **Document in Walkthrough**: Embed any captured screenshots or explicitly report the exact commands/device coverage in the final report.

---

## 8. macOS Editor Visual Verification Workflow
For any macOS Editor-related visual or GUI changes:
1. Build and run the editor in the background: `swift run --package-path Editor AcornEditor &`
2. Wait at least 3 seconds for the window to boot.
3. Capture a screenshot of the main screen: `screencapture <absolute-path-to-artifacts>/editor_screenshot.png`
4. Inspect the screenshot using the `view_file` tool to verify layout, rendering, and wireframe visualization.
5. Terminate the editor process by running `killall AcornEditor`.
6. Embed the final verified screenshot in the `walkthrough.md` report.
