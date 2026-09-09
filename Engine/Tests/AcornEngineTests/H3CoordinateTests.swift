@testable import AcornEngine
import Foundation
import simd
import Testing

struct H3CoordinateTests {
    @Test("H3Index initialization from GPS coordinate and resolution")
    func h3IndexInitialization() {
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let h3_res9 = H3Index(coordinate: helsinki, resolution: 9)

        #expect(h3_res9.resolution == 9)
        #expect(h3_res9.mode == 1)
        #expect(h3_res9.isValid)
        #expect(h3_res9.value != 0)

        let center = h3_res9.centerCoordinate
        // Center should be close to Helsinki (within ~174m cell radius)
        #expect(abs(center.latitude - helsinki.latitude) < 0.01)
        #expect(abs(center.longitude - helsinki.longitude) < 0.01)
    }

    @Test("H3Index hex string parsing and formatting round-trip")
    func h3HexString() {
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let h3 = H3Index(coordinate: helsinki, resolution: 8)

        let hexStr = h3.hexString
        #expect(!hexStr.isEmpty)
        #expect(hexStr.count == 16)

        // Parse back from string
        let parsed = H3Index(string: hexStr)
        #expect(parsed != nil)
        #expect(parsed?.value == h3.value)
        #expect(parsed?.resolution == 8)

        // Parse with 0x prefix
        let parsedWithPrefix = H3Index(string: "0x" + hexStr)
        #expect(parsedWithPrefix?.value == h3.value)
    }

    @Test("H3 hexagon boundary geometry consists of 6 vertices enclosing center")
    func h3BoundaryGeometry() {
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let h3 = H3Index(coordinate: helsinki, resolution: 9)

        let boundary = h3.boundaryCoordinates
        #expect(boundary.count == 6)

        let center = h3.centerCoordinate
        let expectedEdge = h3.edgeLengthMeters
        #expect(expectedEdge > 100.0 && expectedEdge < 250.0)

        // Each boundary vertex is approximately edgeLengthMeters from center in Web Mercator space,
        // and scaled by cos(latitude) in physical ground distance
        let cosLat = cos(center.latitude * .pi / 180.0)
        let expectedGroundEdge = expectedEdge * cosLat
        for pt in boundary {
            let latDiff = (pt.latitude - center.latitude) * .pi / 180.0 * TileCoordinate.earthEquatorialRadius
            let lonDiff = (pt.longitude - center.longitude) * .pi / 180.0 * TileCoordinate.earthEquatorialRadius * cosLat
            let dist = sqrt(latDiff * latDiff + lonDiff * lonDiff)
            #expect(abs(dist - expectedGroundEdge) < 2.0)
        }

        // World 3D boundary vertices (scaled by cos(latitude))
        let worldVertices = h3.boundaryPolygonWorld(relativeTo: helsinki)
        #expect(worldVertices.count == 6)
        let centerPos = h3.worldPosition(relativeTo: helsinki)
        for v in worldVertices {
            let dx = v.x - centerPos.x
            let dz = v.z - centerPos.z
            let dist = sqrt(dx * dx + dz * dz)
            #expect(abs(Double(dist) - expectedGroundEdge) < 0.5)
        }

        let world2D = h3.boundaryPolygon2D(relativeTo: helsinki)
        #expect(world2D.count == 6)
    }

    @Test("H3 boundary projection into slippy tile pixel extent space")
    func h3BoundaryTileProjection() {
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let h3 = H3Index(coordinate: helsinki, resolution: 9)
        let tile = TileCoordinate(coordinate: helsinki, zoom: 15)

        let tilePoly = h3.boundaryPolygonTile(for: tile, extent: 4096)
        #expect(tilePoly.count == 6)
        // At least one vertex should fall near or within the tile extent [0, 4096]
        let insideExtent = tilePoly.contains { $0.x >= -1000 && $0.x <= 5096 && $0.y >= -1000 && $0.y <= 5096 }
        #expect(insideExtent)
    }

    @Test("H3 neighbor traversal rings produce correct cell counts")
    func h3Neighbors() {
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let h3 = H3Index(coordinate: helsinki, resolution: 9)

        let ring0 = h3.neighbors(ring: 0)
        #expect(ring0 == [h3])

        let ring1 = h3.neighbors(ring: 1)
        #expect(ring1.count == 7) // center + 6 neighbors
        #expect(ring1.contains(h3))
        #expect(Set(ring1).count == 7) // all unique

        let ring2 = h3.neighbors(ring: 2)
        #expect(ring2.count == 19) // 1 + 6 + 12 = 19
        #expect(Set(ring2).count == 19)
    }

    @Test("H3 cell finds overlapping square slippy map tiles")
    func overlappingSlippyTiles() {
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let h3 = H3Index(coordinate: helsinki, resolution: 9)

        let overlappingTiles = h3.overlappingTileCoordinates(zoom: 15)
        #expect(!overlappingTiles.isEmpty)
        // A resolution 9 cell (~174m edge) typically intersects 1 to 4 zoom 15 tiles
        #expect(overlappingTiles.count >= 1 && overlappingTiles.count <= 6)

        let centerTile = TileCoordinate(coordinate: helsinki, zoom: 15)
        #expect(overlappingTiles.contains(centerTile))
    }

