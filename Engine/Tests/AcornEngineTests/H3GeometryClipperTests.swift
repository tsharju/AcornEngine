@testable import AcornEngine
import AcornMapGeometry
import Foundation
import simd
import Testing

struct H3GeometryClipperTests {
    // A regular hexagon centered at (0, 0) with radius 10.0 in the XZ plane
    private var testHexagon: [SIMD2<Float>] {
        var pts = [SIMD2<Float>]()
        for i in 0 ..< 6 {
            let a = Float(i) * (.pi / 3.0)
            pts.append(SIMD2<Float>(10.0 * cos(a), 10.0 * sin(a)))
        }
        return pts
    }

    @Test("Triangle completely inside hexagon boundary is preserved")
    func triangleInsideHexagon() {
        let insideTriangle = CPUMeshData(
            vertices: [
                Vertex(position: SIMD3<Float>(0, 5, 0), color: .one),
                Vertex(position: SIMD3<Float>(2, 5, 0), color: .one),
                Vertex(position: SIMD3<Float>(0, 5, 2), color: .one),
            ],
            indices: [0, 1, 2]
        )

        let clipped = H3GeometryClipper.clip(meshData: insideTriangle, toPolygon: testHexagon)
        #expect(clipped.vertices.count == 3)
        #expect(clipped.indices.count == 3)
    }

    @Test("Triangle completely outside hexagon boundary is discarded")
    func triangleOutsideHexagon() {
        let outsideTriangle = CPUMeshData(
            vertices: [
                Vertex(position: SIMD3<Float>(50, 0, 50), color: .one),
                Vertex(position: SIMD3<Float>(60, 0, 50), color: .one),
                Vertex(position: SIMD3<Float>(50, 0, 60), color: .one),
            ],
            indices: [0, 1, 2]
        )

        let clipped = H3GeometryClipper.clip(meshData: outsideTriangle, toPolygon: testHexagon)
        #expect(clipped.vertices.isEmpty)
        #expect(clipped.indices.isEmpty)
    }

    @Test("Triangle crossing hexagon boundary is sliced cleanly with interpolated vertex attributes")
    func triangleStraddlingHexagon() {
        // Triangle starting inside (0, 10, 0) and extending far outside along +X to (20, 0, 0) and (20, 0, 5)
        // Hexagon extends to X=10 along positive X axis
        let straddlingTriangle = CPUMeshData(
            vertices: [
                Vertex(
                    position: SIMD3<Float>(0, 10, 0),
                    color: SIMD4<Float>(1, 0, 0, 1),
                    texCoord: SIMD2<Float>(0, 0),
                    normal: SIMD3<Float>(0, 1, 0)
                ),
                Vertex(
                    position: SIMD3<Float>(20, 0, 0),
                    color: SIMD4<Float>(0, 1, 0, 1),
                    texCoord: SIMD2<Float>(1, 0),
                    normal: SIMD3<Float>(0, 1, 0)
                ),
                Vertex(
                    position: SIMD3<Float>(20, 0, 5),
                    color: SIMD4<Float>(0, 0, 1, 1),
                    texCoord: SIMD2<Float>(1, 1),
                    normal: SIMD3<Float>(0, 1, 0)
                ),
            ],
            indices: [0, 1, 2]
        )

        let clipped = H3GeometryClipper.clip(meshData: straddlingTriangle, toPolygon: testHexagon)
        #expect(!clipped.vertices.isEmpty)
        #expect(!clipped.indices.isEmpty)

        // All resulting vertices must be within the hexagon boundary (X <= 10.001)
        for v in clipped.vertices {
            #expect(v.position.x <= 10.01)
            // Interpolated height Y must be between 0 and 10
            #expect(v.position.y >= -0.01 && v.position.y <= 10.01)
            // Color channels must be valid
            #expect(v.color.x >= 0.0 && v.color.x <= 1.0)
            #expect(v.color.y >= 0.0 && v.color.y <= 1.0)
            #expect(v.color.z >= 0.0 && v.color.z <= 1.0)
        }
    }

    @Test("Tile to H3 coordinate transformation and clipping")
    func testClipTileToH3() {
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let h3 = H3Index(coordinate: helsinki, resolution: 9)
        let tile = TileCoordinate(coordinate: helsinki, zoom: 15)

        // Position triangle around H3 center in tile space
        let h3World = h3.worldPosition(relativeTo: helsinki)
        let tileWorldPos = tile.worldPosition(relativeTo: helsinki)
        let cX = h3World.x - tileWorldPos.x
        let cZ = h3World.z - tileWorldPos.z

        let surfaceMesh = CPUMeshData(
            vertices: [
                Vertex(position: SIMD3<Float>(cX - 10, 0, cZ - 10), color: .one),
                Vertex(position: SIMD3<Float>(cX + 10, 0, cZ - 10), color: .one),
                Vertex(position: SIMD3<Float>(cX, 0, cZ + 10), color: .one),
            ],
            indices: [0, 1, 2]
        )
        let roadMesh = CPUMeshData()
        let tileMeshData = TileMeshData(surfaceMesh: surfaceMesh, roadMesh: roadMesh)

        let clipped = H3GeometryClipper.clipTileToH3(
            tileMeshData: tileMeshData,
            sourceTile: tile,
            targetH3: h3,
            referenceCoordinate: helsinki
        )

        // Clipped mesh should be centered around (0, 0) in H3 local space
        #expect(!clipped.surfaceMesh.vertices.isEmpty)
        let r = Float(h3.edgeLengthMeters)
        for v in clipped.surfaceMesh.vertices {
            let distFromH3Center = sqrt(v.position.x * v.position.x + v.position.z * v.position.z)
            #expect(distFromH3Center <= r * 1.05)
        }
    }

