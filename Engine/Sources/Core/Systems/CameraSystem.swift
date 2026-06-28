import Foundation
import simd

/// A system that updates camera positions based on their tracking targets.
@MainActor
public struct CameraSystem: System {
    /// Initializes a new camera system.
    public init() {}
    
    /// Updates cameras with tracking components to follow their targets.
    /// - Parameters:
    ///   - world: The ECS world.
    ///   - deltaTime: The time elapsed since the last update.
    public func update(world: World, deltaTime: Double) {
        let trackingEntities = world.entities(with: CameraTrackingComponent.self)
        
        for (entity, tracking) in trackingEntities {
            guard var transform = world.component(ofType: TransformComponent.self, for: entity) else {
                continue
            }
            
            guard let targetTransform = world.component(ofType: TransformComponent.self, for: tracking.target) else {
                continue
            }
            
            let targetPosition = targetTransform.position + tracking.offset
            
            // Interpolate towards the target position
            // Uses simple linear interpolation for smoothing
            transform.position = simd_mix(transform.position, targetPosition, SIMD3<Float>(repeating: tracking.smoothing))
            
            world.addComponent(transform, to: entity)
        }
    }
}
