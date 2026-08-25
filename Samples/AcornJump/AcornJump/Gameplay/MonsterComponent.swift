import Foundation
import simd
import AcornEngine

/// Distinct monster types and patrol movement parameters.
public enum MonsterType: Sendable, Equatable {
    case spider(amplitude: Float, speed: Float, startX: Float, phase: Float)
    case bat(frequency: Float, amplitude: Float, time: Float, startX: Float)
    case chestnut(bounceSpeed: Float, startY: Float)
    case blackhole(pullRadius: Float, pullForce: Float)
    
    public var frameName: String {
        switch self {
        case .spider: return "monster_spider"
        case .bat: return "monster_bat"
        case .chestnut: return "monster_chestnut"
        case .blackhole: return "hazard_blackhole"
        }
    }
    
    public var scoreValue: Int {
        switch self {
        case .spider: return 200
        case .bat: return 300
        case .chestnut: return 250
        case .blackhole: return 0
        }
    }
}

/// ECS Component for enemy hazards.
public struct MonsterComponent: Component {
    public var type: MonsterType
    public var radius: Float
    public var isAlive: Bool = true
    public var deathTimer: Float = 0.0
    
    public init(type: MonsterType, radius: Float = 0.45) {
        self.type = type
        self.radius = radius
    }
}
