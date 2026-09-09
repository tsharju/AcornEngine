import Foundation
import simd

/// A 64-bit identifier representing a hexagonal cell in the H3 geospatial indexing system.
///
/// Each `H3Index` represents a regular hexagonal cell at a specific hierarchical resolution (0–15).
/// It provides methods to compute the cell's geographic center, 6-vertex boundary polygon,
/// metric world-space geometry, neighbor rings, and overlap relationships with square slippy map tiles.
public struct H3Index: Hashable, Sendable, Codable, CustomStringConvertible, Comparable {
    /// The raw 64-bit integer representation of the H3 index.
    public let value: UInt64

    // MARK: - Constants

    /// H3 mode for a hexagonal cell (mode 1).
    public static let modeCell: UInt64 = 1

    /// Nominal average hexagon edge lengths in meters for resolutions 0 through 15.
    public static let averageEdgeLengthsMeters: [Double] = [
        1_107_712.59, // Res 0
        418_676.00, // Res 1
        158_244.00, // Res 2
        59810.00, // Res 3
        22606.00, // Res 4
        8544.00, // Res 5
        3229.00, // Res 6
        1220.00, // Res 7
        461.35, // Res 8
        174.38, // Res 9
        65.91, // Res 10
        24.91, // Res 11
        9.42, // Res 12
        3.56, // Res 13
        1.35, // Res 14
        0.51, // Res 15
    ]

    /// Nominal hexagon areas in square meters for resolutions 0 through 15.
    public static let averageAreasMetersSquared: [Double] = [
        4.357e12, // Res 0
        6.224e11, // Res 1
        8.892e10, // Res 2
        1.270e10, // Res 3
        1.815e9, // Res 4
        2.592e8, // Res 5
        3.704e7, // Res 6
        5.291e6, // Res 7
        7.559e5, // Res 8
        1.079e5, // Res 9
        1.542e4, // Res 10
        2.204e3, // Res 11
        3.149e2, // Res 12
        4.499e1, // Res 13
        6.427e0, // Res 14
        0.918e0, // Res 15
    ]

    private static let coordinateOffset: Int64 = 1 << 24

    // MARK: - Initializers

    /// Initializes an H3 index from a raw 64-bit integer.
    public init(value: UInt64) {
        self.value = value
    }

    /// Initializes an H3 index from a hexadecimal string (with or without `0x` prefix).
    public init?(string: String) {
        var clean = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.hasPrefix("0x") {
            clean = String(clean.dropFirst(2))
        }
        guard let val = UInt64(clean, radix: 16) else {
            return nil
        }
        value = val
    }

