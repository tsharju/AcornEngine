import Foundation
import simd

/// A geometric utility that clips 3D surface meshes and 2D road meshes to arbitrary convex 2D polygons,
/// specifically hexagonal H3 cell boundaries.
///
/// Uses an exact Sutherland-Hodgman polygon clipping pipeline extended to 3D triangle meshes,
/// smoothly interpolating vertex positions, elevations, normals, colors, and UV texture coordinates.
public enum H3GeometryClipper {
    // MARK: - Edge Equation Helper

    private struct EdgeEquation {
        let a: Float
        let b: Float
        let c: Float

        @inline(__always)
        init(edgeStart: SIMD2<Float>, edgeEnd: SIMD2<Float>) {
            let dx = edgeEnd.x - edgeStart.x
            let dy = edgeEnd.y - edgeStart.y
            self.a = -dy
            self.b = dx
            self.c = dy * edgeStart.x - dx * edgeStart.y
        }

        @inline(__always)
        func distance(x: Float, z: Float) -> Float {
            a * x + b * z + c
        }
    }

    // MARK: - Core Mesh Clipping

    /// Clips a `CPUMeshData` (composed of indexed triangles) against a 2D convex polygon in the ground (XZ) plane.
    ///
    /// - Parameters:
    ///   - meshData: The input triangle mesh.
    ///   - polygon: The 2D convex polygon vertices in the XZ plane (X = East, Y = South/Z). Must have >= 3 vertices.
    ///   - vertexOffset: Optional 3D translation offset applied directly to output vertices (e.g. from tile space to H3-local space).
    ///   - preserveIntersectingTriangles: When `true`, triangles that intersect the polygon boundary are preserved intact without
    ///     slicing. Essential for road ribbons where vertex attributes (like across-line coordinate `texCoord.x`) cannot be linearly
    ///     interpolated across triangle diagonals without collapsing road width to zero in the shader.
    /// - Returns: A new `CPUMeshData` containing only the geometry inside the polygon, triangulated and clipped.
    public static func clip(
        meshData: CPUMeshData,
        toPolygon polygon: [SIMD2<Float>],
        vertexOffset: SIMD3<Float> = .zero,
        preserveIntersectingTriangles: Bool = false
    ) -> CPUMeshData {
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

        // Fast path: if mesh AABB is entirely inside the polygon, return original mesh (with optional offset)
        if isAABBInsidePolygon(min: meshMin, max: meshMax, polygon: ccwPoly) {
            if vertexOffset == .zero {
                return meshData
            } else {
                var shiftedVerts = meshData.vertices
                for i in 0 ..< shiftedVerts.count {
                    shiftedVerts[i].position += vertexOffset
                }
                return CPUMeshData(vertices: shiftedVerts, indices: meshData.indices)
            }
        }

        // Precompute edge half-plane equations
        let edgeCount = ccwPoly.count
        var edgeEquations = [EdgeEquation]()
        edgeEquations.reserveCapacity(edgeCount)
        for i in 0 ..< edgeCount {
            let e1 = ccwPoly[i]
            let e2 = ccwPoly[(i + 1) % edgeCount]
            edgeEquations.append(EdgeEquation(edgeStart: e1, edgeEnd: e2))
        }

        var outVertices = [Vertex]()
        var outIndices = [UInt32]()
        outVertices.reserveCapacity(meshData.vertices.count)
        outIndices.reserveCapacity(meshData.indices.count)

        // Pre-allocate ping-pong buffers for straddling triangles to avoid per-triangle heap allocations
        var bufferA: [Vertex] = []
        var bufferB: [Vertex] = []
        bufferA.reserveCapacity(12)
        bufferB.reserveCapacity(12)

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

            // 1. Fast triangle AABB rejection against polygon bounding box
            let tMinX = min(v0.position.x, min(v1.position.x, v2.position.x))
            let tMaxX = max(v0.position.x, max(v1.position.x, v2.position.x))
            let tMinZ = min(v0.position.z, min(v1.position.z, v2.position.z))
            let tMaxZ = max(v0.position.z, max(v1.position.z, v2.position.z))

            if tMaxX < polyMin.x || tMinX > polyMax.x || tMaxZ < polyMin.y || tMinZ > polyMax.y {
                continue
            }

            // 2. Early-out testing: check if triangle is completely outside any edge or completely inside all edges
            var allInside = true
            var anyOutsideEdge = false

            for e in 0 ..< edgeCount {
                let eq = edgeEquations[e]
                let d0 = eq.distance(x: v0.position.x, z: v0.position.z)
                let d1 = eq.distance(x: v1.position.x, z: v1.position.z)
                let d2 = eq.distance(x: v2.position.x, z: v2.position.z)

                if d0 < -1e-5 && d1 < -1e-5 && d2 < -1e-5 {
                    anyOutsideEdge = true
                    break
                }
                if d0 < -1e-5 || d1 < -1e-5 || d2 < -1e-5 {
                    allInside = false
                }
            }

            if anyOutsideEdge {
                continue
            }

            if allInside || preserveIntersectingTriangles {
                // Trivial accept or intact preservation: triangle lies inside or intersects the convex polygon
                let baseIndex = UInt32(outVertices.count)
                if vertexOffset == .zero {
                    outVertices.append(v0)
                    outVertices.append(v1)
                    outVertices.append(v2)
                } else {
                    var s0 = v0; s0.position += vertexOffset
                    var s1 = v1; s1.position += vertexOffset
                    var s2 = v2; s2.position += vertexOffset
                    outVertices.append(s0)
                    outVertices.append(s1)
                    outVertices.append(s2)
                }
                outIndices.append(baseIndex)
                outIndices.append(baseIndex + 1)
                outIndices.append(baseIndex + 2)
                continue
            }

            // 3. Triangle straddles one or more edges: run zero-allocation Sutherland-Hodgman clipping
            bufferA.removeAll(keepingCapacity: true)
            bufferA.append(v0)
            bufferA.append(v1)
            bufferA.append(v2)

            var currentBuffer = 0 // 0 = bufferA, 1 = bufferB

            for e in 0 ..< edgeCount {
                let inputCount = (currentBuffer == 0) ? bufferA.count : bufferB.count
                if inputCount < 3 {
                    break
                }

                let eq = edgeEquations[e]
                if currentBuffer == 0 {
                    bufferB.removeAll(keepingCapacity: true)
                    clipPolygonAgainstEdge(input: bufferA, output: &bufferB, edge: eq)
                    currentBuffer = 1
                } else {
                    bufferA.removeAll(keepingCapacity: true)
                    clipPolygonAgainstEdge(input: bufferB, output: &bufferA, edge: eq)
                    currentBuffer = 0
                }
            }

            let resultPoly = (currentBuffer == 0) ? bufferA : bufferB
            let polyCount = resultPoly.count
            if polyCount >= 3 {
                let baseIndex = UInt32(outVertices.count)
                if vertexOffset == .zero {
                    outVertices.append(contentsOf: resultPoly)
                } else {
                    outVertices.reserveCapacity(outVertices.count + polyCount)
                    for i in 0 ..< polyCount {
                        var v = resultPoly[i]
                        v.position += vertexOffset
                        outVertices.append(v)
                    }
                }

                for k in 1 ..< (polyCount - 1) {
                    outIndices.append(baseIndex)
                    outIndices.append(baseIndex + UInt32(k))
                    outIndices.append(baseIndex + UInt32(k + 1))
                }
            }
        }

