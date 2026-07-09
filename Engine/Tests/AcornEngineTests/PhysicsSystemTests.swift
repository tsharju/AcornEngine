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
}
