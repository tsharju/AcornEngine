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
For any visual, rendering, or shader-related changes (e.g., changes to `MetalRenderer`, Signed Distance Fields, Shader definitions, Camera, or UI systems), agents must perform visual verification using the sample app:
1. **Identify and Boot iOS Simulator**: Ensure an iOS simulator matching the app's minimum deployment version (e.g., iOS 26.5 or later) is booted. Use `xcrun simctl list devices booted` to find running simulators, and `xcrun simctl boot <device-id>` to boot one if needed.
2. **Build the Sample App**: Compile the sample app using `xcodebuild -project Samples/AcornSampleApp/AcornSampleApp.xcodeproj -scheme AcornSampleApp -configuration Debug -sdk iphonesimulator -derivedDataPath build_output build`.
3. **Install on Simulator**: Install the built `.app` bundle: `xcrun simctl install <device-id> build_output/Build/Products/Debug-iphonesimulator/AcornSampleApp.app`.
4. **Launch the App**: Start the application: `xcrun simctl launch <device-id> im.teemu.AcornSampleApp`.
5. **Capture Simulator Screenshot**: Take a screenshot: `xcrun simctl io <device-id> screenshot <absolute-path-to-artifacts>/sample_app_screenshot.png`.
6. **Visual Inspection & Verification**: View the screenshot using the `view_file` tool to inspect the rendered output. Verify colors, geometry, alignment, text clarity, and general rendering correctness.
7. **Iterative Feedback Loop**: If the screenshot reveals bugs (e.g. incorrect colors, misaligned layouts, or rendering artifacts), analyze the issue, update the codebase, and repeat steps 2-6 until the rendering is completely correct.
8. **Document in Walkthrough**: Embed the final verified screenshot in the `walkthrough.md` report so the user can easily see the verified visual results.

