import Foundation
import simd
#if canImport(GameController)
import GameController
#endif

/// Bridges Apple's `GameController` framework into AcornEngine's unified input system.
@MainActor
public final class GameControllerBridge {
    private var notificationTasks: [Task<Void, Never>] = []
    private var controllerIdMap: [ObjectIdentifier: Int] = [:]
    private var nextControllerId: Int = 0

    public init() {
        setupNotifications()
    }
    
    deinit {
        for task in notificationTasks {
            task.cancel()
        }
    }
    
    private func setupNotifications() {
        #if canImport(GameController)
        let connectTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .GCControllerDidConnect) {
                guard !Task.isCancelled, let self = self else { break }
                guard let controller = notification.object as? GCController else { continue }
                self.handleControllerConnected(controller)
            }
        }
        
        let disconnectTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .GCControllerDidDisconnect) {
                guard !Task.isCancelled, let self = self else { break }
                guard let controller = notification.object as? GCController else { continue }
                self.handleControllerDisconnected(controller)
            }
        }
        
        notificationTasks = [connectTask, disconnectTask]
        
        // Register any already connected controllers
        for controller in GCController.controllers() {
            handleControllerConnected(controller)
        }
        #endif
    }
    
    #if canImport(GameController)
    private func handleControllerConnected(_ controller: GCController) {
        let objId = ObjectIdentifier(controller)
        let id: Int
        if let existingId = controllerIdMap[objId] {
            id = existingId
        } else {
            id = nextControllerId
            nextControllerId += 1
            controllerIdMap[objId] = id
        }
        
        controller.playerIndex = GCControllerPlayerIndex(rawValue: id) ?? .indexUnset
    }
    
    private func handleControllerDisconnected(_ controller: GCController) {
        let objId = ObjectIdentifier(controller)
        _ = controllerIdMap[objId]
    }
    #endif
    
    /// Polls connected gamepads and updates the input state and event bus.
    /// - Parameters:
    ///   - inputState: The input state to update.
    ///   - eventBus: The event bus to publish events to.
    public func pollControllers(inputState: InputState, eventBus: EventBus) {
        #if canImport(GameController)
        let controllers = GCController.controllers()
        
        for controller in controllers {
            let objId = ObjectIdentifier(controller)
            guard let controllerId = controllerIdMap[objId] else {
                handleControllerConnected(controller)
                continue
            }
            
            var state = inputState.gamepad(id: controllerId) ?? GamepadState(
                id: controllerId,
                name: controller.vendorName ?? "Game Controller",
                isConnected: true
            )
            
            state.isConnected = true
            state.name = controller.vendorName ?? "Game Controller"
            
            if let extended = controller.extendedGamepad {
                pollExtendedGamepad(extended, controllerId: controllerId, state: &state, eventBus: eventBus)
            } else if let micro = controller.microGamepad {
                pollMicroGamepad(micro, controllerId: controllerId, state: &state, eventBus: eventBus)
            }
            
            inputState.updateGamepad(state)
        }
        #endif
    }
    
    #if canImport(GameController)
    private func pollExtendedGamepad(
        _ gamepad: GCExtendedGamepad,
        controllerId: Int,
        state: inout GamepadState,
        eventBus: EventBus
    ) {
        // Thumbsticks
        let leftStick = SIMD2<Float>(Float(gamepad.leftThumbstick.xAxis.value), Float(gamepad.leftThumbstick.yAxis.value))
        let rightStick = SIMD2<Float>(Float(gamepad.rightThumbstick.xAxis.value), Float(gamepad.rightThumbstick.yAxis.value))
        let dpadVec = SIMD2<Float>(Float(gamepad.dpad.xAxis.value), Float(gamepad.dpad.yAxis.value))
        
        if leftStick != state.leftThumbstick {
            state.leftThumbstick = leftStick
            eventBus.publish(GamepadAxisEvent(gamepadId: controllerId, axis: .leftThumbstick, value: leftStick))
        }
        
        if rightStick != state.rightThumbstick {
            state.rightThumbstick = rightStick
            eventBus.publish(GamepadAxisEvent(gamepadId: controllerId, axis: .rightThumbstick, value: rightStick))
        }
        
        if dpadVec != state.dpad {
            state.dpad = dpadVec
            eventBus.publish(GamepadAxisEvent(gamepadId: controllerId, axis: .dpad, value: dpadVec))
        }
        
        // Triggers
        state.leftTrigger = Float(gamepad.leftTrigger.value)
        state.rightTrigger = Float(gamepad.rightTrigger.value)
        
        // Standard Buttons
        updateButton(gamepad.buttonA, button: .buttonA, controllerId: controllerId, state: &state, eventBus: eventBus)
        updateButton(gamepad.buttonB, button: .buttonB, controllerId: controllerId, state: &state, eventBus: eventBus)
        updateButton(gamepad.buttonX, button: .buttonX, controllerId: controllerId, state: &state, eventBus: eventBus)
        updateButton(gamepad.buttonY, button: .buttonY, controllerId: controllerId, state: &state, eventBus: eventBus)
        
        // Shoulders & Triggers
        updateButton(gamepad.leftShoulder, button: .leftShoulder, controllerId: controllerId, state: &state, eventBus: eventBus)
        updateButton(gamepad.rightShoulder, button: .rightShoulder, controllerId: controllerId, state: &state, eventBus: eventBus)
        updateButton(gamepad.leftTrigger, button: .leftTrigger, controllerId: controllerId, state: &state, eventBus: eventBus)
        updateButton(gamepad.rightTrigger, button: .rightTrigger, controllerId: controllerId, state: &state, eventBus: eventBus)
        
        // Thumbstick buttons (if available)
        if let l3 = gamepad.leftThumbstickButton {
            updateButton(l3, button: .leftThumbstickButton, controllerId: controllerId, state: &state, eventBus: eventBus)
        }
        if let r3 = gamepad.rightThumbstickButton {
            updateButton(r3, button: .rightThumbstickButton, controllerId: controllerId, state: &state, eventBus: eventBus)
        }
        
        // D-Pad buttons
        updateButton(gamepad.dpad.up, button: .dpadUp, controllerId: controllerId, state: &state, eventBus: eventBus)
        updateButton(gamepad.dpad.down, button: .dpadDown, controllerId: controllerId, state: &state, eventBus: eventBus)
        updateButton(gamepad.dpad.left, button: .dpadLeft, controllerId: controllerId, state: &state, eventBus: eventBus)
        updateButton(gamepad.dpad.right, button: .dpadRight, controllerId: controllerId, state: &state, eventBus: eventBus)
        
        // Menu / Options / Home
        updateButton(gamepad.buttonMenu, button: .menu, controllerId: controllerId, state: &state, eventBus: eventBus)
        if let options = gamepad.buttonOptions {
            updateButton(options, button: .options, controllerId: controllerId, state: &state, eventBus: eventBus)
        }
        if let home = gamepad.buttonHome {
            updateButton(home, button: .home, controllerId: controllerId, state: &state, eventBus: eventBus)
        }
    }
    
    private func pollMicroGamepad(
        _ gamepad: GCMicroGamepad,
        controllerId: Int,
        state: inout GamepadState,
        eventBus: EventBus
    ) {
        let dpadVec = SIMD2<Float>(Float(gamepad.dpad.xAxis.value), Float(gamepad.dpad.yAxis.value))
        if dpadVec != state.dpad {
            state.dpad = dpadVec
            eventBus.publish(GamepadAxisEvent(gamepadId: controllerId, axis: .dpad, value: dpadVec))
        }
        
        updateButton(gamepad.buttonA, button: .buttonA, controllerId: controllerId, state: &state, eventBus: eventBus)
        updateButton(gamepad.buttonX, button: .buttonX, controllerId: controllerId, state: &state, eventBus: eventBus)
        updateButton(gamepad.buttonMenu, button: .menu, controllerId: controllerId, state: &state, eventBus: eventBus)
    }
    
    private func updateButton(
        _ gcButton: GCControllerButtonInput,
        button: GamepadButton,
        controllerId: Int,
        state: inout GamepadState,
        eventBus: EventBus
    ) {
        let newValue = Float(gcButton.value)
        let isPressed = gcButton.isPressed
        let previousValue = state.buttonValues[button] ?? 0.0
        let wasPressed = previousValue >= 0.5
        
        state.buttonValues[button] = newValue
        
        if isPressed && !wasPressed {
            state.buttonsPressedThisFrame.insert(button)
            eventBus.publish(GamepadButtonEvent(gamepadId: controllerId, button: button, isPressed: true, value: newValue))
        } else if !isPressed && wasPressed {
            state.buttonsReleasedThisFrame.insert(button)
            eventBus.publish(GamepadButtonEvent(gamepadId: controllerId, button: button, isPressed: false, value: newValue))
        }
    }
    #endif
}
