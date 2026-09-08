import Testing
import simd
import Foundation
@testable import AcornEngine

struct TileCoordinateTests {
    @Test("Tile coordinate conversion from GPS and bounds enclosure")
    func testTileCoordinateConversions() {
        // Helsinki coordinates
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let zoom = 15
        let tile = TileCoordinate(coordinate: helsinki, zoom: zoom)
        
        let bounds = tile.bounds
        #expect(bounds.north >= bounds.south)
        #expect(bounds.east >= bounds.west)
        
        // The coordinate must lie strictly within the calculated tile bounds
        #expect(helsinki.latitude <= bounds.north)
        #expect(helsinki.latitude >= bounds.south)
        #expect(helsinki.longitude >= bounds.west)
        #expect(helsinki.longitude <= bounds.east)
        
        // Center coordinate must lie inside bounds
        let center = tile.centerCoordinate
        #expect(center.latitude <= bounds.north && center.latitude >= bounds.south)
        #expect(center.longitude >= bounds.west && center.longitude <= bounds.east)
    }
    
    @Test("Metric latitude scale distortion (cos latitude)")
    func testMetricLatitudeScaling() {
        let zoom = 15
        let equatorTile = TileCoordinate(zoom: zoom, x: 0, y: 0)
        
        // At equator (0 degrees lat), cos(0) = 1
        let (eqWidth, eqHeight) = equatorTile.groundDimensions(atLatitude: 0.0)
        #expect(abs(eqWidth - equatorTile.mercatorDimension) < 0.001)
        #expect(abs(eqHeight - equatorTile.mercatorDimension) < 0.001)
        
        // At 60 degrees latitude, cos(60 deg) = 0.5
        let (helsinkiWidth, helsinkiHeight) = equatorTile.groundDimensions(atLatitude: 60.0)
        let expectedHelsinkiWidth = equatorTile.mercatorDimension * cos(60.0 * .pi / 180.0)
        #expect(abs(helsinkiWidth - expectedHelsinkiWidth) < 0.001)
        #expect(abs(helsinkiHeight - expectedHelsinkiWidth) < 0.001)
        
        // Ground width at 60 deg must be approximately half the equator width
        let ratio = helsinkiWidth / eqWidth
        #expect(abs(ratio - 0.5) < 0.001)
    }
    
    @Test("World position mapping and orientation (+X East, +Y Up, -Z North)")
    func testWorldPositionMapping() {
        let reference = GPSCoordinate(latitude: 60.1699, longitude: 24.9384, altitude: 0.0)
        let zoom = 15
        let currentTile = TileCoordinate(coordinate: reference, zoom: zoom)
        
        let tileWorldPos = currentTile.worldPosition(relativeTo: reference)
        let (tileW, tileH) = currentTile.groundDimensions(atLatitude: reference.latitude)
        
        // The tile's NW corner should be to the West (worldX <= 0) and North (worldZ <= 0)
        // of the reference point inside this tile
        #expect(tileWorldPos.x <= 0.0)
        #expect(tileWorldPos.x > -Float(tileW))
        #expect(tileWorldPos.z <= 0.0)
        #expect(tileWorldPos.z > -Float(tileH))
        #expect(abs(tileWorldPos.y) < 0.001)
    }
    
    @Test("Tile grid seamless continuity between adjacent tiles")
    func testTileGridContinuity() {
        let reference = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let zoom = 15
        let baseTile = TileCoordinate(coordinate: reference, zoom: zoom)
        let eastTile = TileCoordinate(zoom: zoom, x: baseTile.x + 1, y: baseTile.y)
        let southTile = TileCoordinate(zoom: zoom, x: baseTile.x, y: baseTile.y + 1)
        
        let basePos = baseTile.worldPosition(relativeTo: reference)
        let eastPos = eastTile.worldPosition(relativeTo: reference)
        let southPos = southTile.worldPosition(relativeTo: reference)
        
        let (tileW, tileH) = baseTile.groundDimensions(atLatitude: reference.latitude)
        
        // East neighbor must be offset by exactly tileW along +X
        let dx = eastPos.x - basePos.x
        #expect(abs(dx - Float(tileW)) < 0.01)
        #expect(abs(eastPos.z - basePos.z) < 0.01)
        
        // South neighbor must be offset by exactly tileH along +Z
        let dz = southPos.z - basePos.z
        #expect(abs(dz - Float(tileH)) < 0.01)
        #expect(abs(southPos.x - basePos.x) < 0.01)
    }
    
    @Test("Neighbor tile querying and grid boundaries")
    func testNeighbors() {
        let center = TileCoordinate(zoom: 15, x: 100, y: 200)
        let n1 = center.neighbors(radius: 1)
        #expect(n1.count == 9) // 3x3 grid
        #expect(n1.contains(center))
        #expect(n1.contains(TileCoordinate(zoom: 15, x: 99, y: 199)))
        #expect(n1.contains(TileCoordinate(zoom: 15, x: 101, y: 201)))
        
        // Corner tile at grid edge (x=0, y=0)
        let corner = TileCoordinate(zoom: 15, x: 0, y: 0)
        let cornerNeighbors = corner.neighbors(radius: 1)
        #expect(cornerNeighbors.count == 4) // (0,0), (1,0), (0,1), (1,1)
    }
}
