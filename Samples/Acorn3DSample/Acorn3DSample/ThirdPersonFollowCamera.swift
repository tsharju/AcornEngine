import Foundation
import simd
import AcornEngine
import AcornMath

/// A class that manages the camera entity in the AcornEngine World to follow a target in third-person view.
///
/// Computes orbital position based on yaw, pitch, and distance, and updates the camera's
/// `TransformComponent` to look at the target entity.
@MainActor
public final class ThirdPersonFollowCamera {
    /// The camera entity in the ECS world.
    public let entity: Entity
    
    /// The target entity to follow.
    public var target: Entity
    
    /// The distance from the camera to the target in meters (clamped between 15.0 and 400.0).
    public var distance: Float {
        didSet {
            distance = min(max(distance, 15.0), 400.0)
        }
    }
    
    /// The vertical pitch angle of the camera in radians (clamped between 0.2 and 1.4).
    public var pitch: Float {
        didSet {
            pitch = min(max(pitch, 0.2), 1.4)
        }
    }
    
    /// The horizontal orbit yaw angle in radians.
    public var yaw: Float
    
    /// Current 3D look-at focus position in world space.
    public var focusPosition: SIMD3<Float>
    
    /// Whether the camera is automatically tracking the target entity.
    public private(set) var isFollowingTarget: Bool
    
    /// Whether the camera is currently smoothly interpolating back towards the target entity.
    public private(set) var isInterpolatingToTarget: Bool
    
    /// Speed at which the camera focus point interpolates back to the target entity.
    public var focusInterpolationRate: Float = 6.0
    
    /// Initializes a new third-person follow camera controller.
    /// - Parameters:
    ///   - entity: The camera entity in the world.
    ///   - target: The target entity to follow.
    ///   - distance: Initial distance in meters (clamped 15.0...400.0, default 80.0).
    ///   - pitch: Initial pitch in radians (clamped 0.2...1.4, default 0.785).
    ///   - yaw: Initial yaw in radians (default 0.0).
    ///   - focusPosition: Initial focus position in world space (default .zero).
    public init(
        entity: Entity,
        target: Entity,
        distance: Float = 80.0,
        pitch: Float = 0.785,
        yaw: Float = 0.0,
        focusPosition: SIMD3<Float> = .zero
    ) {
        self.entity = entity
        self.target = target
        self.distance = min(max(distance, 15.0), 400.0)
        self.pitch = min(max(pitch, 0.2), 1.4)
        self.yaw = yaw
        self.focusPosition = focusPosition
        self.isFollowingTarget = true
        self.isInterpolatingToTarget = false
    }
    
    /// Creates and configures a new camera entity with perspective projection in the world.
    /// - Parameters:
    ///   - world: The ECS world.
    ///   - target: The target entity to follow.
    ///   - distance: Initial follow distance. Defaults to 80.0.
    ///   - pitch: Initial vertical pitch. Defaults to 0.785 (~45 degrees).
    ///   - yaw: Initial yaw. Defaults to 0.0.
    ///   - fovY: Vertical field of view in radians. Defaults to 60 degrees.
    ///   - nearZ: Near clipping plane. Defaults to 0.5.
    ///   - farZ: Far clipping plane. Defaults to 3000.0.
    ///   - aspectRatio: Viewport aspect ratio. Defaults to 1.0.
    /// - Returns: A new `ThirdPersonFollowCamera` instance.
    public static func create(
        in world: World,
        target: Entity,
        distance: Float = 80.0,
        pitch: Float = 0.785,
        yaw: Float = 0.0,
        fovY: Float = .pi / 3.0,
        nearZ: Float = 0.5,
        farZ: Float = 3000.0,
        aspectRatio: Float = 1.0
    ) -> ThirdPersonFollowCamera {
        let cameraEntity = world.createEntity()
        #if DEBUG
        world.setName("ThirdPersonCamera", for: cameraEntity)
        #endif
        
        let cameraComponent = CameraComponent(
            projectionType: .perspective,
            fovY: fovY,
            nearZ: nearZ,
            farZ: farZ,
            aspectRatio: aspectRatio
        )
        world.addComponent(cameraComponent, to: cameraEntity)
        world.addComponent(TransformComponent(), to: cameraEntity)
        
        let followCam = ThirdPersonFollowCamera(
            entity: cameraEntity,
            target: target,
            distance: distance,
            pitch: pitch,
            yaw: yaw,
            focusPosition: world.worldPosition(for: target)
        )
        followCam.update(world: world)
        return followCam
    }
    
