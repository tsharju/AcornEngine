import Foundation
import simd

/// The thematic zone for a campaign level.
public enum ZoneTheme: Int, CaseIterable, Sendable, Identifiable {
    case forestFloor = 1
    case mossyBarks = 2
    case autumnCanopy = 3
    case breezyBranches = 4
    case pineNeedleHollow = 5
    case mushroomKingdom = 6
    case twilightTreetops = 7
    case stormyCanopy = 8
    case ancientRedwoods = 9
    case worldTreeApex = 10
    
    public var id: Int { rawValue }
    
    /// User-facing display title for this zone.
    public var title: String {
        switch self {
        case .forestFloor: return "Oak Roots & Forest Floor"
        case .mossyBarks: return "Mossy Barks"
        case .autumnCanopy: return "Autumn Canopy"
        case .breezyBranches: return "Breezy Branches"
        case .pineNeedleHollow: return "Pine Needle Hollow"
        case .mushroomKingdom: return "Mushroom Kingdom"
        case .twilightTreetops: return "Twilight Treetops"
        case .stormyCanopy: return "Stormy Canopy"
        case .ancientRedwoods: return "Ancient Redwood Heights"
        case .worldTreeApex: return "Crown of the World Tree"
        }
    }
    
    /// Description of features in this zone.
    public var subtitle: String {
        switch self {
        case .forestFloor: return "Standard branches & gentle springs"
        case .mossyBarks: return "Moving platforms & golden acorns"
        case .autumnCanopy: return "Brittle twigs & sneaky spiders"
        case .breezyBranches: return "Vertical branches & propeller hats"
        case .pineNeedleHollow: return "Vanishing clouds & rocket jetpacks"
        case .mushroomKingdom: return "Super bouncy mushrooms & flying bats"
        case .twilightTreetops: return "Narrow boughs & energy shields"
        case .stormyCanopy: return "Fast hazards & black hole vortexes"
        case .ancientRedwoods: return "High-altitude precision leaps"
        case .worldTreeApex: return "The ultimate pinnacle climbing trial"
        }
    }
    
    /// Base background ambient tint color.
    public var backgroundColor: SIMD4<Float> {
        switch self {
        case .forestFloor: return SIMD4<Float>(0.08, 0.16, 0.12, 1.0)
        case .mossyBarks: return SIMD4<Float>(0.06, 0.18, 0.14, 1.0)
        case .autumnCanopy: return SIMD4<Float>(0.20, 0.12, 0.08, 1.0)
        case .breezyBranches: return SIMD4<Float>(0.08, 0.18, 0.22, 1.0)
        case .pineNeedleHollow: return SIMD4<Float>(0.05, 0.15, 0.18, 1.0)
        case .mushroomKingdom: return SIMD4<Float>(0.16, 0.08, 0.20, 1.0)
        case .twilightTreetops: return SIMD4<Float>(0.10, 0.06, 0.24, 1.0)
        case .stormyCanopy: return SIMD4<Float>(0.06, 0.08, 0.18, 1.0)
        case .ancientRedwoods: return SIMD4<Float>(0.18, 0.08, 0.06, 1.0)
        case .worldTreeApex: return SIMD4<Float>(0.12, 0.18, 0.32, 1.0)
        }
    }
    
    /// Determines the zone for a given 1-indexed level number.
    public static func zone(for level: Int) -> ZoneTheme {
        let clamped = max(1, min(100, level))
        let index = ((clamped - 1) / 10) + 1
        return ZoneTheme(rawValue: index) ?? .forestFloor
    }
}

/// Star threshold score requirements.
public struct StarThresholds: Sendable, Equatable {
    public var oneStar: Int
    public var twoStars: Int
    public var threeStars: Int
    
    public init(oneStar: Int, twoStars: Int, threeStars: Int) {
        self.oneStar = oneStar
        self.twoStars = twoStars
        self.threeStars = threeStars
    }
}

/// Defines the difficulty and layout configuration for a single campaign level.
public struct LevelDefinition: Sendable, Equatable {
    /// Level index (1...100).
    public let levelNumber: Int
    
