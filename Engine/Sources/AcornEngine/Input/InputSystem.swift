import Foundation
import simd

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

/// A system that manages input state across keyboard, mouse, touch pointers, and game controllers.
@MainActor
public final class InputSystem: System {
    /// The consolidated input state.
    public let state: InputState
    
    /// The bridge communicating with Apple's GameController framework.
    public let gameControllerBridge: GameControllerBridge
    
    /// Initializes a new InputSystem.
    /// - Parameters:
    ///   - state: The input state backing store.
    ///   - gameControllerBridge: The GameController bridge.
    public init(
        state: InputState = InputState(),
        gameControllerBridge: GameControllerBridge = GameControllerBridge()
    ) {
        self.state = state
        self.gameControllerBridge = gameControllerBridge
    }
    
    /// Updates the system, polling hardware gamepads and preparing state transitions.
    /// - Parameters:
    ///   - world: The ECS world.
    ///   - deltaTime: Delta time for the current frame.
    public func update(world: World, deltaTime: Double) {
        // Poll connected hardware gamepads
        gameControllerBridge.pollControllers(inputState: state, eventBus: world.eventBus)
    }
    
    /// Clears per-frame transient input delta and transition sets.
    /// Typically called by `World` or `Engine` at the end of a tick.
    public func advanceFrame() {
        state.advanceFrame()
    }
    
    // MARK: - Keyboard Input Processing
    
    /// Processes a key down event.
    /// - Parameters:
    ///   - key: The key that was pressed.
    ///   - modifiers: Active modifier flags.
    ///   - isRepeat: Whether this is an auto-repeat keystroke.
    ///   - eventBus: The event bus to publish to.
    public func processKeyDown(
        _ key: Key,
        modifiers: KeyModifierFlags = [],
        isRepeat: Bool = false,
        eventBus: EventBus? = nil
    ) {
        state.recordKeyDown(key, modifiers: modifiers)
        eventBus?.publish(KeyDownEvent(key: key, modifiers: modifiers, isRepeat: isRepeat))
    }
    
    /// Processes a key up event.
    /// - Parameters:
    ///   - key: The key that was released.
    ///   - modifiers: Active modifier flags.
    ///   - eventBus: The event bus to publish to.
    public func processKeyUp(
        _ key: Key,
        modifiers: KeyModifierFlags = [],
        eventBus: EventBus? = nil
    ) {
        state.recordKeyUp(key, modifiers: modifiers)
        eventBus?.publish(KeyUpEvent(key: key, modifiers: modifiers))
    }
    
    // MARK: - Mouse Input Processing
    
    /// Processes a mouse button press.
    /// - Parameters:
    ///   - button: The mouse button pressed.
    ///   - position: Mouse position in screen coordinates.
    ///   - eventBus: The event bus to publish to.
    public func processMouseDown(
        _ button: MouseButton,
        at position: SIMD2<Float>,
        eventBus: EventBus? = nil
    ) {
        state.recordMouseDown(button, at: position)
        eventBus?.publish(MouseDownEvent(button: button, position: position))
    }
    
    /// Processes a mouse button release.
    /// - Parameters:
    ///   - button: The mouse button released.
    ///   - position: Mouse position in screen coordinates.
    ///   - eventBus: The event bus to publish to.
    public func processMouseUp(
        _ button: MouseButton,
        at position: SIMD2<Float>,
        eventBus: EventBus? = nil
    ) {
        state.recordMouseUp(button, at: position)
        eventBus?.publish(MouseUpEvent(button: button, position: position))
    }
    
    /// Processes mouse movement.
    /// - Parameters:
    ///   - position: Absolute mouse position in screen coordinates.
    ///   - delta: Relative movement delta since last event.
    ///   - eventBus: The event bus to publish to.
    public func processMouseMove(
        to position: SIMD2<Float>,
        delta: SIMD2<Float>,
        eventBus: EventBus? = nil
    ) {
        state.recordMouseMove(to: position, delta: delta)
        eventBus?.publish(MouseMoveEvent(position: position, delta: delta))
    }
    
    /// Processes mouse or trackpad scroll wheel delta.
    /// - Parameters:
    ///   - delta: Scroll delta (X: horizontal, Y: vertical).
    ///   - eventBus: The event bus to publish to.
    public func processMouseScroll(
        delta: SIMD2<Float>,
        eventBus: EventBus? = nil
    ) {
        state.recordMouseScroll(delta: delta)
        eventBus?.publish(MouseScrollEvent(delta: delta))
    }
    
    // MARK: - Touch Input Processing
    
    /// Processes the start of a touch point contact.
    /// - Parameters:
    ///   - id: Unique touch pointer ID.
    ///   - position: Touch position in screen coordinates.
    ///   - tapCount: Number of consecutive taps.
    ///   - eventBus: The event bus to publish to.
    public func processTouchBegan(
        id: Int,
        position: SIMD2<Float>,
        tapCount: Int = 1,
        eventBus: EventBus? = nil
    ) {
        let touch = Touch(id: id, position: position, delta: .zero, phase: .began, tapCount: tapCount)
        state.recordTouchBegan(touch)
        eventBus?.publish(TouchBeganEvent(touch: touch))
    }
    