    /// Initializes an H3 index by indexing a GPS coordinate at the specified resolution (0–15).
    ///
    /// - Parameters:
    ///   - coordinate: The geographic coordinate to index.
    ///   - resolution: The H3 resolution level, clamped to `0...15`.
    public init(coordinate: GPSCoordinate, resolution: Int) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude, resolution: resolution)
    }

    /// Initializes an H3 index from latitude, longitude, and resolution.
    ///
    /// - Parameters:
    ///   - latitude: Latitude in degrees [-90.0, 90.0].
    ///   - longitude: Longitude in degrees [-180.0, 180.0].
    ///   - resolution: The H3 resolution level, clamped to `0...15`.
    public init(latitude: Double, longitude: Double, resolution: Int) {
        let res = max(0, min(15, resolution))
        let clampedLat = max(-85.05112878, min(85.05112878, latitude))
        let normLon = ((longitude + 180.0).truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0) - 180.0

        let edgeLength = Self.averageEdgeLengthsMeters[res]

        // Project to local metric coordinates on conformal Mercator sphere
        let latRad = clampedLat * .pi / 180.0
        let lonRad = normLon * .pi / 180.0
        let x = TileCoordinate.earthEquatorialRadius * lonRad
        let z = -TileCoordinate.earthEquatorialRadius * log(tan(.pi / 4.0 + latRad / 2.0))

        // Axial flat-topped hexagonal grid projection:
        // Width between columns = 1.5 * edgeLength
        // Height between rows = sqrt(3) * edgeLength
        let qFrac = (2.0 / 3.0 * x) / edgeLength
        let rFrac = (-1.0 / 3.0 * x + sqrt(3.0) / 3.0 * z) / edgeLength

        // Cube rounding
        let xCube = qFrac
        let zCube = rFrac
        let yCube = -xCube - zCube

        var rx = round(xCube)
        var ry = round(yCube)
        var rz = round(zCube)

        let xDiff = abs(rx - xCube)
        let yDiff = abs(ry - yCube)
        let zDiff = abs(rz - zCube)

        if xDiff > yDiff, xDiff > zDiff {
            rx = -ry - rz
        } else if yDiff > zDiff {
            ry = -rx - rz
        } else {
            rz = -rx - ry
        }

        let qInt = Int64(rx)
        let rInt = Int64(rz)

        // Pack into 64-bit H3Index structure
        let offsetQ = UInt64(bitPattern: qInt + Self.coordinateOffset) & 0x01FF_FFFF
        let offsetR = UInt64(bitPattern: rInt + Self.coordinateOffset) & 0x01FF_FFFF

        var val: UInt64 = 0
        // Mode 1 (cell): bits 59-62
        val |= (Self.modeCell & 0xF) << 59
        // Resolution: bits 52-55
        val |= (UInt64(res) & 0xF) << 52
        // Packed axial coords in remaining payload
        val |= (offsetQ << 25)
        val |= offsetR

        value = val
    }

    // MARK: - Properties

    /// The resolution level of this H3 cell (0–15).
    public var resolution: Int {
        Int((value >> 52) & 0xF)
    }

    /// The H3 index mode (mode 1 indicates a regular cell).
    public var mode: Int {
        Int((value >> 59) & 0xF)
    }

    /// Whether this index has a valid cell mode and resolution.
    public var isValid: Bool {
        mode == 1 && resolution <= 15
    }

    /// Hexadecimal string representation in standard lowercase format.
    public var hexString: String {
        String(format: "%016llx", value)
    }

    /// CustomStringConvertible description.
    public var description: String {
        hexString
    }

    /// Average hexagon edge length in meters at this cell's resolution.
    public var edgeLengthMeters: Double {
        let res = max(0, min(15, resolution))
        return Self.averageEdgeLengthsMeters[res]
    }

    /// Average hexagon area in square meters at this cell's resolution.
    public var areaMetersSquared: Double {
        let res = max(0, min(15, resolution))
        return Self.averageAreasMetersSquared[res]
    }

    /// Decoded axial coordinate `q` in the hexagonal grid.
    public var axialQ: Int64 {
        let rawQ = (value >> 25) & 0x01FF_FFFF
        return Int64(rawQ) - Self.coordinateOffset
    }

    /// Decoded axial coordinate `r` in the hexagonal grid.
    public var axialR: Int64 {
        let rawR = value & 0x01FF_FFFF
        return Int64(rawR) - Self.coordinateOffset
    }

    /// The geographic center of this H3 cell.
    public var centerCoordinate: GPSCoordinate {
        let res = resolution
        let edgeLength = Self.averageEdgeLengthsMeters[res]
        let q = Double(axialQ)
        let r = Double(axialR)

        let x = edgeLength * (3.0 / 2.0 * q)
        let z = edgeLength * (sqrt(3.0) / 2.0 * q + sqrt(3.0) * r)

        let lonRad = x / TileCoordinate.earthEquatorialRadius
        let lon = lonRad * 180.0 / .pi

        let mercatorY = -z / TileCoordinate.earthEquatorialRadius
        let latRad = 2.0 * atan(exp(mercatorY)) - .pi / 2.0
        let lat = latRad * 180.0 / .pi

        let normLon = ((lon + 180.0).truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0) - 180.0
        return GPSCoordinate(latitude: lat, longitude: normLon, altitude: 0.0)
    }

    /// The 6 boundary vertices of this H3 hexagonal cell in geographic GPS coordinates (CCW order).
    public var boundaryCoordinates: [GPSCoordinate] {
        let res = resolution
        let edgeLength = Self.averageEdgeLengthsMeters[res]
        let q = Double(axialQ)
        let r = Double(axialR)

        let cx = edgeLength * (3.0 / 2.0 * q)
        let cz = edgeLength * (sqrt(3.0) / 2.0 * q + sqrt(3.0) * r)

        var coords = [GPSCoordinate]()
        coords.reserveCapacity(6)

        for i in 0 ..< 6 {
            let angle = Double(i) * (.pi / 3.0)
            let vx = cx + edgeLength * cos(angle)
            let vz = cz + edgeLength * sin(angle)

            let lonRad = vx / TileCoordinate.earthEquatorialRadius
            let lon = lonRad * 180.0 / .pi

            let mercatorY = -vz / TileCoordinate.earthEquatorialRadius
            let latRad = 2.0 * atan(exp(mercatorY)) - .pi / 2.0
            let lat = latRad * 180.0 / .pi

            let clampedLat = max(-85.05112878, min(85.05112878, lat))
            let normLon = ((lon + 180.0).truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0) - 180.0

            coords.append(GPSCoordinate(
                latitude: clampedLat,
                longitude: normLon,
                altitude: 0.0
            ))
        }

        return coords
    }

    // MARK: - Geometric & Engine Operations

    /// Computes the 3D world position of the cell's center relative to the game's reference GPS coordinate.
    /// In AcornEngine space: +X is East, +Y is Up, -Z is North.
    public func worldPosition(relativeTo referenceCoordinate: GPSCoordinate) -> SIMD3<Float> {
        let center = centerCoordinate
        let latRad = referenceCoordinate.latitude * .pi / 180.0
        let cosLat = max(0.001, cos(latRad))

        let dLon = (center.longitude - referenceCoordinate.longitude) * .pi / 180.0
        let dLat = (center.latitude - referenceCoordinate.latitude) * .pi / 180.0

        let worldX = Float(dLon * TileCoordinate.earthEquatorialRadius * cosLat)
        let worldY: Float = 0.0
        let worldZ = Float(-dLat * TileCoordinate.earthEquatorialRadius)

        return SIMD3<Float>(worldX, worldY, worldZ)
    }

    /// Computes the 6 boundary vertices in 3D engine world space relative to the game's reference GPS coordinate.
    public func boundaryPolygonWorld(relativeTo referenceCoordinate: GPSCoordinate) -> [SIMD3<Float>] {
        let centerPos = worldPosition(relativeTo: referenceCoordinate)
        let latRad = referenceCoordinate.latitude * .pi / 180.0
        let cosLat = Float(max(0.001, cos(latRad)))
        let r = Float(edgeLengthMeters) * cosLat

        var vertices = [SIMD3<Float>]()
        vertices.reserveCapacity(6)
        for i in 0 ..< 6 {
            let angle = Float(i) * (.pi / 3.0)
            let dx = r * cos(angle)
            let dz = r * sin(angle)
            vertices.append(SIMD3<Float>(centerPos.x + dx, centerPos.y, centerPos.z + dz))
        }
        return vertices
    }

    /// Computes the 2D ground plane vertices (X = East, Y = South/Z) in engine metric space.
    public func boundaryPolygon2D(relativeTo referenceCoordinate: GPSCoordinate) -> [SIMD2<Float>] {
        let w3 = boundaryPolygonWorld(relativeTo: referenceCoordinate)
        return w3.map { SIMD2<Float>($0.x, $0.z) }
    }

    /// Converts the hexagon boundary vertices into the integer/double coordinate space `[0, extent] x [0, extent]`
    /// of a specific square slippy tile.
    public func boundaryPolygonTile(for tile: TileCoordinate, extent: Int = 4096) -> [SIMD2<Float>] {
        let edgeLength = edgeLengthMeters
        let q = Double(axialQ)
        let r = Double(axialR)
        let cx = edgeLength * (3.0 / 2.0 * q)
        let cz = edgeLength * (sqrt(3.0) / 2.0 * q + sqrt(3.0) * r)

        let tileMercator = tile.mercatorDimension
        let halfCircumference = TileCoordinate.earthEquatorialCircumference / 2.0
        let tileNwX = Double(tile.x) * tileMercator - halfCircumference
        let tileNwZ = Double(tile.y) * tileMercator - halfCircumference
        let numTiles = Double(1 << tile.zoom)

        var tilePoints = [SIMD2<Float>]()
        tilePoints.reserveCapacity(6)

        for i in 0 ..< 6 {
            let angle = Double(i) * (.pi / 3.0)
            let vx = cx + edgeLength * cos(angle)
            let vz = cz + edgeLength * sin(angle)

            var xFrac = (vx - tileNwX) / tileMercator
            let yFrac = (vz - tileNwZ) / tileMercator

            if xFrac < -numTiles / 2.0 {
                xFrac += numTiles
            } else if xFrac > numTiles / 2.0 {
                xFrac -= numTiles
            }

            tilePoints.append(SIMD2<Float>(
                Float(xFrac * Double(extent)),
                Float(yFrac * Double(extent))
            ))
        }
        return tilePoints
    }

    // MARK: - Neighbors & Traversal

    /// Computes neighboring H3 cell indices in concentric hexagonal rings.
    ///
    /// - Parameter ring: Radius of the ring (`k`). Radius 0 returns `[self]`. Radius 1 returns 7 cells (self + 6 neighbors).
    /// - Returns: List of unique H3 indices in the neighbor rings.
    public func neighbors(ring: Int = 1) -> [H3Index] {
        guard ring > 0 else { return [self] }
        let res = resolution
        let q = axialQ
        let r = axialR

        var results = Set<H3Index>()
        results.insert(self)

        for k in 1 ... ring {
            // Hexagonal axial ring traversal
            // 6 directions in axial coordinates
            let directions: [(Int64, Int64)] = [
                (1, 0), (1, -1), (0, -1),
                (-1, 0), (-1, 1), (0, 1),
            ]

            // Start at corner of ring k: (q + k, r - k) or similar
            var curQ = q + Int64(k) * directions[4].0
            var curR = r + Int64(k) * directions[4].1

            for side in 0 ..< 6 {
                for _ in 0 ..< k {
                    let offsetQ = UInt64(bitPattern: curQ + Self.coordinateOffset) & 0x01FF_FFFF
                    let offsetR = UInt64(bitPattern: curR + Self.coordinateOffset) & 0x01FF_FFFF

                    var val: UInt64 = 0
                    val |= (Self.modeCell & 0xF) << 59
                    val |= (UInt64(res) & 0xF) << 52
                    val |= (offsetQ << 25)
                    val |= offsetR
                    results.insert(H3Index(value: val))

                    curQ += directions[side].0
                    curR += directions[side].1
                }
            }
        }

        return Array(results)
    }

    /// Alias for `neighbors(ring:)` following standard H3 terminology.
    public func kRing(radius: Int = 1) -> [H3Index] {
        neighbors(ring: radius)
    }

    // MARK: - Overlap with Slippy Map Tiles

    /// Finds all square slippy map tile coordinates at the specified zoom level that overlap this H3 cell.
    ///
    /// - Parameter zoom: Slippy tile zoom level (e.g. 15 or 16).
    /// - Returns: List of overlapping `TileCoordinate` values.
    public func overlappingTileCoordinates(zoom: Int) -> [TileCoordinate] {
        let clampedZoom = max(0, min(24, zoom))
        let b = boundaryCoordinates
        guard !b.isEmpty else { return [] }

        var minLat = b[0].latitude
        var maxLat = b[0].latitude
        var minLon = b[0].longitude
        var maxLon = b[0].longitude

        for pt in b {
            minLat = min(minLat, pt.latitude)
            maxLat = max(maxLat, pt.latitude)
            minLon = min(minLon, pt.longitude)
            maxLon = max(maxLon, pt.longitude)
        }

        let nw = TileCoordinate(coordinate: GPSCoordinate(latitude: maxLat, longitude: minLon), zoom: clampedZoom)
        let se = TileCoordinate(coordinate: GPSCoordinate(latitude: minLat, longitude: maxLon), zoom: clampedZoom)

        var result = [TileCoordinate]()
        let minTileX = min(nw.x, se.x)
        let maxTileX = max(nw.x, se.x)
        let minTileY = min(nw.y, se.y)
        let maxTileY = max(nw.y, se.y)

        let hexPolygon = b.map { SIMD2<Double>($0.longitude, $0.latitude) }

        for ty in minTileY ... maxTileY {
            for tx in minTileX ... maxTileX {
                let tile = TileCoordinate(zoom: clampedZoom, x: tx, y: ty)
                let tb = tile.bounds
                let tilePoly: [SIMD2<Double>] = [
                    SIMD2<Double>(tb.west, tb.north),
                    SIMD2<Double>(tb.east, tb.north),
                    SIMD2<Double>(tb.east, tb.south),
                    SIMD2<Double>(tb.west, tb.south),
                ]

                if polygonsIntersect(polyA: hexPolygon, polyB: tilePoly) {
                    result.append(tile)
                }
            }
        }

        return result
    }

    /// Finds all H3 cells at the given resolution that overlap a square slippy map tile.
    ///
    /// - Parameters:
    ///   - tile: The slippy tile coordinate.
    ///   - resolution: The target H3 resolution.
    /// - Returns: List of overlapping `H3Index` values.
    public static func overlappingH3Indexes(for tile: TileCoordinate, resolution: Int) -> [H3Index] {
        let res = max(0, min(15, resolution))
        let tb = tile.bounds
        let centerGPS = tile.centerCoordinate
        let centerH3 = H3Index(coordinate: centerGPS, resolution: res)

        // Estimate radius needed in H3 cells based on tile metric size vs hex edge length in Web Mercator space
        let tileMercator = tile.mercatorDimension
        let hexEdge = Self.averageEdgeLengthsMeters[res]
        let ringRadius = max(1, Int(ceil(tileMercator / (hexEdge * 1.2))))

        let candidates = centerH3.neighbors(ring: ringRadius)
        let tilePoly: [SIMD2<Double>] = [
            SIMD2<Double>(tb.west, tb.north),
            SIMD2<Double>(tb.east, tb.north),
            SIMD2<Double>(tb.east, tb.south),
            SIMD2<Double>(tb.west, tb.south),
        ]

        var overlapping = [H3Index]()
        for h3 in candidates {
            let hexPoly = h3.boundaryCoordinates.map { SIMD2<Double>($0.longitude, $0.latitude) }
            if polygonsIntersect(polyA: hexPoly, polyB: tilePoly) {
                overlapping.append(h3)
            }
        }

        return overlapping
    }

    // MARK: - Comparable

    public static func < (lhs: H3Index, rhs: H3Index) -> Bool {
        lhs.value < rhs.value
    }
}