    @Test("Slippy tile finds overlapping H3 cells")
    func overlappingH3IndexesForTile() {
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let tile = TileCoordinate(coordinate: helsinki, zoom: 15)

        let overlappingH3s = H3Index.overlappingH3Indexes(for: tile, resolution: 9)
        #expect(!overlappingH3s.isEmpty)

        let centerH3 = H3Index(coordinate: tile.centerCoordinate, resolution: 9)
        #expect(overlappingH3s.contains(centerH3))
    }

    @Test("H3 boundary coordinates are clamped and normalized at antimeridian and high latitudes")
    func boundaryAntimeridianAndPolarClamping() {
        // Cell right at 179.999° longitude
        let antimeridianCoord = GPSCoordinate(latitude: 0.0, longitude: 179.999)
        let h3Anti = H3Index(coordinate: antimeridianCoord, resolution: 8)
        let antiBounds = h3Anti.boundaryCoordinates
        #expect(antiBounds.count == 6)
        for pt in antiBounds {
            #expect(pt.longitude >= -180.0 && pt.longitude <= 180.0)
            #expect(pt.latitude >= -85.05112878 && pt.latitude <= 85.05112878)
        }

        // Cell near north limit 85.0°
        let polarCoord = GPSCoordinate(latitude: 84.99, longitude: 0.0)
        let h3Polar = H3Index(coordinate: polarCoord, resolution: 8)
        let polarBounds = h3Polar.boundaryCoordinates
        #expect(polarBounds.count == 6)
        for pt in polarBounds {
            #expect(pt.latitude >= -85.05112878 && pt.latitude <= 85.05112878)
        }
    }

    @Test("Adjacent H3 cells share exact GPS vertices along shared edges without gaps or overlapping")
    func adjacentCellsShareGPSVertices() {
        let locations = [
            GPSCoordinate(latitude: 60.1699, longitude: 24.9384), // Helsinki (60° N)
            GPSCoordinate(latitude: 0.0, longitude: 10.0), // Equator (0°)
            GPSCoordinate(latitude: 35.6762, longitude: 139.6503), // Tokyo (35° N)
            GPSCoordinate(latitude: -33.8688, longitude: 151.2093), // Sydney (-33° S)
        ]

        for loc in locations {
            for res in [7, 8, 9] {
                let centerH3 = H3Index(coordinate: loc, resolution: res)
                let neighbors = centerH3.neighbors(ring: 1).filter { $0 != centerH3 }
                #expect(neighbors.count == 6)

                let centerBoundary = centerH3.boundaryCoordinates
                #expect(centerBoundary.count == 6)

                for neighbor in neighbors {
                    let neighborBoundary = neighbor.boundaryCoordinates
                    #expect(neighborBoundary.count == 6)

                    // Count how many vertices match between center and neighbor
                    var sharedCount = 0
                    for cPt in centerBoundary {
                        for nPt in neighborBoundary {
                            let dLat = abs(cPt.latitude - nPt.latitude)
                            let dLon = abs(cPt.longitude - nPt.longitude)
                            if dLat < 1e-7, dLon < 1e-7 {
                                sharedCount += 1
                            }
                        }
                    }

                    // Adjacent hexagonal cells must share exactly 2 vertices (1 shared edge)
                    #expect(sharedCount == 2)
                }
            }
        }
    }

