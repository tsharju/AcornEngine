import Foundation
import simd

/// A component that makes an entity (typically a camera) float in the air and orbit around a target.
public struct CameraOrbitComponent: Component {
    /// The target entity to orbit and look at.
    public var target: Entity
    
    /// The distance from the target.
    public var radius: Float
    
    /// The orbit rotation speed around the Y-axis (radians per second).
    public var speed: Float
    
    /// The base vertical offset above the target.
    public var baseHeight: Float
    
    /// The vertical floating (bobbing) amplitude.
    public var bobbingAmplitude: Float
    
    /// The vertical floating (bobbing) speed factor.
    public var bobbingSpeed: Float
    
    /// The horizontal floating (sway) amplitude.
    public var swayAmplitude: Float
    
    /// The horizontal floating (sway) speed factor.
    public var swaySpeed: Float
    
    /// Whether to sway the angle back and forth instead of a continuous 360 orbit.
    public var useAngleSway: Bool
    
    /// The amplitude of the angle sway in radians (if useAngleSway is true).
    public var swayAngleAmplitude: Float
    
    /// The accumulated time for the floating and sway animations.
    public var time: Double = 0.0
    
    /// The current orbit angle around the Y-axis (or the center of sway).
    public var angle: Float
    
    /// Initializes a new camera orbit component.
    /// - Parameters:
    ///   - target: The entity ID to orbit and look at.
    ///   - radius: The orbit radius. Defaults to 5.0.
    ///   - speed: The orbit speed in radians/sec. Defaults to 0.2.
    ///   - baseHeight: The base height offset. Defaults to 0.5.
    ///   - bobbingAmplitude: The vertical bobbing amplitude. Defaults to 0.2.
    ///   - bobbingSpeed: The vertical bobbing speed factor. Defaults to 1.0.
    ///   - swayAmplitude: The horizontal sway amplitude. Defaults to 0.1.
    ///   - swaySpeed: The horizontal sway speed factor. Defaults to 0.8.
    ///   - useAngleSway: Whether to sway the angle. Defaults to true.
    ///   - swayAngleAmplitude: The amplitude of angle sway. Defaults to 0.6.
    ///   - startingAngle: The starting angle. Defaults to 0.0.
    public init(
        target: Entity,
        radius: Float = 5.0,
        speed: Float = 0.2,
        baseHeight: Float = 0.5,
        bobbingAmplitude: Float = 0.2,
        bobbingSpeed: Float = 1.0,
        swayAmplitude: Float = 0.1,
        swaySpeed: Float = 0.8,
        useAngleSway: Bool = true,
        swayAngleAmplitude: Float = 0.6,
        startingAngle: Float = 0.0
    ) {
        self.target = target
        self.radius = radius
        self.speed = speed
        self.baseHeight = baseHeight
        self.bobbingAmplitude = bobbingAmplitude
        self.bobbingSpeed = bobbingSpeed
        self.swayAmplitude = swayAmplitude
        self.swaySpeed = swaySpeed
        self.useAngleSway = useAngleSway
        self.swayAngleAmplitude = swayAngleAmplitude
        self.angle = startingAngle
    }
}
