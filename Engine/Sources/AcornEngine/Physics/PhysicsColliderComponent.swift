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
    
    // Internal Box2D shape ID. Set by the PhysicsSystem.
    public internal(set) var shapeId: b2ShapeId?
    
    public init(
        shapeType: ShapeType,
        friction: Float = 0.3,
        restitution: Float = 0.0,
        density: Float = 1.0
    ) {
        self.shapeType = shapeType
        self.friction = friction
        self.restitution = restitution
        self.density = density
        self.shapeId = nil
    }
}
