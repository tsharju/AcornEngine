import Testing
import simd
@testable import AcornEngine

@Suite("InputSystem Tests")
@MainActor
struct InputSystemTests {
    
    @Test("Keyboard press, hold, and release tracking")
    func testKeyboardStateLifecycle() {
        let inputSystem = InputSystem()
        let state = inputSystem.state
        let eventBus = EventBus()
        
        var keyDownReceived: Key?
        var keyUpReceived: Key?
        
        let subDown = eventBus.subscribe(KeyDownEvent.self) { e in
            keyDownReceived = e.key
        }
        let subUp = eventBus.subscribe(KeyUpEvent.self) { e in
            keyUpReceived = e.key
        }
        
        // Initial state
        #expect(!state.isKeyDown(.space))
        #expect(!state.isKeyPressed(.space))
        #expect(!state.isKeyReleased(.space))
        
        // Frame 1: Press space
        inputSystem.processKeyDown(.space, modifiers: [.shift], eventBus: eventBus)
        
        #expect(state.isKeyDown(.space))
        #expect(state.isKeyPressed(.space))
        #expect(!state.isKeyReleased(.space))
        #expect(state.modifiers.contains(.shift))
        #expect(keyDownReceived == .space)
        
        // Advance frame (simulate next frame holding space)
        inputSystem.advanceFrame()
        
        #expect(state.isKeyDown(.space))
        #expect(!state.isKeyPressed(.space))
        #expect(!state.isKeyReleased(.space))
        
        // Frame 3: Release space
        inputSystem.processKeyUp(.space, modifiers: [], eventBus: eventBus)
        
        #expect(!state.isKeyDown(.space))
        #expect(!state.isKeyPressed(.space))
        #expect(state.isKeyReleased(.space))
        #expect(keyUpReceived == .space)
        
        // Frame 4: Next frame after release
        inputSystem.advanceFrame()
        #expect(!state.isKeyDown(.space))
        #expect(!state.isKeyPressed(.space))
        #expect(!state.isKeyReleased(.space))
        
        _ = subDown
        _ = subUp
    }
    
    @Test("macOS KeyCode mapping")
    func testMacOSKeyCodeMapping() {
        #expect(Key.from(macOSKeyCode: 0x31) == .space)
        #expect(Key.from(macOSKeyCode: 0x35) == .escape)
        #expect(Key.from(macOSKeyCode: 0x00) == .a)
        #expect(Key.from(macOSKeyCode: 0x0D) == .w)
        #expect(Key.from(macOSKeyCode: 0x01) == .s)
        #expect(Key.from(macOSKeyCode: 0x02) == .d)
        #expect(Key.from(macOSKeyCode: 0x7E) == .upArrow)
        #expect(Key.from(macOSKeyCode: 0xFFFF) == nil)
    }
    
    @Test("Mouse buttons, movement, and scroll tracking")
    func testMouseTracking() {
        let inputSystem = InputSystem()
        let state = inputSystem.state
        let eventBus = EventBus()
        
        var clickedButton: MouseButton?
        let clickSub = eventBus.subscribe(MouseDownEvent.self) { e in
            clickedButton = e.button
        }
        
        // Move mouse
        inputSystem.processMouseMove(to: SIMD2<Float>(100, 200), delta: SIMD2<Float>(10, 20), eventBus: eventBus)
        #expect(state.mousePosition == SIMD2<Float>(100, 200))
        #expect(state.mouseDelta == SIMD2<Float>(10, 20))
        
        // Scroll wheel
        inputSystem.processMouseScroll(delta: SIMD2<Float>(0, 5), eventBus: eventBus)
        #expect(state.scrollDelta == SIMD2<Float>(0, 5))
        
        // Click Left button
        inputSystem.processMouseDown(.left, at: SIMD2<Float>(100, 200), eventBus: eventBus)
        #expect(state.isMouseButtonDown(.left))
        #expect(state.isMouseButtonPressed(.left))
        #expect(!state.isMouseButtonReleased(.left))
        #expect(clickedButton == .left)
        
        // Advance frame
        inputSystem.advanceFrame()
        
        #expect(state.isMouseButtonDown(.left))
        #expect(!state.isMouseButtonPressed(.left))
        #expect(state.mouseDelta == .zero)
        #expect(state.scrollDelta == .zero)
        
        // Release Left button
        inputSystem.processMouseUp(.left, at: SIMD2<Float>(105, 205), eventBus: eventBus)
        #expect(!state.isMouseButtonDown(.left))
        #expect(state.isMouseButtonReleased(.left))
        
        _ = clickSub
    }
    
    @Test("Multi-touch lifecycle and cleanup")
    func testMultiTouchLifecycle() {
        let inputSystem = InputSystem()
        let state = inputSystem.state
        let eventBus = EventBus()
        
        var beganTouchId: Int?
        var endedTouchId: Int?
        
        let subBegan = eventBus.subscribe(TouchBeganEvent.self) { e in
            beganTouchId = e.touch.id
        }
        let subEnded = eventBus.subscribe(TouchEndedEvent.self) { e in
            endedTouchId = e.touch.id
        }
        
        #expect(!state.hasActiveTouches)
        
        // Touch 1 began
        inputSystem.processTouchBegan(id: 1, position: SIMD2<Float>(50, 50), eventBus: eventBus)
        #expect(state.hasActiveTouches)
        #expect(state.touches.count == 1)
        #expect(state.touch(id: 1)?.position == SIMD2<Float>(50, 50))
        #expect(state.touch(id: 1)?.phase == .began)
        #expect(beganTouchId == 1)
        
        // Touch 2 began (multitouch)
        inputSystem.processTouchBegan(id: 2, position: SIMD2<Float>(150, 150), eventBus: eventBus)
        #expect(state.touches.count == 2)
        
        // Touch 1 moved
        inputSystem.processTouchMoved(id: 1, position: SIMD2<Float>(60, 60), delta: SIMD2<Float>(10, 10), eventBus: eventBus)
        #expect(state.touch(id: 1)?.position == SIMD2<Float>(60, 60))
        #expect(state.touch(id: 1)?.delta == SIMD2<Float>(10, 10))
        #expect(state.touch(id: 1)?.phase == .moved)
        
        // Touch 2 ended
        inputSystem.processTouchEnded(id: 2, position: SIMD2<Float>(150, 150), eventBus: eventBus)
        #expect(state.touch(id: 2)?.phase == .ended)
        #expect(endedTouchId == 2)
        
        // Advance frame removes ended touches
        inputSystem.advanceFrame()
        
        #expect(state.touch(id: 2) == nil)
        #expect(state.touch(id: 1) != nil)
        #expect(state.touches.count == 1)
        
        _ = subBegan
        _ = subEnded
    }
}
