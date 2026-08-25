import Foundation
import simd
import AcornEngine

/// Collectible item types.
public enum CollectibleType: Sendable, Equatable {
    case goldenAcorn
    case star(index: Int)
    case powerup(PowerupType)
    
    public var frameName: String {
        switch self {
        case .goldenAcorn:
            return "powerup_acorn_gold"
        case .star:
            return "star_full"
        case .powerup(let type):
            return type.frameName
        }
    }
    
    public var scoreValue: Int {
        switch self {
        case .goldenAcorn: return 50
        case .star: return 500
        case .powerup: return 100
        }
    }
}

/// ECS Component for pick-up items and stars.
public struct CollectibleComponent: Component {
    public var type: CollectibleType
    public var isCollected: Bool = false
    public var bobPhase: Float = 0.0
    public var radius: Float = 0.35
    
    public init(type: CollectibleType, radius: Float = 0.35) {
        self.type = type
        self.radius = radius
    }
}