    /// The thematic zone this level belongs to.
    public let zone: ZoneTheme
    
    /// Target vertical height in world units to complete the level.
    public let targetHeight: Float
    
    /// Vertical spacing between consecutive platforms.
    public let platformSpacingMin: Float
    public let platformSpacingMax: Float
    
    /// Ratio of horizontal moving platforms (0.0 ... 1.0).
    public let movingHorizontalRatio: Float
    
    /// Ratio of vertical moving platforms (0.0 ... 1.0).
    public let movingVerticalRatio: Float
    
    /// Ratio of fragile/breaking platforms (0.0 ... 1.0).
    public let breakingRatio: Float
    
    /// Ratio of disappearing platforms (0.0 ... 1.0).
    public let disappearingRatio: Float
    
    /// Ratio of spring / bouncy platforms (0.0 ... 1.0).
    public let springRatio: Float
    
    /// Probability of spawning a monster on eligible heights (0.0 ... 1.0).
    public let monsterSpawnChance: Float
    
    /// Probability of spawning powerups (0.0 ... 1.0).
    public let powerupSpawnChance: Float
    
    /// Total number of golden acorns distributed in this level.
    public let goldenAcornsCount: Int
    
    /// Score thresholds required to earn 1, 2, and 3 stars.
    public let starThresholdScores: StarThresholds
    
    /// Generates a balanced LevelDefinition for any level from 1 to 100.
    public static func definition(for level: Int) -> LevelDefinition {
        let lvl = max(1, min(100, level))
        let progress = Float(lvl - 1) / 99.0 // 0.0 at level 1, 1.0 at level 100
        let zone = ZoneTheme.zone(for: lvl)
        
        // Target height escalates from 40m at Level 1 to 450m at Level 100
        let targetHeight = 40.0 + progress * 410.0
        
        // Spacing tightens slightly at high levels
        let spacingMin = 1.1 + progress * 0.4
        let spacingMax = 1.8 + progress * 0.7
        
        // Moving platforms increase with zone progression
        let movingH = min(0.35, 0.05 + progress * 0.30)
        let movingV = lvl >= 30 ? min(0.20, (Float(lvl - 30) / 70.0) * 0.20) : 0.0
        
        // Breaking platforms appear from zone 3 (lvl 21+)
        let breaking = lvl >= 20 ? min(0.30, (Float(lvl - 20) / 80.0) * 0.30) : 0.0
        
        // Disappearing platforms appear from zone 5 (lvl 41+)
        let disappearing = lvl >= 40 ? min(0.25, (Float(lvl - 40) / 60.0) * 0.25) : 0.0
        
        // Spring platforms maintain a healthy presence throughout
        let spring = max(0.08, 0.18 - progress * 0.08)
        
        // Monsters appear starting level 15+
        let monsterChance = lvl >= 15 ? min(0.28, (Float(lvl - 15) / 85.0) * 0.28) : 0.0
        
        // Powerups spawn moderately
        let powerupChance = 0.12 - progress * 0.04
        
        // Golden acorns placed per level
        let acornsCount = 4 + Int(progress * 14.0)
        
        // Star score thresholds
        let baseClearScore = Int(targetHeight * 10.0)
        let oneStar = baseClearScore
        let twoStars = baseClearScore + (acornsCount * 50) / 2 + 200
        let threeStars = baseClearScore + (acornsCount * 50) + 500
        
        return LevelDefinition(
            levelNumber: lvl,
            zone: zone,
            targetHeight: targetHeight,
            platformSpacingMin: spacingMin,
            platformSpacingMax: spacingMax,
            movingHorizontalRatio: movingH,
            movingVerticalRatio: movingV,
            breakingRatio: breaking,
            disappearingRatio: disappearing,
            springRatio: spring,
            monsterSpawnChance: monsterChance,
            powerupSpawnChance: powerupChance,
            goldenAcornsCount: acornsCount,
            starThresholdScores: StarThresholds(oneStar: oneStar, twoStars: twoStars, threeStars: threeStars)
        )
    }
}
