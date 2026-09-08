import Foundation
import simd

/// A representation of a Web Mercator slippy map tile coordinate (zoom, x, y).
public struct TileCoordinate: Hashable, Sendable, Codable {
    /// The tile zoom level.
    public var zoom: Int
    
    /// The tile X coordinate in the tile grid [0, 2^zoom - 1].
    public var x: Int
    
    /// The tile Y coordinate in the tile grid [0, 2^zoom - 1].
    public var y: Int
    
    /// Earth equatorial radius (WGS 84) in meters.
    public static let earthEquatorialRadius: Double = 6378137.0
    
    /// Earth equatorial circumference in meters (~40075016.68557849 m).
    public static let earthEquatorialCircumference: Double = 2.0 * .pi * earthEquatorialRadius
    
    /// Initializes a tile coordinate directly.
    public init(zoom: Int, x: Int, y: Int) {
        self.zoom = zoom
        self.x = x
        self.y = y
    }
    
    /// Initializes a tile coordinate from a GPS coordinate and target zoom level.
    public init(coordinate: GPSCoordinate, zoom: Int) {
        self.zoom = zoom
        let n = Double(1 << zoom)
        let lon = coordinate.longitude
        let lat = max(-85.05112878, min(85.05112878, coordinate.latitude))
        let latRad = lat * .pi / 180.0
        
        let tileX = Int(floor((lon + 180.0) / 360.0 * n))
        let tileY = Int(floor((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n))
        
        let maxIndex = (1 << zoom) - 1
        self.x = max(0, min(maxIndex, tileX))
        self.y = max(0, min(maxIndex, tileY))
    }
    
    /// Geographic bounding box of the tile in WGS84 degrees.
    public struct GPSBounds: Equatable, Sendable {
        public var north: Double
        public var south: Double
        public var west: Double
        public var east: Double
        
        public init(north: Double, south: Double, west: Double, east: Double) {
            self.north = north
            self.south = south
            self.west = west
            self.east = east
        }
    }
    
    /// Geographic bounds of this tile.
    public var bounds: GPSBounds {
        let n = Double(1 << zoom)
        let west = Double(x) / n * 360.0 - 180.0
        let east = Double(x + 1) / n * 360.0 - 180.0
        
        let northRad = atan(sinh(.pi * (1.0 - 2.0 * Double(y) / n)))
        let southRad = atan(sinh(.pi * (1.0 - 2.0 * Double(y + 1) / n)))
        
        let north = northRad * 180.0 / .pi
        let south = southRad * 180.0 / .pi
        
        return GPSBounds(north: north, south: south, west: west, east: east)
    }
    
    /// Center GPS coordinate of this tile.
    public var centerCoordinate: GPSCoordinate {
        let b = bounds
        let centerLat = (b.north + b.south) / 2.0
        let centerLon = (b.west + b.east) / 2.0
        return GPSCoordinate(latitude: centerLat, longitude: centerLon, altitude: 0.0)
    }
    
    /// Web Mercator nominal dimension in meters at this zoom level (unscaled by cos(latitude)).
    public var mercatorDimension: Double {
        Self.earthEquatorialCircumference / Double(1 << zoom)
    }
    
    /// Ground metric dimensions (width, height in meters) at a given reference latitude.
    /// Conformal Web Mercator scales ground meters by cos(latitude).
    public func groundDimensions(atLatitude latitude: Double) -> (width: Double, height: Double) {
        let latRad = latitude * .pi / 180.0
        let cosLat = max(0.0001, cos(latRad))
        let dim = mercatorDimension * cosLat
        return (dim, dim)
    }
    
    /// Ground metric dimensions at the tile's own center latitude.
    public var groundDimensions: (width: Double, height: Double) {
        groundDimensions(atLatitude: centerCoordinate.latitude)
    }
    
    /// Calculates the world position (in metric meters) of the tile's North-West corner
    /// relative to the given reference GPS coordinate.
    /// In AcornEngine space: +X is East, +Y is Up, -Z is North (so +Z is South).
    public func worldPosition(relativeTo referenceCoordinate: GPSCoordinate) -> SIMD3<Float> {
        let n = Double(1 << zoom)
        let refLon = referenceCoordinate.longitude
        let refLat = max(-85.05112878, min(85.05112878, referenceCoordinate.latitude))
        let refLatRad = refLat * .pi / 180.0
        
        let refXFrac = (refLon + 180.0) / 360.0 * n
        let refYFrac = (1.0 - log(tan(refLatRad) + 1.0 / cos(refLatRad)) / .pi) / 2.0 * n
        
        let deltaTileX = Double(x) - refXFrac
        let deltaTileY = Double(y) - refYFrac
        
        let (tileWidthMeters, tileHeightMeters) = groundDimensions(atLatitude: referenceCoordinate.latitude)
        
        let worldX = Float(deltaTileX * tileWidthMeters)
        let worldY = Float(0.0 - referenceCoordinate.altitude)
        let worldZ = Float(deltaTileY * tileHeightMeters)
        
        return SIMD3<Float>(worldX, worldY, worldZ)
    }
    
    /// Returns the neighboring tile coordinates within a Chebyshev distance radius.
    public func neighbors(radius: Int = 1) -> [TileCoordinate] {
        let maxIndex = (1 << zoom) - 1
        var result = [TileCoordinate]()
        for dy in -radius...radius {
            for dx in -radius...radius {
                let nx = x + dx
                let ny = y + dy
                if nx >= 0 && nx <= maxIndex && ny >= 0 && ny <= maxIndex {
                    result.append(TileCoordinate(zoom: zoom, x: nx, y: ny))
                }
            }
        }
        return result
    }
}
