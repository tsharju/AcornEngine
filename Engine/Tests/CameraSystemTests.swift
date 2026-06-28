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
}
