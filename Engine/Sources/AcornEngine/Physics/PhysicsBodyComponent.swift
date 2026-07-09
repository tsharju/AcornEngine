import box2d
import simd

/// Represents a physical body in the physics simulation.
public struct PhysicsBodyComponent: Component, @unchecked Sendable {
    public enum BodyType: Int, Sendable {
        case staticBody = 0
        case kinematicBody = 1
        case dynamicBody = 2
        
        var b2Type: b2BodyType {
            switch self {
            case .staticBody: return b2_staticBody
            case .kinematicBody: return b2_kinematicBody
            case .dynamicBody: return b2_dynamicBody
            }
        }
    }
    
    public var type: BodyType
    public var isAwake: Bool
    public var linearVelocity: SIMD2<Float>
    public var angularVelocity: Float
    public var linearDamping: Float
    public var angularDamping: Float
    public var gravityScale: Float
    public var isBullet: Bool
    public var fixedRotation: Bool
    
    // Internal Box2D body ID. Set by the PhysicsSystem.
    public internal(set) var bodyId: b2BodyId?
    
    public init(
        type: BodyType = .dynamicBody,
        isAwake: Bool = true,
        linearVelocity: SIMD2<Float> = .zero,
        angularVelocity: Float = 0.0,
        linearDamping: Float = 0.0,
        angularDamping: Float = 0.0,
        gravityScale: Float = 1.0,
        isBullet: Bool = false,
        fixedRotation: Bool = false
    ) {
        self.type = type
        self.isAwake = isAwake
        self.linearVelocity = linearVelocity
        self.angularVelocity = angularVelocity
        self.linearDamping = linearDamping
        self.angularDamping = angularDamping
        self.gravityScale = gravityScale
        self.isBullet = isBullet
        self.fixedRotation = fixedRotation
        self.bodyId = nil
    }
}