    /// Updates camera position and rotation in the world to follow the target or focus point.
    /// - Parameters:
    ///   - world: The ECS world containing the target and camera entities.
    ///   - deltaTime: The elapsed frame time in seconds (used for smooth target transition).
    public func update(world: World, deltaTime: Double = 0.016) {
        let targetPos = world.worldPosition(for: target)
        
        if isFollowingTarget {
            if isInterpolatingToTarget {
                let diff = targetPos - focusPosition
                let dist = simd_length(diff)
                if dist < 0.05 {
                    focusPosition = targetPos
                    isInterpolatingToTarget = false
                } else {
                    let t = min(1.0, max(0.0, 1.0 - exp(-focusInterpolationRate * Float(deltaTime))))
                    focusPosition += diff * t
                }
            } else {
                focusPosition = targetPos
            }
        }
        
        let clampedPitch = min(max(pitch, 0.2), 1.4)
        let clampedDist = min(max(distance, 15.0), 400.0)
        
        let hDist = clampedDist * cos(clampedPitch)
        let vDist = clampedDist * sin(clampedPitch)
        
        let camX = focusPosition.x + hDist * sin(yaw)
        let camY = focusPosition.y + vDist
        let camZ = focusPosition.z + hDist * cos(yaw)
        let camPos = SIMD3<Float>(camX, camY, camZ)
        
        // Target look-at point at character torso (1.0m above ground)
        let lookTarget = focusPosition + SIMD3<Float>(0, 1.0, 0)
        let dx = lookTarget.x - camPos.x
        let dy = camPos.y - lookTarget.y
        let dz = lookTarget.z - camPos.z
        let currentHDist = simd_length(SIMD2<Float>(dx, dz))
        
        // In AcornEngine's left-handed projection (+Z forward, w_clip = z_view > 0):
        // Pitch is positive when camera is above target (tilts down towards target).
        // Yaw faces the direction vector (dx, dz) towards the target.
        let lookPitch = atan2(dy, max(0.001, currentHDist))
        let lookYaw = atan2(dx, dz)
        
        var transform = world.component(ofType: TransformComponent.self, for: entity) ?? TransformComponent()
        transform.position = camPos
        transform.rotation = SIMD3<Float>(lookPitch, lookYaw, 0.0)
        // Invert X to adapt right-handed world space (+X East, +Y Up, -Z North)
        // to left-handed camera view space (+X Right, +Y Up, +Z Forward).
        transform.scale = SIMD3<Float>(-1, 1, 1)
        world.addComponent(transform, to: entity)
    }
    
    /// Smoothly rotates the camera yaw to follow behind the target's movement heading.
    /// - Parameters:
    ///   - targetHeading: The target heading in radians.
    ///   - deltaTime: The elapsed frame time in seconds.
    ///   - lerpRate: Follow interpolation speed (default 2.5).
    public func followHeading(_ targetHeading: Float, deltaTime: Double, lerpRate: Float = 2.5) {
        guard isFollowingTarget else { return }
        var diff = targetHeading - yaw
        while diff < -.pi { diff += 2 * .pi }
        while diff > .pi { diff -= 2 * .pi }
        
        let t = min(1.0, max(0.0, 1.0 - exp(-lerpRate * Float(deltaTime))))
        yaw += diff * t
        while yaw < -.pi { yaw += 2 * .pi }
        while yaw > .pi { yaw -= 2 * .pi }
    }
    
    /// Pans the camera focus point on the horizontal XZ plane along camera horizontal basis axes.
    ///
    /// Detaches the camera from automatically following the target entity.
    /// - Parameters:
    ///   - deltaRight: Displacement along the camera's horizontal right axis.
    ///   - deltaForward: Displacement along the camera's horizontal forward axis.
    public func pan(deltaRight: Float, deltaForward: Float) {
        isFollowingTarget = false
        isInterpolatingToTarget = false
        
        // Camera horizontal basis vectors
        let camForward = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
        let camRight = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        
        focusPosition += camRight * deltaRight + camForward * deltaForward
    }
    
    /// Pans the camera focus point by a world-space translation vector.
    ///
    /// Detaches the camera from automatically following the target entity.
    /// - Parameter deltaWorld: The displacement vector in world space.
    public func pan(deltaWorld: SIMD3<Float>) {
        isFollowingTarget = false
        isInterpolatingToTarget = false
        focusPosition += deltaWorld
    }
    
    /// Re-engages focus on the target entity.
    /// - Parameter animated: Whether to smoothly glide back to the target (`true`) or snap immediately (`false`).
    public func focusOnTarget(animated: Bool = true) {
        isFollowingTarget = true
        isInterpolatingToTarget = animated
    }
    
    /// Orbits the camera around the target by the given yaw and pitch deltas.
    /// - Parameters:
    ///   - deltaYaw: Horizontal rotation angle delta in radians.
    ///   - deltaPitch: Vertical rotation angle delta in radians.
    public func orbit(deltaYaw: Float, deltaPitch: Float) {
        yaw += deltaYaw
        while yaw < -.pi { yaw += 2 * .pi }
        while yaw > .pi { yaw -= 2 * .pi }
        
        pitch = min(max(pitch + deltaPitch, 0.2), 1.4)
    }
    
    /// Zooms the camera by adjusting the follow distance with the given scale factor.
    /// - Parameter scale: Scale factor (values > 1 zoom in, values < 1 zoom out).
    public func zoom(scale: Float) {
        guard scale > 0 else { return }
        distance = min(max(distance / scale, 15.0), 400.0)
    }
    
    /// Snaps the camera directly behind the player based on the player's heading angle.
    /// - Parameter heading: The player's heading yaw in radians.
    public func resetBehind(heading: Float) {
        isFollowingTarget = true
        isInterpolatingToTarget = false
        yaw = heading
        while yaw < -.pi { yaw += 2 * .pi }
        while yaw > .pi { yaw -= 2 * .pi }
        pitch = 0.785
    }
}
