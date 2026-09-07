import Testing
import simd
import box2d
@testable import AcornEngine

@MainActor
@Suite("Physics System Tests")
struct PhysicsSystemTests {
    @Test("Test basic physics integration")
    func testPhysicsIntegration() {
        let world = World()
        let physicsSystem = PhysicsSystem()
        world.registerSystem(physicsSystem)
        
        // Create an entity to be a falling box
        let entity = world.createEntity()
        let initialTransform = TransformComponent(position: SIMD3<Float>(0, 10, 0))
        world.addComponent(initialTransform, to: entity)
        
        let bodyComponent = PhysicsBodyComponent(type: .dynamicBody)
        world.addComponent(bodyComponent, to: entity)
        
        let colliderComponent = PhysicsColliderComponent(shapeType: .box(width: 1.0, height: 1.0))
        world.addComponent(colliderComponent, to: entity)
        
        // Create a static ground entity
        let groundEntity = world.createEntity()
        let groundTransform = TransformComponent(position: SIMD3<Float>(0, 0, 0))
        world.addComponent(groundTransform, to: groundEntity)
        
        let groundBody = PhysicsBodyComponent(type: .staticBody)
        world.addComponent(groundBody, to: groundEntity)
        
        let groundCollider = PhysicsColliderComponent(shapeType: .box(width: 10.0, height: 1.0))
        world.addComponent(groundCollider, to: groundEntity)
        
        // Step 1: Initial state
        let t0 = world.component(ofType: TransformComponent.self, for: entity)
        #expect(t0?.position.y == 10)
        
        // Step 2: Step the simulation multiple times
        // Box2D physics simulation is ticked at 1/60s by default in the system
        for _ in 0..<60 {
            world.update(deltaTime: 1.0 / 60.0)
        }
        
        // Step 3: Check that it fell due to gravity
        let t1 = world.component(ofType: TransformComponent.self, for: entity)
        #expect(t1 != nil)
        
        // Since gravity is -9.81, and it falls for 1 second, it should have moved downwards.
        // It shouldn't have fallen through the ground at y = 0, considering sizes.
        // Box half height is 0.5, ground half height is 0.5.
        // So they collide at y = 1.0.
        // The position might bounce a bit depending on restitution, but it should be below 10 and above or equal to 0.5.
        if let yPos = t1?.position.y {
            #expect(yPos < 10.0)
            #expect(yPos > 0.0)
        }
    }

    @Test("Entity destruction and component removal cleans up Box2D bodies and shape registry")
    func testEntityDestructionCleansUpPhysicsBodies() {
        let world = World()
        let physicsSystem = PhysicsSystem()
        world.registerSystem(physicsSystem)
        
        // 1. Create two physics entities
        let entityA = world.createEntity()
        world.addComponent(TransformComponent(position: SIMD3<Float>(0, 5, 0)), to: entityA)
        world.addComponent(PhysicsBodyComponent(type: .dynamicBody), to: entityA)
        world.addComponent(PhysicsColliderComponent(shapeType: .box(width: 1.0, height: 1.0)), to: entityA)
        
        let entityB = world.createEntity()
        world.addComponent(TransformComponent(position: SIMD3<Float>(0, 0, 0)), to: entityB)
        world.addComponent(PhysicsBodyComponent(type: .staticBody), to: entityB)
        world.addComponent(PhysicsColliderComponent(shapeType: .circle(radius: 2.0)), to: entityB)
        
        world.update(deltaTime: 1.0 / 60.0)
        
        #expect(physicsSystem.activeBodyCount == 2)
        #expect(physicsSystem.registeredShapeCount == 2)
        #expect(physicsSystem.hasBody(for: entityA))
        #expect(physicsSystem.hasBody(for: entityB))
        
        // 2. Destroy entityA - verify its Box2D body & shape are cleaned up
        world.destroyEntity(entityA)
        world.update(deltaTime: 1.0 / 60.0)
        
        #expect(physicsSystem.activeBodyCount == 1)
        #expect(physicsSystem.registeredShapeCount == 1)
        #expect(!physicsSystem.hasBody(for: entityA))
        #expect(physicsSystem.hasBody(for: entityB))
        
        // 3. Remove PhysicsBodyComponent from entityB - verify its body & shape are cleaned up
        world.removeComponent(ofType: PhysicsBodyComponent.self, from: entityB)
        world.update(deltaTime: 1.0 / 60.0)
        
        #expect(physicsSystem.activeBodyCount == 0)
        #expect(physicsSystem.registeredShapeCount == 0)
        #expect(!physicsSystem.hasBody(for: entityB))
    }
}
