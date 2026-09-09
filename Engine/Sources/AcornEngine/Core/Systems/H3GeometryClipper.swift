import Foundation
import simd

/// A geometric utility that clips 3D surface meshes and 2D road meshes to arbitrary convex 2D polygons,
/// specifically hexagonal H3 cell boundaries.
///
/// Uses an exact Sutherland-Hodgman polygon clipping pipeline extended to 3D triangle meshes,
/// smoothly interpolating vertex positions, elevations, normals, colors, and UV texture coordinates.
public enum H3GeometryClipper {
    // MARK: - Core Mesh Clipping

    /// Clips a `CPUMeshData` (composed of indexed triangles) against a 2D convex polygon in the ground (XZ) plane.
    ///
    /// - Parameters:
    ///   - meshData: The input triangle mesh.
    ///   - polygon: The 2D convex polygon vertices in the XZ plane (X = East, Y = South/Z). Must have >= 3 vertices.
    /// - Returns: A new `CPUMeshData` containing only the geometry inside the polygon, triangulated and clipped.
    public static func clip(meshData: CPUMeshData, toPolygon polygon: [SIMD2<Float>]) -> CPUMeshData {
        let sanitized = sanitizePolygon(polygon)
        guard sanitized.count >= 3, !meshData.vertices.isEmpty, !meshData.indices.isEmpty else {
            return CPUMeshData()
        }

        // Ensure polygon has counter-clockwise winding
        let ccwPoly = ensureCCW(sanitized)

        // Fast AABB rejection
        let (polyMin, polyMax) = computeAABB(ccwPoly)
        let (meshMin, meshMax) = computeMeshAABB(meshData.vertices)

        if meshMax.x < polyMin.x || meshMin.x > polyMax.x || meshMax.y < polyMin.y || meshMin.y > polyMax.y {
            return CPUMeshData()
        }

        // Fast path: if mesh AABB is entirely inside the polygon, return original mesh
        if isAABBInsidePolygon(min: meshMin, max: meshMax, polygon: ccwPoly) {
            return meshData
        }

        var outVertices = [Vertex]()
        var outIndices = [UInt32]()
        outVertices.reserveCapacity(meshData.vertices.count)
        outIndices.reserveCapacity(meshData.indices.count)

        let indexCount = meshData.indices.count
        var triIdx = 0
        while triIdx + 2 < indexCount {
            let i0 = Int(meshData.indices[triIdx])
            let i1 = Int(meshData.indices[triIdx + 1])
            let i2 = Int(meshData.indices[triIdx + 2])
            triIdx += 3

            guard i0 < meshData.vertices.count, i1 < meshData.vertices.count, i2 < meshData.vertices.count else {
                continue
            }

            let v0 = meshData.vertices[i0]
            let v1 = meshData.vertices[i1]
            let v2 = meshData.vertices[i2]

            // Clip triangle against each edge of the convex polygon
            var poly = [v0, v1, v2]

            for edgeIdx in 0 ..< ccwPoly.count {
                let e1 = ccwPoly[edgeIdx]
                let e2 = ccwPoly[(edgeIdx + 1) % ccwPoly.count]

                poly = clipPolygonAgainstEdge(poly, edgeStart: e1, edgeEnd: e2)
                if poly.count < 3 {
                    break
                }
            }

            // Triangulate resulting convex polygon using a triangle fan
            if poly.count >= 3 {
                let baseIndex = UInt32(outVertices.count)
                outVertices.append(contentsOf: poly)

                for k in 1 ..< (poly.count - 1) {
                    outIndices.append(baseIndex)
                    outIndices.append(baseIndex + UInt32(k))
                    outIndices.append(baseIndex + UInt32(k + 1))
                }
            }
        }

        return CPUMeshData(vertices: outVertices, indices: outIndices)
    }

    /// Clips a `TileMeshData` container (surfaceMesh + roadMesh) against a 2D convex polygon.
    public static func clip(tileMeshData: TileMeshData, toPolygon polygon: [SIMD2<Float>]) -> TileMeshData {
        let clippedSurface = clip(meshData: tileMeshData.surfaceMesh, toPolygon: polygon)
        let clippedRoad = clip(meshData: tileMeshData.roadMesh, toPolygon: polygon)
        return TileMeshData(surfaceMesh: clippedSurface, roadMesh: clippedRoad)
    }

