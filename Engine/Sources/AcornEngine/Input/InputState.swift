import Foundation
import simd

/// Maintains the comprehensive, queryable input state across keyboard, mouse, touch, and gamepads.
@MainActor
public final class InputState {
    // MARK: - Keyboard State
    private var heldKeys: Set<Key> = []
    private var keysPressedThisFrame: Set<Key> = []
    private var keysReleasedThisFrame: Set<Key> = []
    public private(set) var modifiers: KeyModifierFlags = []
    
    // MARK: - Mouse State
    public private(set) var mousePosition: SIMD2<Float> = .zero
    public private(set) var mouseDelta: SIMD2<Float> = .zero
    public private(set) var scrollDelta: SIMD2<Float> = .zero
    private var heldMouseButtons: Set<MouseButton> = []
    private var mouseButtonsPressedThisFrame: Set<MouseButton> = []
    private var mouseButtonsReleasedThisFrame: Set<MouseButton> = []
    
    // MARK: - Touch State
    private var activeTouches: [Int: Touch] = [:]
    
    // MARK: - Gamepad State
    private var gamepadStates: [Int: GamepadState] = [:]
    
    public init() {}
    
    // MARK: - Keyboard Queries
    
    /// Returns whether the specified key is currently held down.
    public func isKeyDown(_ key: Key) -> Bool {
        return heldKeys.contains(key)
    }
    
    /// Returns whether the specified key was pressed during the current frame.
    public func isKeyPressed(_ key: Key) -> Bool {
        return keysPressedThisFrame.contains(key)
    }
    
    /// Returns whether the specified key was released during the current frame.
    public func isKeyReleased(_ key: Key) -> Bool {
        return keysReleasedThisFrame.contains(key)
    }
    
    /// All keys currently held down.
    public var currentHeldKeys: Set<Key> {
        return heldKeys
    }
    
    // MARK: - Mouse Queries
    
    /// Returns whether the specified mouse button is currently held down.
    public func isMouseButtonDown(_ button: MouseButton) -> Bool {
        return heldMouseButtons.contains(button)
    }
    
    /// Returns whether the specified mouse button was clicked during the current frame.
    public func isMouseButtonPressed(_ button: MouseButton) -> Bool {
        return mouseButtonsPressedThisFrame.contains(button)
    }
    
    /// Returns whether the specified mouse button was released during the current frame.
    public func isMouseButtonReleased(_ button: MouseButton) -> Bool {
        return mouseButtonsReleasedThisFrame.contains(button)
    }
    
    // MARK: - Touch Queries
    
    /// All currently active touch points on screen.
    public var touches: [Touch] {
        return Array(activeTouches.values)
    }
    
    /// Returns the active touch with the specified identifier, if present.
    public func touch(id: Int) -> Touch? {
        return activeTouches[id]
    }
    
    /// Returns whether there are any active touch contacts on the screen.
    public var hasActiveTouches: Bool {
        return !activeTouches.isEmpty
    }
    
    // MARK: - Gamepad Queries
    
    /// All currently tracked gamepad states.
    public var gamepads: [GamepadState] {
        return Array(gamepadStates.values.filter { $0.isConnected })
    }
    
    /// Retrieves the gamepad state for a specific controller identifier.
    public func gamepad(id: Int) -> GamepadState? {
        return gamepadStates[id]
    }
    
    /// Retrieves the primary (first connected) gamepad, if any.
    public var primaryGamepad: GamepadState? {
        return gamepads.sorted(by: { $0.id < $1.id }).first
    }
    
    // MARK: - State Mutators (Internal/Engine Facing)
    
    public func recordKeyDown(_ key: Key, modifiers: KeyModifierFlags) {
        self.modifiers = modifiers
        if !heldKeys.contains(key) {
            keysPressedThisFrame.insert(key)
        }
        heldKeys.insert(key)
    }
    
    public func recordKeyUp(_ key: Key, modifiers: KeyModifierFlags) {
        self.modifiers = modifiers
        heldKeys.remove(key)
        keysReleasedThisFrame.insert(key)
    }
    
    public func recordMouseDown(_ button: MouseButton, at position: SIMD2<Float>) {
        self.mousePosition = position
        if !heldMouseButtons.contains(button) {
            mouseButtonsPressedThisFrame.insert(button)
        }
        heldMouseButtons.insert(button)
    }
    
    public func recordMouseUp(_ button: MouseButton, at position: SIMD2<Float>) {
        self.mousePosition = position
        heldMouseButtons.remove(button)
        mouseButtonsReleasedThisFrame.insert(button)
    }
    
    public func recordMouseMove(to position: SIMD2<Float>, delta: SIMD2<Float>) {
        self.mousePosition = position
        self.mouseDelta += delta
    }
    
    public func recordMouseScroll(delta: SIMD2<Float>) {
        self.scrollDelta += delta
    }
    
    public func recordTouchBegan(_ touch: Touch) {
        activeTouches[touch.id] = touch
    }
    
    public func recordTouchMoved(_ touch: Touch) {
        activeTouches[touch.id] = touch
    }
    
    public func recordTouchEnded(_ touch: Touch) {
        activeTouches[touch.id] = touch
    }
    
    public func recordTouchCancelled(_ touch: Touch) {
        activeTouches[touch.id] = touch
    }
    
    public func updateGamepad(_ state: GamepadState) {
        gamepadStates[state.id] = state
    }
    
    public func removeGamepad(id: Int) {
        gamepadStates[id]?.isConnected = false
    }
    
    // MARK: - Frame Advancement
    
    /// Clears per-frame transient input delta and transition sets.
    public func advanceFrame() {
        keysPressedThisFrame.removeAll(keepingCapacity: true)
        keysReleasedThisFrame.removeAll(keepingCapacity: true)
        
        mouseButtonsPressedThisFrame.removeAll(keepingCapacity: true)
        mouseButtonsReleasedThisFrame.removeAll(keepingCapacity: true)
        mouseDelta = .zero
        scrollDelta = .zero
        
        // Remove ended/cancelled touches
        activeTouches = activeTouches.filter { _, touch in
            touch.phase != .ended && touch.phase != .cancelled
        }
        
        // Advance gamepad frames
        for id in gamepadStates.keys {
            gamepadStates[id]?.advanceFrame()
        }
    }
    
    /// Resets all input states back to idle.
    public func reset() {
        heldKeys.removeAll()
        keysPressedThisFrame.removeAll()
        keysReleasedThisFrame.removeAll()
        modifiers = []
        
        mousePosition = .zero
        mouseDelta = .zero
        scrollDelta = .zero
        heldMouseButtons.removeAll()
        mouseButtonsPressedThisFrame.removeAll()
        mouseButtonsReleasedThisFrame.removeAll()
        
        activeTouches.removeAll()
        gamepadStates.removeAll()
    }
}
