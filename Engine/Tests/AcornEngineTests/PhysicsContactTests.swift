import Testing
import simd
import box2d
@testable import AcornEngine

@Suite("Physics Contact & Sensor Tests")
@MainActor
struct PhysicsContactTests {
    
    @Test("CollisionEnter, CollisionStay, and CollisionExit lifecycle")
    func testCollisionLifecycle() {
        let world = World()
        let physicsSystem = PhysicsSystem()
        world.registerSystem(physicsSystem)
        
        // 1. Static Floor at y = 0
        let floor = world.createEntity()
        world.addComponent(TransformComponent(position: SIMD3<Float>(0, 0, 0)), to: floor)
        world.addComponent(PhysicsBodyComponent(type: .staticBody), to: floor)
        world.addComponent(PhysicsColliderComponent(shapeType: .box(width: 10.0, height: 1.0)), to: floor)
        
        // 2. Dynamic Box falling from y = 3
        let box = world.createEntity()
        world.addComponent(TransformComponent(position: SIMD3<Float>(0, 3, 0)), to: box)
        world.addComponent(PhysicsBodyComponent(type: .dynamicBody), to: box)
        world.addComponent(PhysicsColliderComponent(shapeType: .box(width: 1.0, height: 1.0)), to: box)
        
        var enterEvents: [CollisionEnterEvent] = []
        var stayCount = 0
        var exitEvents: [CollisionExitEvent] = []
        
        let subEnter = world.eventBus.subscribe(CollisionEnterEvent.self) { event in
            enterEvents.append(event)
        }
        let subStay = world.eventBus.subscribe(CollisionStayEvent.self) { _ in
            stayCount += 1
        }
        let subExit = world.eventBus.subscribe(CollisionExitEvent.self) { event in
            exitEvents.append(event)
        }
        
        // Step simulation until box hits the floor
        var collided = false
        for _ in 0..<60 {
            world.update(deltaTime: 1.0 / 60.0)
            if !enterEvents.isEmpty {
                collided = true
                break
            }
        }
        
        #expect(collided)
        #expect(!enterEvents.isEmpty)
        let enter = enterEvents[0]
        #expect(enter.involves(box))
        #expect(enter.involves(floor))
        #expect(enter.otherEntity(than: box) == floor)
        
        // Step several more frames while resting on the floor
        let stayBefore = stayCount
        for _ in 0..<10 {
            world.update(deltaTime: 1.0 / 60.0)
        }
        #expect(stayCount > stayBefore)
        
        // Now impart an upward velocity on the box to separate from the floor
        if var bodyComp = world.component(ofType: PhysicsBodyComponent.self, for: box),
           let b2Body = bodyComp.bodyId {
            b2Body_SetLinearVelocity(b2Body, b2Vec2(x: 0, y: 15.0))
            bodyComp.linearVelocity = SIMD2<Float>(0, 15.0)
            world.addComponent(bodyComp, to: box)
        }
        
        // Step simulation to observe separation
        var exited = false
        for _ in 0..<30 {
            world.update(deltaTime: 1.0 / 60.0)
            if !exitEvents.isEmpty {
                exited = true
                break
            }
        }
        
        #expect(exited)
        let exit = exitEvents[0]
        #expect(exit.involves(box))
        #expect(exit.involves(floor))
        
        _ = subEnter
        _ = subStay
        _ = subExit
    }
    
    @Test("SensorTriggerComponent enter, stay, exit, and overlap queries")
    func testSensorTriggerLifecycle() {
        let world = World()
        let physicsSystem = PhysicsSystem()
        world.registerSystem(physicsSystem)
        
        // 1. Static Sensor Trigger Volume at y = 5 (height = 2, so spans y: [4.0, 6.0])
        let sensorEntity = world.createEntity()
        world.addComponent(TransformComponent(position: SIMD3<Float>(0, 5, 0)), to: sensorEntity)
        world.addComponent(PhysicsBodyComponent(type: .staticBody), to: sensorEntity)
        world.addComponent(SensorTriggerComponent(shapeType: .box(width: 4.0, height: 2.0)), to: sensorEntity)
        
        // 2. Dynamic Box starting at y = 8 (above sensor), falling down through it
        let visitorBox = world.createEntity()
        world.addComponent(TransformComponent(position: SIMD3<Float>(0, 8, 0)), to: visitorBox)
        world.addComponent(PhysicsBodyComponent(type: .dynamicBody), to: visitorBox)
        world.addComponent(PhysicsColliderComponent(shapeType: .box(width: 1.0, height: 1.0)), to: visitorBox)
        
        var sensorEnterEvents: [SensorEnterEvent] = []
        var sensorStayCount = 0
        var sensorExitEvents: [SensorExitEvent] = []
        
        let subEnter = world.eventBus.subscribe(SensorEnterEvent.self) { event in
            sensorEnterEvents.append(event)
        }
        let subStay = world.eventBus.subscribe(SensorStayEvent.self) { _ in
            sensorStayCount += 1
        }
        let subExit = world.eventBus.subscribe(SensorExitEvent.self) { event in
            sensorExitEvents.append(event)
        }
        
        // Initial state: not overlapping
        let initialSensor = world.component(ofType: SensorTriggerComponent.self, for: sensorEntity)
        #expect(initialSensor?.overlapCount == 0)
        #expect(initialSensor?.isOverlapping(visitorBox) == false)
        
        // Step simulation until box enters sensor zone
        var entered = false
        for _ in 0..<40 {
            world.update(deltaTime: 1.0 / 60.0)
            if !sensorEnterEvents.isEmpty {
                entered = true
                break
            }
        }
        
        #expect(entered)
        #expect(sensorEnterEvents[0].sensorEntity == sensorEntity)
        #expect(sensorEnterEvents[0].visitorEntity == visitorBox)
        
        let duringSensor = world.component(ofType: SensorTriggerComponent.self, for: sensorEntity)
        #expect(duringSensor?.overlapCount == 1)
        #expect(duringSensor?.isOverlapping(visitorBox) == true)
        
        // Step simulation further as it falls out of the bottom of the sensor
        var exited = false
        for _ in 0..<60 {
            world.update(deltaTime: 1.0 / 60.0)
            if !sensorExitEvents.isEmpty {
                exited = true
                break
            }
        }
        
        #expect(exited)
        #expect(sensorStayCount > 0)
        #expect(sensorExitEvents[0].sensorEntity == sensorEntity)
        #expect(sensorExitEvents[0].visitorEntity == visitorBox)
        
        let afterExitSensor = world.component(ofType: SensorTriggerComponent.self, for: sensorEntity)
        #expect(afterExitSensor?.overlapCount == 0)
        #expect(afterExitSensor?.isOverlapping(visitorBox) == false)
        
        _ = subEnter
        _ = subStay
        _ = subExit
    }
}
