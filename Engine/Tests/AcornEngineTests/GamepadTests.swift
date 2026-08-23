import Testing
import simd
@testable import AcornEngine

@Suite("Gamepad Tests")
@MainActor
struct GamepadTests {
    
    @Test("GamepadState initialization and defaults")
    func testGamepadStateDefaults() {
        let gamepad = GamepadState(id: 0, name: "DualSense", isConnected: true)
        
        #expect(gamepad.id == 0)
        #expect(gamepad.name == "DualSense")
        #expect(gamepad.isConnected)
        #expect(gamepad.leftThumbstick == .zero)
        #expect(gamepad.rightThumbstick == .zero)
        #expect(gamepad.leftTrigger == 0.0)
        #expect(gamepad.rightTrigger == 0.0)
        #expect(!gamepad.isButtonDown(.buttonA))
        #expect(!gamepad.isButtonPressed(.buttonA))
        #expect(!gamepad.isButtonReleased(.buttonA))
    }
    
    @Test("Gamepad button transitions and frame lifecycle")
    func testGamepadButtonTransitions() {
        let inputSystem = InputSystem()
        let eventBus = EventBus()
        
        var receivedButtonEvent: (button: GamepadButton, isPressed: Bool)?
        let sub = eventBus.subscribe(GamepadButtonEvent.self) { e in
            receivedButtonEvent = (e.button, e.isPressed)
        }
        
        inputSystem.processGamepadConnected(id: 0, name: "Xbox Controller", eventBus: eventBus)
        
        let primary = inputSystem.state.primaryGamepad
        #expect(primary?.id == 0)
        #expect(primary?.name == "Xbox Controller")
        
        // Frame 1: Press button A
        inputSystem.processGamepadButton(id: 0, button: .buttonA, isPressed: true, value: 1.0, eventBus: eventBus)
        
        var current = inputSystem.state.gamepad(id: 0)
        #expect(current?.isButtonDown(.buttonA) == true)
        #expect(current?.isButtonPressed(.buttonA) == true)
        #expect(current?.isButtonReleased(.buttonA) == false)
        #expect(receivedButtonEvent?.button == .buttonA)
        #expect(receivedButtonEvent?.isPressed == true)
        
        // Advance frame (simulate holding A in next frame)
        inputSystem.advanceFrame()
        
        current = inputSystem.state.gamepad(id: 0)
        #expect(current?.isButtonDown(.buttonA) == true)
        #expect(current?.isButtonPressed(.buttonA) == false)
        #expect(current?.isButtonReleased(.buttonA) == false)
        
        // Release button A
        inputSystem.processGamepadButton(id: 0, button: .buttonA, isPressed: false, value: 0.0, eventBus: eventBus)
        
        current = inputSystem.state.gamepad(id: 0)
        #expect(current?.isButtonDown(.buttonA) == false)
        #expect(current?.isButtonPressed(.buttonA) == false)
        #expect(current?.isButtonReleased(.buttonA) == true)
        #expect(receivedButtonEvent?.isPressed == false)
        
        _ = sub
    }
    
    @Test("Gamepad axis updates and events")
    func testGamepadAxisUpdates() {
        let inputSystem = InputSystem()
        let eventBus = EventBus()
        
        var axisVector: SIMD2<Float>?
        let sub = eventBus.subscribe(GamepadAxisEvent.self) { e in
            if e.axis == .leftThumbstick {
                axisVector = e.value
            }
        }
        
        inputSystem.processGamepadConnected(id: 1, name: "Controller 2", eventBus: eventBus)
        
        let stickInput = SIMD2<Float>(0.75, -0.5)
        inputSystem.processGamepadAxis(id: 1, axis: .leftThumbstick, value: stickInput, eventBus: eventBus)
        
        let gamepad = inputSystem.state.gamepad(id: 1)
        #expect(gamepad?.leftThumbstick == stickInput)
        #expect(axisVector == stickInput)
        
        _ = sub
    }
}