    /// Clips a square slippy map tile's `TileMeshData` to the boundary of a target `H3Index` cell.
    ///
    /// The resulting mesh is transformed into H3-local metric space (relative to the H3 cell's world position),
    /// ready to be attached as a child entity in the ECS.
    ///
    /// - Parameters:
    ///   - tileMeshData: The mesh data produced from the square slippy tile.
    ///   - sourceTile: The slippy tile coordinate.
    ///   - targetH3: The target H3 cell index.
    ///   - referenceCoordinate: The game's reference GPS coordinate for world origin.
    /// - Returns: `TileMeshData` clipped to the hexagon and centered in the H3 cell's local space.
    public static func clipTileToH3(
        tileMeshData: TileMeshData,
        sourceTile: TileCoordinate,
        targetH3: H3Index,
        referenceCoordinate: GPSCoordinate
    ) -> TileMeshData {
        // 1. Compute world position offset of source tile NW corner
        let tileWorldPos = sourceTile.worldPosition(relativeTo: referenceCoordinate)
        let h3WorldPos = targetH3.worldPosition(relativeTo: referenceCoordinate)

        // 2. Transform tile mesh from tile-local space [0, W] x [0, H] to world space
        func toWorld(_ mesh: CPUMeshData) -> CPUMeshData {
            var worldVerts = mesh.vertices
            for i in 0 ..< worldVerts.count {
                worldVerts[i].position.x += tileWorldPos.x
                worldVerts[i].position.y += tileWorldPos.y
                worldVerts[i].position.z += tileWorldPos.z
            }
            return CPUMeshData(vertices: worldVerts, indices: mesh.indices)
        }

        let worldSurface = toWorld(tileMeshData.surfaceMesh)
        let worldRoad = toWorld(tileMeshData.roadMesh)

        // 3. Obtain H3 cell boundary in world 2D space (XZ plane)
        let h3PolyWorld = targetH3.boundaryPolygon2D(relativeTo: referenceCoordinate)

        // 4. Clip against H3 hexagon boundary
        let clippedWorldSurface = clip(meshData: worldSurface, toPolygon: h3PolyWorld)
        let clippedWorldRoad = clip(meshData: worldRoad, toPolygon: h3PolyWorld)

        // 5. Shift clipped vertices from world space to H3-local space (relative to h3WorldPos)
        func toH3Local(_ mesh: CPUMeshData) -> CPUMeshData {
            var localVerts = mesh.vertices
            for i in 0 ..< localVerts.count {
                localVerts[i].position.x -= h3WorldPos.x
                localVerts[i].position.y -= h3WorldPos.y
                localVerts[i].position.z -= h3WorldPos.z
            }
            return CPUMeshData(vertices: localVerts, indices: mesh.indices)
        }

        return TileMeshData(
            surfaceMesh: toH3Local(clippedWorldSurface),
            roadMesh: toH3Local(clippedWorldRoad)
        )
    }

    // MARK: - Sutherland-Hodgman Polygon Edge Clipping

    private static func clipPolygonAgainstEdge(
        _ inputPoly: [Vertex],
        edgeStart: SIMD2<Float>,
        edgeEnd: SIMD2<Float>
    ) -> [Vertex] {
        guard !inputPoly.isEmpty else { return [] }

        var output = [Vertex]()
        output.reserveCapacity(inputPoly.count + 2)

        // Directed edge normal pointing INWARD for CCW polygon:
        // edge = (dx, dy). Inward normal = (-dy, dx).
        let dx = edgeEnd.x - edgeStart.x
        let dy = edgeEnd.y - edgeStart.y

        func distanceToEdge(_ pt: SIMD3<Float>) -> Float {
            // (pt.x - edgeStart.x) * (-dy) + (pt.z - edgeStart.y) * dx
            // = dx * (pt.z - edgeStart.y) - dy * (pt.x - edgeStart.x)
            dx * (pt.z - edgeStart.y) - dy * (pt.x - edgeStart.x)
        }

        let count = inputPoly.count
        var prev = inputPoly[count - 1]
        var prevDist = distanceToEdge(prev.position)
        var prevInside = prevDist >= -1e-5

        for curr in inputPoly {
            let currDist = distanceToEdge(curr.position)
            let currInside = currDist >= -1e-5

            if prevInside, currInside {
                // Both inside: keep curr
                output.append(curr)
            } else if prevInside, !currInside {
                // Edge exits: compute intersection
                let t = max(0.0, min(1.0, prevDist / (prevDist - currDist)))
                let inter = interpolateVertex(v0: prev, v1: curr, t: t)
                output.append(inter)
            } else if !prevInside, currInside {
                // Edge enters: compute intersection then curr
                let t = max(0.0, min(1.0, prevDist / (prevDist - currDist)))
                let inter = interpolateVertex(v0: prev, v1: curr, t: t)
                output.append(inter)
                output.append(curr)
            }

            prev = curr
            prevDist = currDist
            prevInside = currInside
        }

        return output
    }