    @Test("C++ MapboxTileProcessor.processPolygon with clipPolygon using Clipper2")
    func cPlusPlusPolygonClipping() {
        // Outer building quad [0, 2000] x [0, 2000]
        var outerRing = AcornMap.PolygonRing()
        outerRing.addPoint(0.0, 0.0)
        outerRing.addPoint(2000.0, 0.0)
        outerRing.addPoint(2000.0, 2000.0)
        outerRing.addPoint(0.0, 2000.0)
        outerRing.addPoint(0.0, 0.0)

        var input = AcornMap.TestPolygonInput()
        input.addRing(outerRing)

        // Clip polygon: hexagon inscribed inside [200, 1200]
        var clipHex = AcornMap.PolygonRing()
        for i in 0 ..< 6 {
            let a = Double(i) * (.pi / 3.0)
            let cx = 700.0 + 500.0 * cos(a)
            let cy = 700.0 + 500.0 * sin(a)
            clipHex.addPoint(cx, cy)
        }
        clipHex.addPoint(clipHex.getPoint(0).x, clipHex.getPoint(0).y)

        var result = AcornMap.TileMeshResult()
        AcornMap.MapboxTileProcessor.processPolygon(
            input,
            15.0, // height
            0.0, // min_height
            4096, // extent
            1000.0,
            1000.0,
            &result,
            false,
            clipHex
        )

        #expect(result.getVertexCount() > 0)
        #expect(result.getIndexCount() > 0)

        // The resulting mesh should be clipped strictly to the hexagon!
        // Roof vertices should have Y == 15
        var hasRoof = false
        for i in 0 ..< result.getVertexCount() {
            let v = result.getVertex(i)
            if v.y == 15.0 {
                hasRoof = true
            }
        }
        #expect(hasRoof)
    }

    @Test("C++ MapboxTileProcessor.clipTileMesh directly clips TileMeshResult")
    func cPlusPlusClipTileMesh() {
        var inMesh = AcornMap.TileMeshResult()
        // Add single triangle in [0, 100] x [0, 100]
        inMesh.vertices.push_back(AcornMap.MapVertex(x: 10, y: 5, z: 10, nx: 0, ny: 1, nz: 0, r: 1, g: 1, b: 1, a: 1, u: 0, v: 0))
        inMesh.vertices.push_back(AcornMap.MapVertex(x: 90, y: 5, z: 10, nx: 0, ny: 1, nz: 0, r: 1, g: 1, b: 1, a: 1, u: 1, v: 0))
        inMesh.vertices.push_back(AcornMap.MapVertex(x: 50, y: 5, z: 90, nx: 0, ny: 1, nz: 0, r: 1, g: 1, b: 1, a: 1, u: 0.5, v: 1))
        inMesh.indices.push_back(0)
        inMesh.indices.push_back(1)
        inMesh.indices.push_back(2)

        var clipHex = AcornMap.PolygonRing()
        for i in 0 ..< 6 {
            let a = Double(i) * (.pi / 3.0)
            clipHex.addPoint(50.0 + 30.0 * cos(a), 50.0 + 30.0 * sin(a))
        }

        let outMesh = AcornMap.MapboxTileProcessor.clipTileMesh(inMesh, clipHex)
        #expect(outMesh.getVertexCount() > 0)
        #expect(outMesh.getIndexCount() > 0)
    }

    @Test("H3GeometryClipper cleanly handles explicitly closed polygon rings (first == last)")
    func closedPolygonSanitization() {
        var closedHex = testHexagon
        closedHex.append(closedHex[0]) // Explicitly closed 7-vertex ring
        #expect(closedHex.count == 7)

        let insideTriangle = CPUMeshData(
            vertices: [
                Vertex(position: SIMD3<Float>(0, 5, 0), color: .one),
                Vertex(position: SIMD3<Float>(2, 5, 0), color: .one),
                Vertex(position: SIMD3<Float>(0, 5, 2), color: .one),
            ],
            indices: [0, 1, 2]
        )

        let clipped = H3GeometryClipper.clip(meshData: insideTriangle, toPolygon: closedHex)
        #expect(clipped.vertices.count == 3)
        #expect(clipped.indices.count == 3)
    }

    @Test("TileMeshData clipping slices both surface and road meshes")
    func tileMeshDataBothMeshesClipped() {
        let tri = CPUMeshData(
            vertices: [
                Vertex(position: SIMD3<Float>(0, 0, 0), color: .one),
                Vertex(position: SIMD3<Float>(1, 0, 0), color: .one),
                Vertex(position: SIMD3<Float>(0, 0, 1), color: .one),
            ],
            indices: [0, 1, 2]
        )
        let tmd = TileMeshData(surfaceMesh: tri, roadMesh: tri)
        let clipped = H3GeometryClipper.clip(tileMeshData: tmd, toPolygon: testHexagon)
        #expect(!clipped.surfaceMesh.vertices.isEmpty)
        #expect(!clipped.roadMesh.vertices.isEmpty)
    }
}