        return CPUMeshData(vertices: outVertices, indices: outIndices)
    }

    /// Clips a `TileMeshData` container (surfaceMesh + roadMesh) against a 2D convex polygon.
    ///
    /// Surface meshes (3D terrain, buildings, water) are sliced along the polygon boundary.
    /// Road ribbon meshes (whose width is dynamically expanded in the vertex shader using `texCoord.x`)
    /// have their intersecting triangles preserved intact without slicing to avoid pinching the road width
    /// to zero along triangle diagonals.
    public static func clip(
        tileMeshData: TileMeshData,
        toPolygon polygon: [SIMD2<Float>],
        vertexOffset: SIMD3<Float> = .zero
    ) -> TileMeshData {
        let clippedSurface = clip(
            meshData: tileMeshData.surfaceMesh,
            toPolygon: polygon,
            vertexOffset: vertexOffset,
            preserveIntersectingTriangles: false
        )
        let clippedRoad = clip(
            meshData: tileMeshData.roadMesh,
            toPolygon: polygon,
            vertexOffset: vertexOffset,
            preserveIntersectingTriangles: true
        )
        return TileMeshData(surfaceMesh: clippedSurface, roadMesh: clippedRoad)
    }

    /// Clips a square slippy map tile's `TileMeshData` to the boundary of a target `H3Index` cell.
    ///
    /// The resulting mesh is transformed directly into H3-local metric space (relative to the H3 cell's world position),
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
        // 1. World positions of tile NW corner and H3 center
        let tileWorldPos = sourceTile.worldPosition(relativeTo: referenceCoordinate)
        let h3WorldPos = targetH3.worldPosition(relativeTo: referenceCoordinate)

        // 2. Obtain H3 cell boundary in world 2D space (XZ plane)
        let h3PolyWorld = targetH3.boundaryPolygon2D(relativeTo: referenceCoordinate)

        // 3. Transform H3 polygon into tile-local space
        // Since P_world = tileWorldPos + P_tile, P_tile = P_world - tileWorldPos
        let h3PolyTile = h3PolyWorld.map {
            SIMD2<Float>($0.x - tileWorldPos.x, $0.y - tileWorldPos.z)
        }

        // 4. Offset from tile space to H3-local space
        // P_h3 = P_world - h3WorldPos = P_tile + tileWorldPos - h3WorldPos
        let vertexOffset = tileWorldPos - h3WorldPos

        // 5. Clip directly in tile-local space with direct vertex offset translation
        return clip(
            tileMeshData: tileMeshData,
            toPolygon: h3PolyTile,
            vertexOffset: vertexOffset
        )
    }

    // MARK: - Sutherland-Hodgman Polygon Edge Clipping

    @inline(__always)
    private static func clipPolygonAgainstEdge(
        input: [Vertex],
        output: inout [Vertex],
        edge: EdgeEquation
    ) {
        let count = input.count
        guard count > 0 else { return }

        var prev = input[count - 1]
        var prevDist = edge.distance(x: prev.position.x, z: prev.position.z)
        var prevInside = prevDist >= -1e-5

        for i in 0 ..< count {
            let curr = input[i]
            let currDist = edge.distance(x: curr.position.x, z: curr.position.z)
            let currInside = currDist >= -1e-5

            if prevInside && currInside {
                output.append(curr)
            } else if prevInside && !currInside {
                let t = max(0.0, min(1.0, prevDist / (prevDist - currDist)))
                output.append(interpolateVertex(v0: prev, v1: curr, t: t))
            } else if !prevInside && currInside {
                let t = max(0.0, min(1.0, prevDist / (prevDist - currDist)))
                output.append(interpolateVertex(v0: prev, v1: curr, t: t))
                output.append(curr)
            }

            prev = curr
            prevDist = currDist
            prevInside = currInside
        }
    }

    @inline(__always)
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
