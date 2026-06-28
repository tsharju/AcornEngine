import Testing
import simd
@testable import AcornEngine

@Suite("Camera System Tests")
struct CameraSystemTests {
    @Test("Camera system tracks target smoothly")
    @MainActor
    func testCameraTracking() {
        let world = World()
        let cameraSystem = CameraSystem()
        
        let targetEntity = world.createEntity()
        let targetTransform = TransformComponent(position: SIMD3<Float>(10, 0, 0))
        world.addComponent(targetTransform, to: targetEntity)
        
        let cameraEntity = world.createEntity()
        let cameraTransform = TransformComponent(position: .zero)
        world.addComponent(cameraTransform, to: cameraEntity)
        
        // Offset of 0,0,5. Smoothing of 0.5.
        // It should move 50% of the way towards (10, 0, 5).
        let trackingComponent = CameraTrackingComponent(target: targetEntity, offset: SIMD3<Float>(0, 0, 5), smoothing: 0.5)
        world.addComponent(trackingComponent, to: cameraEntity)
        
        cameraSystem.update(world: world, deltaTime: 0.16)
        
        let updatedCameraTransform = world.component(ofType: TransformComponent.self, for: cameraEntity)
        #expect(updatedCameraTransform != nil)
        
        // position starts at 0,0,0
        // target position is 10,0,0 + 0,0,5 = 10,0,5
        // moving 50% towards 10,0,5 should result in 5,0,2.5
        if let pos = updatedCameraTransform?.position {
            #expect(abs(pos.x - 5.0) < 1e-5)
            #expect(abs(pos.y - 0.0) < 1e-5)
            #expect(abs(pos.z - 2.5) < 1e-5)
        }
    }
    
    @Test("Camera system orbits target correctly")
    @MainActor
    func testCameraOrbit() {
        let world = World()
        let cameraSystem = CameraSystem()
        
        let targetEntity = world.createEntity()
        let targetTransform = TransformComponent(position: .zero)
        world.addComponent(targetTransform, to: targetEntity)
        
        let cameraEntity = world.createEntity()
        let cameraTransform = TransformComponent(position: .zero)
        world.addComponent(cameraTransform, to: cameraEntity)
        
        // Setup simple orbit with no bobbing or sway to keep math simple:
        // radius = 5.0, speed = 1.0 rad/s, baseHeight = 2.0
        let orbitComponent = CameraOrbitComponent(
            target: targetEntity,
            radius: 5.0,
            speed: 1.0,
            baseHeight: 2.0,
            bobbingAmplitude: 0.0,
            bobbingSpeed: 0.0,
            swayAmplitude: 0.0,
            swaySpeed: 0.0,
            startingAngle: 0.0
        )
        world.addComponent(orbitComponent, to: cameraEntity)
        
        // Update with dt = 1.0 -> angle becomes 1.0 radians
        cameraSystem.update(world: world, deltaTime: 1.0)
        
        let updatedTransform = world.component(ofType: TransformComponent.self, for: cameraEntity)
        #expect(updatedTransform != nil)
        
        if let transform = updatedTransform {
            let expectedX = 5.0 * sin(Float(1.0))
            let expectedY: Float = 2.0
            let expectedZ = -5.0 * cos(Float(1.0))
            
            #expect(abs(transform.position.x - expectedX) < 1e-5)
            #expect(abs(transform.position.y - expectedY) < 1e-5)
            #expect(abs(transform.position.z - expectedZ) < 1e-5)
            
            // Expected yaw = -atan2(xOffset, -zOffset) = -1.0
            // Expected pitch = atan2(yBob, XZdist) = atan2(2, 5)
            let expectedYaw: Float = -1.0
            let expectedPitch = atan2(Float(2.0), Float(5.0))
            
            #expect(abs(transform.rotation.x - expectedPitch) < 1e-5)
            #expect(abs(transform.rotation.y - expectedYaw) < 1e-5)
            #expect(abs(transform.rotation.z - 0.0) < 1e-5)
        }
    }
}
