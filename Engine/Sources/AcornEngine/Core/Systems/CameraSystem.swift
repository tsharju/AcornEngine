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
        // 1. Process standard camera tracking
        world.forEach(CameraTrackingComponent.self) { entity, tracking in
            guard var transform = world.component(ofType: TransformComponent.self, for: entity) else {
                return
            }
            
            guard world.component(ofType: TransformComponent.self, for: tracking.target) != nil else {
                return
            }
            
            let targetPosition = world.worldPosition(for: tracking.target) + tracking.offset
            
            // Interpolate towards the target position
            // Uses simple linear interpolation for smoothing
            transform.position = simd_mix(transform.position, targetPosition, SIMD3<Float>(repeating: tracking.smoothing))
            
            world.addComponent(transform, to: entity)
        }
        
        // 2. Process floating camera orbiting
        world.forEach(CameraOrbitComponent.self) { entity, orbit in
            guard var transform = world.component(ofType: TransformComponent.self, for: entity) else {
                return
            }
            
            var mutableOrbit = orbit
            mutableOrbit.time += deltaTime
            
            let angle: Float
            if orbit.useAngleSway {
                // In sway mode, angle changes back and forth around the starting angle
                angle = orbit.angle + orbit.swayAngleAmplitude * sin(Float(orbit.speed) * Float(mutableOrbit.time))
            } else {
                // In continuous mode, angle increases linearly
                mutableOrbit.angle += orbit.speed * Float(deltaTime)
                angle = mutableOrbit.angle
            }
            
            // Get target position
            let targetPos: SIMD3<Float>
            if world.component(ofType: TransformComponent.self, for: orbit.target) != nil {
                targetPos = world.worldPosition(for: orbit.target)
            } else {
                targetPos = .zero
            }
            
            let time = Float(mutableOrbit.time)
            
            // Calculate orbital offset on XZ plane
            let xOffset = orbit.radius * sin(angle)
            let zOffset = -orbit.radius * cos(angle)
            
            // Floating/bobbing on Y axis, swaying on X axis
            let yBob = orbit.baseHeight + orbit.bobbingAmplitude * sin(orbit.bobbingSpeed * time)
            let xSway = orbit.swayAmplitude * cos(orbit.swaySpeed * time)
            
            // Compute the new camera position
            var position = targetPos
            position.x += xOffset + xSway
            position.y += yBob
            position.z += zOffset
            
            transform.position = position
            
            // Calculate look-at rotation:
            // Yaw is the rotation around Y-axis to face the target horizontally
            let yaw = atan2(xOffset + xSway, -zOffset)
            
            // Pitch is the rotation around X-axis to face the target vertically
            let horizontalDistance = sqrt((xOffset + xSway) * (xOffset + xSway) + zOffset * zOffset)
            let pitch = atan2(yBob, horizontalDistance)
            
            // Apply Euler angles (pitch, yaw, roll = 0)
            transform.rotation = SIMD3<Float>(pitch, -yaw, 0.0)
            
            // Write back to components
            world.addComponent(transform, to: entity)
            world.addComponent(mutableOrbit, to: entity)
        }
    }
}
