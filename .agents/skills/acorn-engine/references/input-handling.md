# AcornEngine Unified Input Guide

AcornEngine provides a unified input abstraction spanning keyboard, mouse/pointer, multi-touch screens, and hardware game controllers (MFi, Xbox, and PlayStation).

---

## 1. Input Architecture

- **`InputSystem`**: The primary ECS system polling connected hardware and forwarding OS events. Created and registered automatically by `Engine`.
- **`InputState`**: Represents the current continuous state (down keys, mouse position, active touches, gamepads).
- **`EventBus`**: Dispatches discrete transitional events (`KeyDownEvent`, `TouchBeganEvent`, etc.).

```swift
// Access the continuous input state directly:
let input = engine.inputSystem.state
```

---

## 2. Polling Continuous Input

Systems typically poll `InputState` inside `update(world:deltaTime:)`:

### 1. Keyboard
```swift
// Is key currently held down?
if input.isKeyDown(.w) || input.isKeyDown(.upArrow) {
    moveDirection.y += 1.0
}

// Was key pressed this exact frame?
if input.wasKeyPressedThisFrame(.space) {
    jump()
}

// Was key released this frame?
if input.wasKeyReleasedThisFrame(.leftShift) {
    stopSprinting()
}
```

### 2. Mouse & Trackpad
```swift
// Cursor coordinates in screen space
let mousePos: SIMD2<Float> = input.mousePosition

// Relative frame-to-frame movement delta
let delta: SIMD2<Float> = input.mouseDelta

// Scroll wheel delta
let scroll: SIMD2<Float> = input.scrollDelta

// Mouse buttons (.left, .right, .middle, .other(Int))
if input.isMouseButtonDown(.left) {
    fireWeapon()
}
if input.wasMouseButtonPressedThisFrame(.right) {
    openContextMenu()
}
```

### 3. Multi-Touch Gestures
```swift
for touch in input.touches.values {
    print("Touch ID \(touch.id) at \(touch.position), phase: \(touch.phase)")
}
```

### 4. Game Controllers (Gamepads)
Polled seamlessly via Apple's `GameController` framework bridge:
```swift
if let gamepad = input.gamepads.values.first {
    // Analog thumbsticks (values clamped [-1.0 ... 1.0])
    let moveStick = gamepad.leftThumbstick
    let lookStick = gamepad.rightThumbstick

    // Buttons
    if gamepad.isButtonDown(.buttonA) {
        jump()
    }
    if gamepad.wasButtonPressed(.buttonX) {
        reload()
    }

    // Analog Triggers [0.0 ... 1.0]
    let gas = gamepad.rightTrigger
    let brake = gamepad.leftTrigger
}
```

---

## 3. Event-Driven Input Handling

If you prefer event-driven architecture, subscribe to input events on the `EventBus`:

```swift
// Keyboard key press
world.eventBus.subscribe(KeyDownEvent.self) { event in
    if event.key == .escape {
        pauseMenu.toggle()
    }
}

// Mouse click
world.eventBus.subscribe(MouseDownEvent.self) { event in
    if event.button == .left {
        handleTap(at: event.position)
    }
}

// Touch phase begin
world.eventBus.subscribe(TouchBeganEvent.self) { event in
    startDrag(id: event.touch.id, at: event.touch.position)
}

// Gamepad connection
world.eventBus.subscribe(GamepadConnectedEvent.self) { event in
    print("Connected gamepad: \(event.gamepad.name)")
}
```

---

## 4. Forwarding Native UIKit / AppKit Events

If you are writing a custom View Controller or window delegate, forward incoming native events into `InputSystem`:

```swift
// Example: In a custom iOS UIViewController
override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches {
        let loc = touch.location(in: view)
        let pos = SIMD2<Float>(Float(loc.x), Float(loc.y))
        engine.inputSystem.touchBegan(id: UInt64(touch.hash), position: pos)
    }
}

override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches {
        let loc = touch.location(in: view)
        let pos = SIMD2<Float>(Float(loc.x), Float(loc.y))
        engine.inputSystem.touchEnded(id: UInt64(touch.hash), position: pos)
    }
}
```
