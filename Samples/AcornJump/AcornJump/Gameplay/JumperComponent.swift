import Foundation
import simd
import AcornEngine

/// Active wearable or consumed power-up type.
public enum PowerupType: Sendable, Equatable {
    case propeller(duration: Float)
    case jetpack(duration: Float)
    case shield(charges: Int)
    case springShoes(jumpsRemaining: Int)
    
    public var frameName: String {
        switch self {
        case .propeller: return "powerup_propeller"
        case .jetpack: return "powerup_jetpack"
        case .shield: return "powerup_shield"
        case .springShoes: return "powerup_spring"
        }
    }
}

/// Visual and animation state of the player character.
public enum JumperState: Sendable, Equatable {
    case idle
    case jumping
    case falling
    case flyingJetpack
    case flyingPropeller
    case shooting
    case dead
    case victory
}

/// ECS Component for the player jumper character with tuned physics and animation parameters.
public struct JumperComponent: Component {
    /// Current velocity (X = horizontal, Y = vertical).
    public var velocity: SIMD2<Float> = .zero
    
    /// Previous Y position before current tick (for swept continuous collision).
    public var previousY: Float = 0.0
    
    /// Current animation/action state.
    public var state: JumperState = .idle
    
    // MARK: - Vertical Physics & Jump Feel
    
    /// Normal bounce velocity when landing on standard platforms (tuned for brisk, satisfying leap).
    public var normalJumpVelocity: Float = 13.5
    
    /// High bounce velocity from springs / trampolines.
    public var springJumpVelocity: Float = 22.5
    
    /// Upward thrust velocity while flying with jetpack.
    public var jetpackThrustVelocity: Float = 17.5
    
    /// Upward thrust velocity while flying with propeller hat.
    public var propellerThrustVelocity: Float = 11.0
    
    /// Terminal falling velocity.
    public var terminalVelocity: Float = -18.0
    
    /// Base gravity acceleration.
    public var baseGravity: Float = -26.0
    
    /// Gravity multiplier near apex of jump for floaty hang-time.
    public var apexGravityMultiplier: Float = 0.70
    
    // MARK: - Horizontal Inertia & Steering
    
    /// Maximum horizontal speed (tuned for smooth, controlled motion).
    public var maxHorizontalSpeed: Float = 6.8
    
    /// Horizontal acceleration rate when input is applied.
    public var horizontalAcceleration: Float = 30.0
    
    /// Horizontal deceleration / drag rate when coasting (tuned for stable landings).
    public var horizontalDeceleration: Float = 26.0
    
    /// Normalized horizontal steering input [-1.0, 1.0].
    public var horizontalSteering: Float = 0.0
    
    /// Left and right screen wrap boundaries.
    public var screenWrapBounds: Float = 3.2
    
    /// Collision radius for platforms and items.
    public var collisionRadius: Float = 0.38
    
    // MARK: - Squash, Stretch & Lean Animation
    
    /// Dynamic squash and stretch scale multiplier (default (1.0, 1.0)).
    public var squashStretch: SIMD2<Float> = SIMD2<Float>(1.0, 1.0)
    
    /// Target tilt angle around Z-axis based on horizontal motion.
    public var leanAngle: Float = 0.0
    
    // MARK: - Powerups & Items
    
    /// Currently active powerup and its remaining duration.
    public var activePowerup: PowerupType? = nil
    public var powerupTimeRemaining: Float = 0.0
    public var shieldCharges: Int = 0
    public var springShoesJumpsRemaining: Int = 0
    
    /// Shooting cooldown timer.
    public var shootCooldown: Float = 0.0
    
    // MARK: - Metrics & Progress
    
    /// Tracked metrics for scoring.
    public var currentHeight: Float = 0.0
    public var maxHeightReached: Float = 0.0
    public var score: Int = 0
    public var goldenAcornsCollected: Int = 0
    public var starsCollected: Int = 0
    
    /// Campaign context.
    public var isCampaign: Bool = true
    public var levelNumber: Int = 1
    public var targetLevelHeight: Float = 100.0
    
    /// Facing direction.
    public var isFacingRight: Bool = true
    
    /// Lifecycle flags.
    public var isAlive: Bool = true
    public var hasReachedFinish: Bool = false
    
    public init(
        isCampaign: Bool = true,
        levelNumber: Int = 1,
        targetLevelHeight: Float = 100.0
    ) {
        self.isCampaign = isCampaign
        self.levelNumber = levelNumber
        self.targetLevelHeight = targetLevelHeight
        self.velocity = SIMD2<Float>(0.0, 13.5) // Initial launch bounce
        self.previousY = 0.0
    }
}
