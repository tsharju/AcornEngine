import Foundation
import simd

/// Represents standard physical or virtual gamepad buttons.
public enum GamepadButton: String, Sendable, CaseIterable, Hashable {
    /// Action button A (Cross on PlayStation, B on Nintendo).
    case buttonA
    /// Action button B (Circle on PlayStation, A on Nintendo).
    case buttonB
    /// Action button X (Square on PlayStation, Y on Nintendo).
    case buttonX
    /// Action button Y (Triangle on PlayStation, X on Nintendo).
    case buttonY
    
    /// Left bumper / shoulder button (L1).
    case leftShoulder
    /// Right bumper / shoulder button (R1).
    case rightShoulder
    
    /// Left analog trigger (L2).
    case leftTrigger
    /// Right analog trigger (R2).
    case rightTrigger
    
    /// Left thumbstick click (L3).
    case leftThumbstickButton
    /// Right thumbstick click (R3).
    case rightThumbstickButton
    
    /// Directional Pad Up.
    case dpadUp
    /// Directional Pad Down.
    case dpadDown
    /// Directional Pad Left.
    case dpadLeft
    /// Directional Pad Right.
    case dpadRight
    
    /// Menu / Start / Options button.
    case menu
    /// Options / Back / Select / Share button.
    case options
    /// Home / System / Guide button.
    case home
}

/// Represents analog axes on a gamepad.
public enum GamepadAxis: String, Sendable, CaseIterable, Hashable {
    case leftThumbstick
    case rightThumbstick
    case dpad
}

/// Represents the instantaneous state of a connected gamepad / game controller.
public struct GamepadState: Sendable, Identifiable {
    /// Unique controller identifier / player index.
    public let id: Int
    
    /// The vendor or descriptive name of the controller (e.g. "Xbox Wireless Controller", "DualSense").
    public var name: String
    
    /// Indicates whether the controller is currently connected.
    public var isConnected: Bool
    
    /// Left thumbstick 2D vector in range `[-1.0, 1.0]`.
    public var leftThumbstick: SIMD2<Float>
    
    /// Right thumbstick 2D vector in range `[-1.0, 1.0]`.
    public var rightThumbstick: SIMD2<Float>
    
    /// Directional pad 2D vector in range `[-1.0, 1.0]`.
    public var dpad: SIMD2<Float>
    
    /// Left trigger analog pressure value in range `[0.0, 1.0]`.
    public var leftTrigger: Float
    
    /// Right trigger analog pressure value in range `[0.0, 1.0]`.
    public var rightTrigger: Float
    
    /// Button analog or digital values in range `[0.0, 1.0]`.
    public var buttonValues: [GamepadButton: Float]
    
    /// Buttons that transitioned from unpressed to pressed during the current frame.
    public var buttonsPressedThisFrame: Set<GamepadButton>
    
    /// Buttons that transitioned from pressed to unpressed during the current frame.
    public var buttonsReleasedThisFrame: Set<GamepadButton>
    
    /// Initializes a new gamepad state with default values.
    /// - Parameters:
    ///   - id: Unique identifier.
    ///   - name: Descriptive device name.
    ///   - isConnected: Connection status.
    public init(
        id: Int,
        name: String = "Gamepad",
        isConnected: Bool = true
    ) {
        self.id = id
        self.name = name
        self.isConnected = isConnected
        self.leftThumbstick = .zero
        self.rightThumbstick = .zero
        self.dpad = .zero
        self.leftTrigger = 0.0
        self.rightTrigger = 0.0
        self.buttonValues = [:]
        self.buttonsPressedThisFrame = []
        self.buttonsReleasedThisFrame = []
    }
    
    /// Returns whether the specified button is currently held down.
    /// - Parameter button: The gamepad button to query.
    /// - Returns: `true` if pressed, otherwise `false`.
    public func isButtonDown(_ button: GamepadButton) -> Bool {
        return (buttonValues[button] ?? 0.0) >= 0.5
    }
    
    /// Returns whether the specified button was pressed during this frame.
    /// - Parameter button: The gamepad button to query.
    /// - Returns: `true` if pressed this frame, otherwise `false`.
    public func isButtonPressed(_ button: GamepadButton) -> Bool {
        return buttonsPressedThisFrame.contains(button)
    }
    
    /// Returns whether the specified button was released during this frame.
    /// - Parameter button: The gamepad button to query.
    /// - Returns: `true` if released this frame, otherwise `false`.
    public func isButtonReleased(_ button: GamepadButton) -> Bool {
        return buttonsReleasedThisFrame.contains(button)
    }
    
    /// Retrieves the analog value of the specified button (0.0 to 1.0).
    /// - Parameter button: The button to query.
    /// - Returns: Analog pressure value between 0.0 and 1.0.
    public func buttonValue(_ button: GamepadButton) -> Float {
        return buttonValues[button] ?? 0.0
    }
    
    /// Clears single-frame transition sets.
    public mutating func advanceFrame() {
        buttonsPressedThisFrame.removeAll(keepingCapacity: true)
        buttonsReleasedThisFrame.removeAll(keepingCapacity: true)
    }
}
