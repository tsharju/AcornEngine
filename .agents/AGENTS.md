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

