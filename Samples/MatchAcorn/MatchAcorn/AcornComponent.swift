import Foundation
import simd
import AcornEngine

/// Represents an individual acorn entity on the board.
public struct AcornComponent: Component {
    /// The color of this acorn.
    public var color: AcornColor
    
    /// The current logical X coordinate (column) on the board (0-7).
    public var gridX: Int
    
    /// The current logical Y coordinate (row) on the board (0-7).
    public var gridY: Int
    
    /// The target X coordinate we are moving towards (if animating).
    public var targetGridX: Int
    
    /// The target Y coordinate we are moving towards (if animating).
    public var targetGridY: Int
    
    /// The interpolation progression factor between current position and target position (0.0 to 1.0).
    public var moveProgress: Float = 1.0
    
    /// Flag indicating this acorn has been matched and is scheduled for destruction.
    public var isMatched: Bool = false
    
    /// Scale factor for match/destruction animation (shrinks from 1.0 to 0.0).
    public var matchScale: Float = 1.0
    
    /// Initializes a new AcornComponent.
    public init(color: AcornColor, gridX: Int, gridY: Int) {
        self.color = color
        self.gridX = gridX
        self.gridY = gridY
        self.targetGridX = gridX
        self.targetGridY = gridY
    }
}
