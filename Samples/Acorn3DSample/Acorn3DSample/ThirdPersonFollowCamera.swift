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
    
    /// Initializes a new third-person follow camera controller.
    /// - Parameters:
    ///   - entity: The camera entity in the world.
    ///   - target: The target entity to follow.
    ///   - distance: Initial distance in meters (clamped 15.0...400.0, default 80.0).
    ///   - pitch: Initial pitch in radians (clamped 0.2...1.4, default 0.785).
    ///   - yaw: Initial yaw in radians (default 0.0).
    public init(
        entity: Entity,
        target: Entity,
        distance: Float = 80.0,
        pitch: Float = 0.785,
        yaw: Float = 0.0
    ) {
        self.entity = entity
        self.target = target
        self.distance = min(max(distance, 15.0), 400.0)
        self.pitch = min(max(pitch, 0.2), 1.4)
        self.yaw = yaw
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
            yaw: yaw
        )
        followCam.update(world: world)
        return followCam
    }
    
    /// Updates camera position and rotation in the world to follow the target.
    /// - Parameter world: The ECS world containing the target and camera entities.
    public func update(world: World) {
        let targetPos = world.worldPosition(for: target)
        
        let clampedPitch = min(max(pitch, 0.2), 1.4)
        let clampedDist = min(max(distance, 15.0), 400.0)
        
        let hDist = clampedDist * cos(clampedPitch)
        let vDist = clampedDist * sin(clampedPitch)
        
        let camX = targetPos.x + hDist * sin(yaw)
        let camY = targetPos.y + vDist
        let camZ = targetPos.z + hDist * cos(yaw)
        let camPos = SIMD3<Float>(camX, camY, camZ)
        
        // Target look-at point slightly above ground/feet
        let lookTarget = targetPos + SIMD3<Float>(0, 2.0, 0)
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
        world.addComponent(transform, to: entity)
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
        yaw = heading
        while yaw < -.pi { yaw += 2 * .pi }
        while yaw > .pi { yaw -= 2 * .pi }
        pitch = 0.785
    }
}
