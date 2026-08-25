import Foundation
import simd
import AcornEngine

/// Distinct gameplay platform behaviors.
public enum PlatformType: Sendable, Equatable {
    case wood
    case leaf
    case movingHorizontal(amplitude: Float, speed: Float, startX: Float, phase: Float)
    case movingVertical(amplitude: Float, speed: Float, startY: Float, phase: Float)
    case breaking(isBroken: Bool, breakProgress: Float)
    case disappearing(lifetime: Float, isTriggered: Bool)
    case spring(isCompressed: Bool, cooldown: Float)
    
    public var frameName: String {
        switch self {
        case .wood:
            return "platform_wood"
        case .leaf:
            return "platform_leaf"
        case .movingHorizontal, .movingVertical:
            return "platform_moving"
        case .breaking(let isBroken, _):
            return isBroken ? "platform_broken_2" : "platform_broken_1"
        case .disappearing:
            return "platform_disappearing"
        case .spring(let isCompressed, _):
            return isCompressed ? "platform_spring_active" : "platform_spring_idle"
        }
    }
}

/// ECS Component for jumping platforms.
public struct PlatformComponent: Component {
    public var type: PlatformType
    public var width: Float
    public var height: Float
    
    /// Normal bounce boost imparted on landing.
    public var jumpBoost: Float
    
    /// Super bounce boost for springs.
    public var springBoost: Float
    
    /// Flag indicating whether the platform has been stepped on.
    public var isSteppedOn: Bool = false
    
    public init(
        type: PlatformType,
        width: Float = 1.2,
        height: Float = 0.3,
        jumpBoost: Float = 11.5,
        springBoost: Float = 20.0
    ) {
        self.type = type
        self.width = width
        self.height = height
        self.jumpBoost = jumpBoost
        self.springBoost = springBoost
    }
}