    /// Processes movement of an existing touch point.
    /// - Parameters:
    ///   - id: Unique touch pointer ID.
    ///   - position: New touch position in screen coordinates.
    ///   - delta: Movement delta since previous touch event.
    ///   - eventBus: The event bus to publish to.
    public func processTouchMoved(
        id: Int,
        position: SIMD2<Float>,
        delta: SIMD2<Float>,
        eventBus: EventBus? = nil
    ) {
        let tapCount = state.touch(id: id)?.tapCount ?? 1
        let touch = Touch(id: id, position: position, delta: delta, phase: .moved, tapCount: tapCount)
        state.recordTouchMoved(touch)
        eventBus?.publish(TouchMovedEvent(touch: touch))
    }
    
    /// Processes completion of a touch point contact.
    /// - Parameters:
    ///   - id: Unique touch pointer ID.
    ///   - position: Final touch position in screen coordinates.
    ///   - eventBus: The event bus to publish to.
    public func processTouchEnded(
        id: Int,
        position: SIMD2<Float>,
        eventBus: EventBus? = nil
    ) {
        let tapCount = state.touch(id: id)?.tapCount ?? 1
        let touch = Touch(id: id, position: position, delta: .zero, phase: .ended, tapCount: tapCount)
        state.recordTouchEnded(touch)
        eventBus?.publish(TouchEndedEvent(touch: touch))
    }
    
    /// Processes cancellation of a touch point.
    /// - Parameters:
    ///   - id: Unique touch pointer ID.
    ///   - eventBus: The event bus to publish to.
    public func processTouchCancelled(
        id: Int,
        eventBus: EventBus? = nil
    ) {
        guard let existing = state.touch(id: id) else { return }
        var touch = existing
        touch.phase = .cancelled
        state.recordTouchCancelled(touch)
        eventBus?.publish(TouchCancelledEvent(touch: touch))
    }
    
    // MARK: - Gamepad Synthetic / Custom Input Processing
    
    /// Registers or updates a gamepad connection.
    /// - Parameters:
    ///   - id: Unique gamepad identifier.
    ///   - name: Descriptive controller name.
    ///   - eventBus: The event bus to publish to.
    public func processGamepadConnected(
        id: Int,
        name: String = "Gamepad",
        eventBus: EventBus? = nil
    ) {
        var gamepad = state.gamepad(id: id) ?? GamepadState(id: id, name: name, isConnected: true)
        gamepad.isConnected = true
        gamepad.name = name
        state.updateGamepad(gamepad)
        eventBus?.publish(GamepadConnectedEvent(gamepadId: id, name: name))
    }
    
    /// Registers a gamepad disconnection.
    /// - Parameters:
    ///   - id: Unique gamepad identifier.
    ///   - eventBus: The event bus to publish to.
    public func processGamepadDisconnected(
        id: Int,
        eventBus: EventBus? = nil
    ) {
        state.removeGamepad(id: id)
        eventBus?.publish(GamepadDisconnectedEvent(gamepadId: id))
    }
    
    /// Updates a gamepad button state.
    /// - Parameters:
    ///   - id: Unique gamepad identifier.
    ///   - button: Gamepad button.
    ///   - isPressed: Button state.
    ///   - value: Analog pressure value in `[0.0, 1.0]`.
    ///   - eventBus: The event bus to publish to.
    public func processGamepadButton(
        id: Int,
        button: GamepadButton,
        isPressed: Bool,
        value: Float = 1.0,
        eventBus: EventBus? = nil
    ) {
        var gamepad = state.gamepad(id: id) ?? GamepadState(id: id)
        let previousValue = gamepad.buttonValues[button] ?? 0.0
        let wasPressed = previousValue >= 0.5
        
        let pressure = isPressed ? max(value, 0.5) : 0.0
        gamepad.buttonValues[button] = pressure
        
        if isPressed && !wasPressed {
            gamepad.buttonsPressedThisFrame.insert(button)
            eventBus?.publish(GamepadButtonEvent(gamepadId: id, button: button, isPressed: true, value: pressure))
        } else if !isPressed && wasPressed {
            gamepad.buttonsReleasedThisFrame.insert(button)
            eventBus?.publish(GamepadButtonEvent(gamepadId: id, button: button, isPressed: false, value: 0.0))
        }
        
        state.updateGamepad(gamepad)
    }
    
    /// Updates a gamepad analog axis value.
    /// - Parameters:
    ///   - id: Unique gamepad identifier.
    ///   - axis: The axis (leftThumbstick, rightThumbstick, dpad).
    ///   - value: 2D vector in `[-1.0, 1.0]`.
    ///   - eventBus: The event bus to publish to.
    public func processGamepadAxis(
        id: Int,
        axis: GamepadAxis,
        value: SIMD2<Float>,
        eventBus: EventBus? = nil
    ) {
        var gamepad = state.gamepad(id: id) ?? GamepadState(id: id)
        switch axis {
        case .leftThumbstick:
            gamepad.leftThumbstick = value
        case .rightThumbstick:
            gamepad.rightThumbstick = value
        case .dpad:
            gamepad.dpad = value
        }
        state.updateGamepad(gamepad)
        eventBus?.publish(GamepadAxisEvent(gamepadId: id, axis: axis, value: value))
    }
}
