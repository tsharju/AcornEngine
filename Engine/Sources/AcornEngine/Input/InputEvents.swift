import Foundation
import simd

// MARK: - Keyboard Events

/// Event published when a keyboard key is pressed.
public struct KeyDownEvent: Event {
    public let key: Key
    public let modifiers: KeyModifierFlags
    public let isRepeat: Bool
    
    public init(key: Key, modifiers: KeyModifierFlags = [], isRepeat: Bool = false) {
        self.key = key
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }
}

/// Event published when a keyboard key is released.
public struct KeyUpEvent: Event {
    public let key: Key
    public let modifiers: KeyModifierFlags
    
    public init(key: Key, modifiers: KeyModifierFlags = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

// MARK: - Mouse Events

/// Event published when a mouse button is clicked down.
public struct MouseDownEvent: Event {
    public let button: MouseButton
    public let position: SIMD2<Float>
    
    public init(button: MouseButton, position: SIMD2<Float>) {
        self.button = button
        self.position = position
    }
}

/// Event published when a mouse button is released.
public struct MouseUpEvent: Event {
    public let button: MouseButton
    public let position: SIMD2<Float>
    
    public init(button: MouseButton, position: SIMD2<Float>) {
        self.button = button
        self.position = position
    }
}

/// Event published when the mouse pointer moves.
public struct MouseMoveEvent: Event {
    public let position: SIMD2<Float>
    public let delta: SIMD2<Float>
    
    public init(position: SIMD2<Float>, delta: SIMD2<Float>) {
        self.position = position
        self.delta = delta
    }
}

/// Event published when a mouse wheel / scroll wheel is operated.
public struct MouseScrollEvent: Event {
    public let delta: SIMD2<Float>
    
    public init(delta: SIMD2<Float>) {
        self.delta = delta
    }
}

// MARK: - Touch Events

/// Event published when a touch pointer contacts the screen.
public struct TouchBeganEvent: Event {
    public let touch: Touch
    
    public init(touch: Touch) {
        self.touch = touch
    }
}

/// Event published when an existing touch pointer moves.
public struct TouchMovedEvent: Event {
    public let touch: Touch
    
    public init(touch: Touch) {
        self.touch = touch
    }
}

/// Event published when a touch pointer lifts off the screen.
public struct TouchEndedEvent: Event {
    public let touch: Touch
    
    public init(touch: Touch) {
        self.touch = touch
    }
}

/// Event published when a touch pointer is cancelled by the operating system.
public struct TouchCancelledEvent: Event {
    public let touch: Touch
    
    public init(touch: Touch) {
        self.touch = touch
    }
}

// MARK: - Gamepad Events

/// Event published when a gamepad connects.
public struct GamepadConnectedEvent: Event {
    public let gamepadId: Int
    public let name: String
    
    public init(gamepadId: Int, name: String) {
        self.gamepadId = gamepadId
        self.name = name
    }
}

/// Event published when a gamepad disconnects.
public struct GamepadDisconnectedEvent: Event {
    public let gamepadId: Int
    
    public init(gamepadId: Int) {
        self.gamepadId = gamepadId
    }
}

/// Event published when a gamepad button state changes.
public struct GamepadButtonEvent: Event {
    public let gamepadId: Int
    public let button: GamepadButton
    public let isPressed: Bool
    public let value: Float
    
    public init(gamepadId: Int, button: GamepadButton, isPressed: Bool, value: Float) {
        self.gamepadId = gamepadId
        self.button = button
        self.isPressed = isPressed
        self.value = value
    }
}

/// Event published when a gamepad analog axis moves.
public struct GamepadAxisEvent: Event {
    public let gamepadId: Int
    public let axis: GamepadAxis
    public let value: SIMD2<Float>
    
    public init(gamepadId: Int, axis: GamepadAxis, value: SIMD2<Float>) {
        self.gamepadId = gamepadId
        self.axis = axis
        self.value = value
    }
}
