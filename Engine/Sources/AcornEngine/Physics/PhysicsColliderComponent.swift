import box2d
import simd

/// Defines a shape attached to a physics body.
public struct PhysicsColliderComponent: Component, @unchecked Sendable {
    public enum ShapeType: Sendable {
        /// A box shape. `width` and `height` are full dimensions, not half-dimensions.
        case box(width: Float, height: Float)
        /// A circle shape with the given `radius`.
        case circle(radius: Float)
    }
    
    public var shapeType: ShapeType
    public var friction: Float
    public var restitution: Float
    public var density: Float
    public var isSensor: Bool
    public var enableContactEvents: Bool
    public var enableSensorEvents: Bool
    
    // Internal Box2D shape ID. Set by the PhysicsSystem.
    public internal(set) var shapeId: b2ShapeId?
    
    public init(
        shapeType: ShapeType,
        friction: Float = 0.3,
        restitution: Float = 0.0,
        density: Float = 1.0,
        isSensor: Bool = false,
        enableContactEvents: Bool = true,
        enableSensorEvents: Bool = true
    ) {
        self.shapeType = shapeType
        self.friction = friction
        self.restitution = restitution
        self.density = density
        self.isSensor = isSensor
        self.enableContactEvents = enableContactEvents
        self.enableSensorEvents = enableSensorEvents
        self.shapeId = nil
    }
}