    private static func interpolateVertex(v0: Vertex, v1: Vertex, t: Float) -> Vertex {
        let pos = v0.position + (v1.position - v0.position) * t
        let col = v0.color + (v1.color - v0.color) * t
        let uv = v0.texCoord + (v1.texCoord - v0.texCoord) * t

        var n = v0.normal + (v1.normal - v0.normal) * t
        let lenSq = n.x * n.x + n.y * n.y + n.z * n.z
        if lenSq > 1e-6 {
            n /= sqrt(lenSq)
        } else {
            n = v0.normal
        }

        return Vertex(position: pos, color: col, texCoord: uv, normal: n)
    }

    // MARK: - Geometric Helpers

    private static func ensureCCW(_ poly: [SIMD2<Float>]) -> [SIMD2<Float>] {
        var area: Float = 0.0
        let count = poly.count
        for i in 0 ..< count {
            let p1 = poly[i]
            let p2 = poly[(i + 1) % count]
            area += (p1.x * p2.y - p2.x * p1.y)
        }
        if area < 0.0 {
            return poly.reversed()
        }
        return poly
    }

    private static func computeAABB(_ poly: [SIMD2<Float>]) -> (min: SIMD2<Float>, max: SIMD2<Float>) {
        var minPt = poly[0]
        var maxPt = poly[0]
        for pt in poly {
            minPt.x = min(minPt.x, pt.x)
            minPt.y = min(minPt.y, pt.y)
            maxPt.x = max(maxPt.x, pt.x)
            maxPt.y = max(maxPt.y, pt.y)
        }
        return (minPt, maxPt)
    }

    private static func computeMeshAABB(_ vertices: [Vertex]) -> (min: SIMD2<Float>, max: SIMD2<Float>) {
        var minPt = SIMD2<Float>(vertices[0].position.x, vertices[0].position.z)
        var maxPt = minPt
        for v in vertices {
            minPt.x = min(minPt.x, v.position.x)
            minPt.y = min(minPt.y, v.position.z)
            maxPt.x = max(maxPt.x, v.position.x)
            maxPt.y = max(maxPt.y, v.position.z)
        }
        return (minPt, maxPt)
    }

    private static func isAABBInsidePolygon(min: SIMD2<Float>, max: SIMD2<Float>, polygon: [SIMD2<Float>]) -> Bool {
        let corners = [
            SIMD2<Float>(min.x, min.y),
            SIMD2<Float>(max.x, min.y),
            SIMD2<Float>(max.x, max.y),
            SIMD2<Float>(min.x, max.y),
        ]
        for c in corners {
            if !isPointInsideConvexPolygon(c, polygon: polygon) {
                return false
            }
        }
        return true
    }

    private static func isPointInsideConvexPolygon(_ pt: SIMD2<Float>, polygon: [SIMD2<Float>]) -> Bool {
        let count = polygon.count
        for i in 0 ..< count {
            let p1 = polygon[i]
            let p2 = polygon[(i + 1) % count]
            let dx = p2.x - p1.x
            let dy = p2.y - p1.y
            let dist = dx * (pt.y - p1.y) - dy * (pt.x - p1.x)
            if dist < -1e-4 {
                return false
            }
        }
        return true
    }

    private static func sanitizePolygon(_ poly: [SIMD2<Float>]) -> [SIMD2<Float>] {
        var clean = poly
        while clean.count >= 4 {
            let first = clean[0]
            let last = clean[clean.count - 1]
            if abs(first.x - last.x) < 1e-5, abs(first.y - last.y) < 1e-5 {
                clean.removeLast()
            } else {
                break
            }
        }
        return clean
    }
}