    @Test("Adjacent H3 cells in engine world space share vertices and do not overlap")
    func adjacentCellsWorldSpaceTessellation() {
        let locations = [
            GPSCoordinate(latitude: 60.1699, longitude: 24.9384), // Helsinki (60° N)
            GPSCoordinate(latitude: 0.0, longitude: 10.0), // Equator (0°)
            GPSCoordinate(latitude: 35.6762, longitude: 139.6503), // Tokyo (35° N)
            GPSCoordinate(latitude: -33.8688, longitude: 151.2093), // Sydney (-33° S)
        ]

        for loc in locations {
            for res in [8, 9] {
                let centerH3 = H3Index(coordinate: loc, resolution: res)
                let neighbors = centerH3.neighbors(ring: 1).filter { $0 != centerH3 }

                let centerWorld = centerH3.boundaryPolygonWorld(relativeTo: loc)
                let centerPos = centerH3.worldPosition(relativeTo: loc)
                let cosLat = cos(loc.latitude * .pi / 180.0)
                let expectedRadius = centerH3.edgeLengthMeters * cosLat
                let expectedCenterDist = sqrt(3.0) * expectedRadius

                for neighbor in neighbors {
                    let neighborWorld = neighbor.boundaryPolygonWorld(relativeTo: loc)
                    let neighborPos = neighbor.worldPosition(relativeTo: loc)

                    // 1. Center-to-center distance must match regular hexagon packing: sqrt(3) * radius
                    let dCenter = simd_distance(SIMD2<Float>(centerPos.x, centerPos.z), SIMD2<Float>(neighborPos.x, neighborPos.z))
                    #expect(abs(Double(dCenter) - expectedCenterDist) < 2.0)

                    // 2. Exactly 2 shared vertices in world space
                    var sharedCount = 0
                    for cV in centerWorld {
                        for nV in neighborWorld {
                            let d = simd_distance(SIMD2<Float>(cV.x, cV.z), SIMD2<Float>(nV.x, nV.z))
                            if d < 0.2 {
                                sharedCount += 1
                            }
                        }
                    }
                    #expect(sharedCount == 2)

                    // 3. No overlap: neighbor center must be outside center hexagon (distance >= 2 * inradius)
                    // Hexagon inradius is sqrt(3)/2 * radius. Two touching hexagons have center distance 2 * inradius = sqrt(3) * radius.
                    let inradius = Float(sqrt(3.0) / 2.0 * expectedRadius)
                    #expect(dCenter >= 2.0 * inradius - 0.2)

                    // Every vertex of neighbor must be at or outside the inradius of the center cell
                    for nV in neighborWorld {
                        let dToCenter = simd_distance(SIMD2<Float>(nV.x, nV.z), SIMD2<Float>(centerPos.x, centerPos.z))
                        #expect(dToCenter >= inradius - 0.2)
                    }
                }
            }
        }
    }

    @Test("Ring 2 multi-cell tessellation covers area without overlaps")
    func ring2TessellationCoverage() {
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let centerH3 = H3Index(coordinate: helsinki, resolution: 9)
        let allCells = centerH3.neighbors(ring: 2)
        #expect(allCells.count == 19)

        let cosLat = cos(helsinki.latitude * .pi / 180.0)
        let radius = centerH3.edgeLengthMeters * cosLat
        let minCenterDist = sqrt(3.0) * radius - 0.5 // minimum distance between any distinct cells

        // Verify distinct cells never have overlapping centers
        for i in 0 ..< allCells.count {
            let posA = allCells[i].worldPosition(relativeTo: helsinki)
            for j in (i + 1) ..< allCells.count {
                let posB = allCells[j].worldPosition(relativeTo: helsinki)
                let d = simd_distance(SIMD2<Float>(posA.x, posA.z), SIMD2<Float>(posB.x, posB.z))
                #expect(Double(d) >= minCenterDist)
            }
        }
    }

    @Test("Adjacent cells polygon interior non-overlap and mutual edge sharing")
    func adjacentCellsPolygonInteriorNonOverlap() {
        let locations = [
            GPSCoordinate(latitude: 60.1699, longitude: 24.9384), // Helsinki (60° N)
            GPSCoordinate(latitude: 0.0, longitude: 10.0), // Equator (0°)
            GPSCoordinate(latitude: 35.6762, longitude: 139.6503), // Tokyo (35° N)
        ]

        for loc in locations {
            let centerH3 = H3Index(coordinate: loc, resolution: 9)
            let neighbors = centerH3.neighbors(ring: 1).filter { $0 != centerH3 }

            let centerPoly2D = centerH3.boundaryPolygon2D(relativeTo: loc)
            let centerPolyDouble = centerPoly2D.map { SIMD2<Double>(Double($0.x), Double($0.y)) }

            for neighbor in neighbors {
                let neighborPoly2D = neighbor.boundaryPolygon2D(relativeTo: loc)
                let neighborPos = neighbor.worldPosition(relativeTo: loc)
                let neighborCenter2D = SIMD2<Double>(Double(neighborPos.x), Double(neighborPos.z))

                // Check edge midpoints of neighbor:
                // When inset slightly (0.999x), edge midpoints must be strictly outside center cell.
                // When expanded slightly (1.02x), the shared edge midpoint must cross into the center cell.
                var insetInside = false
                var expandedInside = false

                for i in 0 ..< neighborPoly2D.count {
                    let p1 = SIMD2<Double>(Double(neighborPoly2D[i].x), Double(neighborPoly2D[i].y))
                    let p2 = SIMD2<Double>(Double(neighborPoly2D[(i + 1) % neighborPoly2D.count].x), Double(neighborPoly2D[(i + 1) % neighborPoly2D.count].y))
                    let mid = (p1 + p2) * 0.5

                    let insetMid = neighborCenter2D + (mid - neighborCenter2D) * 0.999
                    if pointInPolygon(point: insetMid, polygon: centerPolyDouble) {
                        insetInside = true
                    }

                    let expMid = neighborCenter2D + (mid - neighborCenter2D) * 1.02
                    if pointInPolygon(point: expMid, polygon: centerPolyDouble) {
                        expandedInside = true
                    }
                }

                #expect(!insetInside)
                #expect(expandedInside)
            }
        }
    }
}
