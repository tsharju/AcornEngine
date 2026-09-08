import Foundation

/// ECS component that identifies an entity as a map tile in the world.
public struct MapTileComponent: Component {
    /// Tile state in the loading lifecycle.
    public enum State: Sendable, Equatable {
        case loading
        case loaded
        case failed(String)
    }
    
    /// The tile's slippy coordinate (zoom, x, y).
    public var coordinate: TileCoordinate
    
    /// The reference latitude in degrees used when computing metric scaling.
    public var referenceLatitude: Double
    
    /// The ground dimensions (width, height in meters) of this tile.
    public var groundDimensions: (width: Double, height: Double)
    
    /// Current loading/meshing state of the tile.
    public var state: State
    
    /// Initializes a new map tile component.
    /// - Parameters:
    ///   - coordinate: Slippy tile coordinate.
    ///   - referenceLatitude: Reference latitude used for metric scaling.
    ///   - groundDimensions: Tile width and height in meters.
    ///   - state: Initial loading state.
    public init(
        coordinate: TileCoordinate,
        referenceLatitude: Double,
        groundDimensions: (width: Double, height: Double),
        state: State = .loaded
    ) {
        self.coordinate = coordinate
        self.referenceLatitude = referenceLatitude
        self.groundDimensions = groundDimensions
        self.state = state
    }
}
