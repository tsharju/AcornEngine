import Foundation
import AcornEngine

/// The gameplay state of the board.
public enum BoardState: Sendable, Equatable {
    case idle
    case swapping(entityA: Entity, entityB: Entity, revert: Bool)
    case checkingMatches
    case clearingMatches
    case falling
    case gameOver
}

/// Represents the global board state in the ECS.
public struct BoardComponent: Component {
    /// Grid width (columns).
    public let width: Int = 8
    
    /// Grid height (rows).
    public let height: Int = 8
    
    /// 2D grid storing entities at each coordinate.
    /// Index is [x][y], where x = col, y = row. Row 0 is the bottom row.
    public var grid: [[Entity?]]
    
    /// Currently selected acorn for swapping.
    public var selectedAcorn: Entity? = nil
    
    /// The current player score.
    public var score: Int = 0
    
    /// Number of moves remaining.
    public var movesRemaining: Int = 20
    
    /// Target score to complete the level.
    public var targetScore: Int = 1000
    
    /// The current state of the board.
    public var state: BoardState = .idle
    
    /// Flag indicating whether the board is locked for input.
    public var isLocked: Bool {
        switch state {
        case .idle: return false
        default: return true
        }
    }
    
    /// Initializes an empty BoardComponent.
    public init() {
        self.grid = Array(repeating: Array(repeating: nil, count: 8), count: 8)
    }
}
