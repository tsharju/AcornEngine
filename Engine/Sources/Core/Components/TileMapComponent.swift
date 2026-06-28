import Foundation
import simd

/// A component that renders a 2D tile map using a SpriteSheet.
public struct TileMapComponent: Component {
    /// The sprite sheet used for the tiles.
    public var spriteSheet: SpriteSheet
    
    /// The number of tiles horizontally.
    public var columns: Int
    
    /// The number of tiles vertically.
    public var rows: Int
    
    /// The size of each tile in world units.
    public var tileSize: SIMD2<Float>
    
    /// A 1D array of tile frame names (row-major order). An empty string means no tile.
    public var tiles: [String]
    
    /// An optional color tint applied to the entire tile map.
    public var color: SIMD4<Float>
    
    /// The internally cached mesh representing the entire tile map.
    public var mesh: (any Mesh)?
    
    /// A flag indicating whether the mesh needs to be rebuilt.
    public var isDirty: Bool = true
    
    /// Initializes a new TileMapComponent.
    /// - Parameters:
    ///   - spriteSheet: The sprite sheet to use.
    ///   - columns: The width of the map in tiles.
    ///   - rows: The height of the map in tiles.
    ///   - tileSize: The dimensions of a single tile in world space.
    ///   - tiles: The tile data (row-major order). Empty strings represent empty space.
    ///   - color: A global color tint for the tile map.
    public init(spriteSheet: SpriteSheet, columns: Int, rows: Int, tileSize: SIMD2<Float>, tiles: [String], color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)) {
        self.spriteSheet = spriteSheet
        self.columns = columns
        self.rows = rows
        self.tileSize = tileSize
        self.tiles = tiles
        self.color = color
    }
    
    /// Updates a tile at the given coordinates.
    /// - Parameters:
    ///   - column: The column index.
    ///   - row: The row index.
    ///   - frameName: The new frame name, or empty string to remove.
    public mutating func setTile(column: Int, row: Int, frameName: String) {
        guard column >= 0, column < columns, row >= 0, row < rows else { return }
        let index = row * columns + column
        if tiles[index] != frameName {
            tiles[index] = frameName
            isDirty = true
        }
    }
}
