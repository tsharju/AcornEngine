import Foundation
import simd

/// ECS component that identifies an entity as a hexagonal H3 map tile in the world.
///
/// An H3 tile corresponds to an H3 cell at a specific resolution and is assembled from one or more
/// geometry parts clipped from square slippy map tiles (`TileCoordinate`).
public struct H3TileComponent: Component, Sendable {
    /// Tile loading lifecycle state.
    public enum State: Sendable, Equatable {
        /// Waiting for source tiles or in progress of receiving clipped geometry pieces.
        case loading(loadedParts: Int, totalParts: Int)
        /// All required overlapping source tiles have been loaded and attached.
        case complete
        /// Failed to load or assemble the tile.
        case failed(String)
    }

    /// The H3 index identifying this hexagonal cell.
    public var h3Index: H3Index

    /// The slippy map zoom level used when requesting source tiles.
    public var sourceZoomLevel: Int

    /// The reference latitude in degrees used for metric scale calculations.
    public var referenceLatitude: Double

    /// The set of all square slippy tile coordinates that overlap this H3 cell.
    public var requiredSourceTiles: Set<TileCoordinate>

    /// The set of square slippy tile coordinates that have completed loading and contributed geometry.
    public var loadedSourceTiles: Set<TileCoordinate>

    /// The set of square slippy tile coordinates that failed to load.
    public var failedSourceTiles: Set<TileCoordinate>

    /// Child entity references for each loaded geometry part, keyed by source tile coordinate.
    public var geometryPartEntities: [TileCoordinate: Entity]

    /// Current loading state of this H3 tile.
    public var state: State

    /// Fraction of required source tiles currently loaded and attached [0.0 ... 1.0].
    public var coverageFraction: Double {
        guard !requiredSourceTiles.isEmpty else { return 1.0 }
        return Double(loadedSourceTiles.count) / Double(requiredSourceTiles.count)
    }

    /// Whether all required overlapping source tiles have contributed their clipped geometry or been handled.
    public var isComplete: Bool {
        !requiredSourceTiles.isEmpty && requiredSourceTiles.isSubset(of: loadedSourceTiles.union(failedSourceTiles))
    }

    /// Whether any required source tiles failed to load.
    public var hasFailures: Bool {
        !failedSourceTiles.isEmpty
    }

    /// Initializes a new H3 tile component.
    ///
    /// - Parameters:
    ///   - h3Index: The H3 cell index.
    ///   - sourceZoomLevel: Slippy zoom level for source tiles (default 15).
    ///   - referenceLatitude: Reference latitude for metric calculations.
    ///   - requiredSourceTiles: Pre-calculated or automatically computed set of overlapping source tiles.
    public init(
        h3Index: H3Index,
        sourceZoomLevel: Int = 15,
        referenceLatitude: Double = 0.0,
        requiredSourceTiles: Set<TileCoordinate>? = nil
    ) {
        self.h3Index = h3Index
        self.sourceZoomLevel = sourceZoomLevel
        self.referenceLatitude = referenceLatitude

        let required = requiredSourceTiles ?? Set(h3Index.overlappingTileCoordinates(zoom: sourceZoomLevel))
        self.requiredSourceTiles = required
        loadedSourceTiles = []
        failedSourceTiles = []
        geometryPartEntities = [:]
        state = .loading(loadedParts: 0, totalParts: required.count)
    }
}

/// ECS component attached to a child entity representing a single geometry piece
/// clipped from an overlapping square slippy map tile.
public struct H3TileGeometryPartComponent: Component, Sendable {
    /// The source slippy map tile coordinate this geometry was clipped from.
    public var sourceTile: TileCoordinate

    /// The parent H3 index this geometry piece belongs to.
    public var h3Index: H3Index

    /// The clipped 3D surface and 2D road mesh data for this piece.
    public var tileMeshData: TileMeshData

    /// Initializes a new H3 tile geometry part component.
    ///
    /// - Parameters:
    ///   - sourceTile: The source slippy map tile coordinate.
    ///   - h3Index: The parent H3 cell index.
    ///   - tileMeshData: The clipped tile mesh data.
    public init(
        sourceTile: TileCoordinate,
        h3Index: H3Index,
        tileMeshData: TileMeshData
    ) {
        self.sourceTile = sourceTile
        self.h3Index = h3Index
        self.tileMeshData = tileMeshData
    }
}