// MARK: - Private Geometric Intersection Helpers

func pointInPolygon(point: SIMD2<Double>, polygon: [SIMD2<Double>]) -> Bool {
    var inside = false
    var j = polygon.count - 1
    for i in 0 ..< polygon.count {
        let pi = polygon[i]
        let pj = polygon[j]
        if ((pi.y > point.y) != (pj.y > point.y)) &&
            (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x)
        {
            inside.toggle()
        }
        j = i
    }
    return inside
}

private func segmentsIntersect(p1: SIMD2<Double>, p2: SIMD2<Double>, p3: SIMD2<Double>, p4: SIMD2<Double>) -> Bool {
    func ccw(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>) -> Double {
        (c.y - a.y) * (b.x - a.x) - (b.y - a.y) * (c.x - a.x)
    }
    let d1 = ccw(p1, p2, p3)
    let d2 = ccw(p1, p2, p4)
    let d3 = ccw(p3, p4, p1)
    let d4 = ccw(p3, p4, p2)

    if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    {
        return true
    }
    return false
}

private func polygonsIntersect(polyA: [SIMD2<Double>], polyB: [SIMD2<Double>]) -> Bool {
    // 1. Any vertex of polyA inside polyB?
    for pt in polyA {
        if pointInPolygon(point: pt, polygon: polyB) { return true }
    }
    // 2. Any vertex of polyB inside polyA?
    for pt in polyB {
        if pointInPolygon(point: pt, polygon: polyA) { return true }
    }
    // 3. Any edge of polyA intersects any edge of polyB?
    for i in 0 ..< polyA.count {
        let a1 = polyA[i]
        let a2 = polyA[(i + 1) % polyA.count]
        for j in 0 ..< polyB.count {
            let b1 = polyB[j]
            let b2 = polyB[(j + 1) % polyB.count]
            if segmentsIntersect(p1: a1, p2: a2, p3: b1, p4: b2) {
                return true
            }
        }
    }
    return false
}
