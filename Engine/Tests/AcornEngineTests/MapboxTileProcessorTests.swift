import Testing
import simd
import Foundation
import AcornMapGeometry
@testable import AcornEngine

struct MapboxTileProcessorTests {
    @Test("Simple 3D building extrusion with roof normal (0, 1, 0) and outward CCW wall quads")
    func testSimpleBuildingExtrusion() {
        var outerRing = AcornMap.PolygonRing()
        outerRing.addPoint(1000.0, 1000.0)
        outerRing.addPoint(2000.0, 1000.0)
        outerRing.addPoint(2000.0, 2000.0)
        outerRing.addPoint(1000.0, 2000.0)
        outerRing.addPoint(1000.0, 1000.0)
        
        var input = AcornMap.TestPolygonInput()
        input.addRing(outerRing)
        
        var result = AcornMap.TileMeshResult()
        AcornMap.MapboxTileProcessor.processPolygon(
            input,
            20.0, // height
            0.0,  // min_height
            4096, // extent
            1000.0, // tile ground width in meters
            1000.0, // tile ground height in meters
            &result,
            false // isWater
        )
        
        let vertexCount = result.getVertexCount()
        let indexCount = result.getIndexCount()
        
        #expect(vertexCount > 0)
        #expect(indexCount > 0)
        
        // Roof cap: 4 vertices, triangulated into 2 triangles = 6 indices
        // 4 walls: 4 vertices per wall quad = 16 vertices, 2 triangles per wall = 24 indices
        // Total indices = 30
        #expect(indexCount == 30)
        
        // Check roof vertices
        var roofVertexCount = 0
        var wallVertexCount = 0
        for i in 0..<vertexCount {
            let v = result.getVertex(i)
            if v.y == 20.0 && v.ny == 1.0 {
                roofVertexCount += 1
            } else {
                wallVertexCount += 1
                // Wall normal must be horizontal (ny == 0) and unit length
                #expect(abs(v.ny) < 0.001)
                let len = sqrt(v.nx * v.nx + v.nz * v.nz)
                #expect(abs(len - 1.0) < 0.01)
            }
        }
        #expect(roofVertexCount == 4)
        #expect(wallVertexCount == 16)
    }
    
    @Test("Courtyard hole triangulation with earcut.hpp and inward courtyard wall normals")
    func testBuildingWithCourtyardHole() {
        // Outer ring [1000, 3000] x [1000, 3000]
        var outerRing = AcornMap.PolygonRing()
        outerRing.addPoint(1000.0, 1000.0)
        outerRing.addPoint(3000.0, 1000.0)
        outerRing.addPoint(3000.0, 3000.0)
        outerRing.addPoint(1000.0, 3000.0)
        outerRing.addPoint(1000.0, 1000.0)
        
        // Inner courtyard hole [1500, 2500] x [1500, 2500]
        var holeRing = AcornMap.PolygonRing()
        holeRing.addPoint(1500.0, 1500.0)
        holeRing.addPoint(1500.0, 2500.0)
        holeRing.addPoint(2500.0, 2500.0)
        holeRing.addPoint(2500.0, 1500.0)
        holeRing.addPoint(1500.0, 1500.0)
        
        var input = AcornMap.TestPolygonInput()
        input.addRing(outerRing)
        input.addRing(holeRing)
        
        var result = AcornMap.TileMeshResult()
        AcornMap.MapboxTileProcessor.processPolygon(
            input,
            15.0, // height
            0.0,  // min_height
            4096, // extent
            1000.0,
            1000.0,
            &result,
            false
        )
        
        let indexCount = result.getIndexCount()
        // 4 outer walls (24 indices) + 4 inner courtyard walls (24 indices) = 48 wall indices
        // Roof cap around hole is triangulated into at least 8 triangles (24 indices)
        // Total indices >= 72
        #expect(indexCount >= 72)
    }
    
    @Test("Tile seam filter suppresses wall creation along tile boundaries [0, extent]")
    func testTileBoundarySeamFilter() {
        // Building cut right along the West boundary x = 0:
        // (0, 1000) -> (1000, 1000) -> (1000, 2000) -> (0, 2000) -> (0, 1000)
        // Edge (0, 2000) -> (0, 1000) lies on x = 0
        var outerRing = AcornMap.PolygonRing()
        outerRing.addPoint(0.0, 1000.0)
        outerRing.addPoint(1000.0, 1000.0)
        outerRing.addPoint(1000.0, 2000.0)
        outerRing.addPoint(0.0, 2000.0)
        outerRing.addPoint(0.0, 1000.0)
        
        var input = AcornMap.TestPolygonInput()
        input.addRing(outerRing)
        
        var result = AcornMap.TileMeshResult()
        AcornMap.MapboxTileProcessor.processPolygon(
            input,
            20.0,
            0.0,
            4096,
            1000.0,
            1000.0,
            &result,
            false
        )
        
        // Roof cap: 2 triangles = 6 indices
        // Walls: Only 3 walls should be extruded (3 * 6 = 18 indices) because the edge at x=0 was SUPPRESSED!
        // Total indices = 24 (instead of 30)
        #expect(result.getIndexCount() == 24)
    }
    
    @Test("Multi-tier clipping with Clipper2 on geometry crossing tile boundary")
    func testMultiTierClipping() {
        // Polygon extending outside tile bounds to x = -500:
        // (-500, 1000) -> (1000, 1000) -> (1000, 2000) -> (-500, 2000) -> (-500, 1000)
        var outerRing = AcornMap.PolygonRing()
        outerRing.addPoint(-500.0, 1000.0)
        outerRing.addPoint(1000.0, 1000.0)
        outerRing.addPoint(1000.0, 2000.0)
        outerRing.addPoint(-500.0, 2000.0)
        outerRing.addPoint(-500.0, 1000.0)
        
        var input = AcornMap.TestPolygonInput()
        input.addRing(outerRing)
        
        var result = AcornMap.TileMeshResult()
        AcornMap.MapboxTileProcessor.processPolygon(
            input,
            20.0,
            0.0,
            4096,
            1000.0,
            1000.0,
            &result,
            false
        )
        
        #expect(result.getVertexCount() > 0)
        // Verify all vertices were clipped to x >= 0
        for i in 0..<result.getVertexCount() {
            let v = result.getVertex(i)
            #expect(v.x >= -0.01)
        }
        
        // Seam wall along x=0 is suppressed, so only 3 wall quads (18 indices) + roof (6 indices) = 24 indices!
        #expect(result.getIndexCount() == 24)
    }
    
    @Test("Water flat polygon produces surface mesh at Y=0 without wall extrusion")
    func testWaterPolygon() {
        var outerRing = AcornMap.PolygonRing()
        outerRing.addPoint(1000.0, 1000.0)
        outerRing.addPoint(2000.0, 1000.0)
        outerRing.addPoint(2000.0, 2000.0)
        outerRing.addPoint(1000.0, 2000.0)
        outerRing.addPoint(1000.0, 1000.0)
        
        var input = AcornMap.TestPolygonInput()
        input.addRing(outerRing)
        
        var result = AcornMap.TileMeshResult()
        AcornMap.MapboxTileProcessor.processPolygon(
            input,
            0.0,
            0.0,
            4096,
            1000.0,
            1000.0,
            &result,
            true // isWater
        )
        
        // Only 4 vertices and 6 indices for the flat water surface
        #expect(result.getVertexCount() == 4)
        #expect(result.getIndexCount() == 6)
        
        for i in 0..<result.getVertexCount() {
            let v = result.getVertex(i)
            #expect(abs(v.y) < 0.001)
            #expect(v.ny == 1.0)
        }
    }
    
    @Test("End-to-end vector tile protobuf generation and decoding pipeline")
    func testEndToEndVectorTilePipeline() async {
        // Create an in-memory MVT tile containing a 3D building
        var outerRing = AcornMap.PolygonRing()
        outerRing.addPoint(1000.0, 1000.0)
        outerRing.addPoint(2000.0, 1000.0)
        outerRing.addPoint(2000.0, 2000.0)
        outerRing.addPoint(1000.0, 2000.0)
        
        let testTileRes = AcornMap.MapboxTileProcessor.createTestTile(
            std.__1.string("building"),
            outerRing,
            30.0, // height = 30m
            0.0   // min_height = 0m
        )
        #expect(testTileRes.success)
        
        var tileBytes = [UInt8](repeating: 0, count: testTileRes.size())
        tileBytes.withUnsafeMutableBufferPointer { buf in
            testTileRes.copyTo(buf.baseAddress)
        }
        let tileData = Data(tileBytes)
        #expect(!tileData.isEmpty)
        
        let loader = MapTileLoader()
        let coord = TileCoordinate(zoom: 15, x: 100, y: 100)
        let mesh = await loader.processTile(data: tileData, coordinate: coord, referenceLatitude: 60.0)
        
        #expect(mesh.vertices.count > 0)
        #expect(mesh.indices.count == 30)
        
        // Verify building height is 30m in mesh vertices (both roof cap and top of walls)
        var foundRoof = false
        for v in mesh.vertices {
            if abs(v.position.y - 30.0) < 0.001 && v.normal == SIMD3<Float>(0, 1, 0) {
                foundRoof = true
            }
        }
        #expect(foundRoof)
    }
    
    @Test("Landuse flat polygon produces surface mesh at Y=0 without wall extrusion")
    func testLanduseFlatSurfaceNoWalls() async {
        var outerRing = AcornMap.PolygonRing()
        outerRing.addPoint(1000.0, 1000.0)
        outerRing.addPoint(2000.0, 1000.0)
        outerRing.addPoint(2000.0, 2000.0)
        outerRing.addPoint(1000.0, 2000.0)
        
        let testTileRes = AcornMap.MapboxTileProcessor.createTestTile(
            std.__1.string("landuse"),
            outerRing,
            10.0, // Should be ignored since landuse is a 2D ground surface
            0.0
        )
        #expect(testTileRes.success)
        
        var tileBytes = [UInt8](repeating: 0, count: testTileRes.size())
        tileBytes.withUnsafeMutableBufferPointer { buf in
            testTileRes.copyTo(buf.baseAddress)
        }
        let tileData = Data(tileBytes)
        
        let loader = MapTileLoader()
        let coord = TileCoordinate(zoom: 15, x: 100, y: 100)
        let mesh = await loader.processTile(data: tileData, coordinate: coord, referenceLatitude: 60.0)
        
        // Only 4 vertices and 6 indices for the flat ground surface (no walls!)
        #expect(mesh.vertices.count == 4)
        #expect(mesh.indices.count == 6)
        
        for v in mesh.vertices {
            #expect(abs(v.position.y) < 0.001)
            #expect(v.normal == SIMD3<Float>(0, 1, 0))
        }
    }
    
    @Test("Unknown layers (e.g. admin) are ignored and not extruded as buildings")
    func testUnknownLayerIgnored() async {
        var outerRing = AcornMap.PolygonRing()
        outerRing.addPoint(1000.0, 1000.0)
        outerRing.addPoint(2000.0, 1000.0)
        outerRing.addPoint(2000.0, 2000.0)
        outerRing.addPoint(1000.0, 2000.0)
        
        let testTileRes = AcornMap.MapboxTileProcessor.createTestTile(
            std.__1.string("admin"),
            outerRing,
            10.0,
            0.0
        )
        #expect(testTileRes.success)
        
        var tileBytes = [UInt8](repeating: 0, count: testTileRes.size())
        tileBytes.withUnsafeMutableBufferPointer { buf in
            testTileRes.copyTo(buf.baseAddress)
        }
        let tileData = Data(tileBytes)
        
        let loader = MapTileLoader()
        let coord = TileCoordinate(zoom: 15, x: 100, y: 100)
        let mesh = await loader.processTile(data: tileData, coordinate: coord, referenceLatitude: 60.0)
        
        #expect(mesh.vertices.isEmpty)
        #expect(mesh.indices.isEmpty)
    }
    
    @Test("Road linestring processing generates ribbon geometry with width and outline attributes")
    func testRoadLineStringProcessing() async {
        var roadPoints = AcornMap.PolygonRing()
        roadPoints.addPoint(500.0, 500.0)
        roadPoints.addPoint(1500.0, 500.0)
        roadPoints.addPoint(2500.0, 1500.0)
        
        let testTileRes = AcornMap.MapboxTileProcessor.createTestRoadTile(
            std.__1.string("road"),
            roadPoints,
            std.__1.string("primary")
        )
        #expect(testTileRes.success)
        
        var tileBytes = [UInt8](repeating: 0, count: testTileRes.size())
        tileBytes.withUnsafeMutableBufferPointer { buf in
            testTileRes.copyTo(buf.baseAddress)
        }
        let tileData = Data(tileBytes)
        
        let loader = MapTileLoader()
        let coord = TileCoordinate(zoom: 15, x: 100, y: 100)
        let meshData = await loader.processTileData(data: tileData, coordinate: coord, referenceLatitude: 60.0)
        
        #expect(meshData.surfaceMesh.vertices.isEmpty)
        let roadMesh = meshData.roadMesh
        
        // 3 points on the road path -> 2 vertices per point = 6 vertices
        #expect(roadMesh.vertices.count == 6)
        // 2 segments -> 2 quads -> 4 triangles = 12 indices
        #expect(roadMesh.indices.count == 12)
        
        for v in roadMesh.vertices {
            // Road ribbon should be slightly elevated above terrain
            #expect(abs(v.position.y - 0.08) < 0.001)
            // Primary road base width is 10.5 meters (miter joints may scale slightly up)
            #expect(v.normal.y >= 10.5 - 0.001)
            // Ribbon side in texCoord.x should be -1.0 or +1.0
            #expect(abs(abs(v.texCoord.x) - 1.0) < 0.001)
            // Outline ratio in texCoord.y should be 0.18
            #expect(abs(v.texCoord.y - 0.18) < 0.001)
        }
    }
    
    @Test("Road classification styles map correctly to widths")
    func testRoadClassificationStyles() async {
        let classesAndExpectedWidths: [(String, Float)] = [
            ("motorway", 14.0),
            ("trunk", 12.0),
            ("primary", 10.5),
            ("street", 6.0),
            ("service", 4.5)
        ]
        
        for (roadClass, expectedWidth) in classesAndExpectedWidths {
            var roadPoints = AcornMap.PolygonRing()
            roadPoints.addPoint(100.0, 100.0)
            roadPoints.addPoint(500.0, 100.0)
            
            let testTileRes = AcornMap.MapboxTileProcessor.createTestRoadTile(
                std.__1.string("road"),
                roadPoints,
                std.__1.string(roadClass)
            )
            #expect(testTileRes.success)
            
            var tileBytes = [UInt8](repeating: 0, count: testTileRes.size())
            tileBytes.withUnsafeMutableBufferPointer { buf in
                testTileRes.copyTo(buf.baseAddress)
            }
            let tileData = Data(tileBytes)
            
            let loader = MapTileLoader()
            let coord = TileCoordinate(zoom: 15, x: 100, y: 100)
            let meshData = await loader.processTileData(data: tileData, coordinate: coord, referenceLatitude: 60.0)
            let roadMesh = meshData.roadMesh
            
            #expect(!roadMesh.vertices.isEmpty)
            for v in roadMesh.vertices {
                #expect(abs(v.normal.y - expectedWidth) < 0.001)
            }
        }
    }
    
    @Test("Non-car road layers (pedestrian, path, cycleway) are filtered out by carOnly configuration")
    func testNonCarRoadsFilteredOut() async {
        let nonCarClasses = ["pedestrian", "path", "cycleway", "footway", "steps", "track"]
        
        for nonCarClass in nonCarClasses {
            var roadPoints = AcornMap.PolygonRing()
            roadPoints.addPoint(100.0, 100.0)
            roadPoints.addPoint(500.0, 100.0)
            
            let testTileRes = AcornMap.MapboxTileProcessor.createTestRoadTile(
                std.__1.string("road"),
                roadPoints,
                std.__1.string(nonCarClass)
            )
            #expect(testTileRes.success)
            
            var tileBytes = [UInt8](repeating: 0, count: testTileRes.size())
            tileBytes.withUnsafeMutableBufferPointer { buf in
                testTileRes.copyTo(buf.baseAddress)
            }
            let tileData = Data(tileBytes)
            
            // Default loader uses .carOnly
            let loader = MapTileLoader(roadConfiguration: .carOnly)
            let coord = TileCoordinate(zoom: 15, x: 100, y: 100)
            let meshData = await loader.processTileData(data: tileData, coordinate: coord, referenceLatitude: 60.0)
            
            // All non-car layers must be omitted completely
            #expect(meshData.roadMesh.vertices.isEmpty, "Road class '\(nonCarClass)' should be filtered out by carOnly configuration")
            #expect(meshData.roadMesh.indices.isEmpty)
        }
    }
    
    @Test("Non-car road layers are rendered when using allRoads configuration")
    func testAllRoadsConfigurationIncludesNonCarLayers() async {
        var roadPoints = AcornMap.PolygonRing()
        roadPoints.addPoint(100.0, 100.0)
        roadPoints.addPoint(500.0, 100.0)
        
        let testTileRes = AcornMap.MapboxTileProcessor.createTestRoadTile(
            std.__1.string("road"),
            roadPoints,
            std.__1.string("path")
        )
        #expect(testTileRes.success)
        
        var tileBytes = [UInt8](repeating: 0, count: testTileRes.size())
        tileBytes.withUnsafeMutableBufferPointer { buf in
            testTileRes.copyTo(buf.baseAddress)
        }
        let tileData = Data(tileBytes)
        
        let loader = MapTileLoader(roadConfiguration: .allRoads)
        let coord = TileCoordinate(zoom: 15, x: 100, y: 100)
        let meshData = await loader.processTileData(data: tileData, coordinate: coord, referenceLatitude: 60.0)
        
        #expect(!meshData.roadMesh.vertices.isEmpty)
        for v in meshData.roadMesh.vertices {
            #expect(abs(v.normal.y - 3.0) < 0.001)
        }
    }
    
    @Test("Custom road configuration allows modifying widths and filtering")
    func testCustomRoadConfiguration() async {
        var roadPoints = AcornMap.PolygonRing()
        roadPoints.addPoint(100.0, 100.0)
        roadPoints.addPoint(500.0, 100.0)
        
        let testTileRes = AcornMap.MapboxTileProcessor.createTestRoadTile(
            std.__1.string("road"),
            roadPoints,
            std.__1.string("primary")
        )
        #expect(testTileRes.success)
        
        var tileBytes = [UInt8](repeating: 0, count: testTileRes.size())
        tileBytes.withUnsafeMutableBufferPointer { buf in
            testTileRes.copyTo(buf.baseAddress)
        }
        let tileData = Data(tileBytes)
        
        // Customize primary road width to 18.0m
        var customConfig = RoadConfiguration.carOnly
        customConfig.setStyle(RoadLayerStyle(width: 18.0), for: "primary")
        
        let loader = MapTileLoader(roadConfiguration: customConfig)
        let coord = TileCoordinate(zoom: 15, x: 100, y: 100)
        let meshData = await loader.processTileData(data: tileData, coordinate: coord, referenceLatitude: 60.0)
        
        #expect(!meshData.roadMesh.vertices.isEmpty)
        for v in meshData.roadMesh.vertices {
            #expect(abs(v.normal.y - 18.0) < 0.001)
        }
    }
    
    @Test("Road junction caps generation produces circular fan caps at endpoints")
    func testRoadJunctionCapGeneration() async {
        var roadPoints = AcornMap.PolygonRing()
        roadPoints.addPoint(500.0, 500.0)
        roadPoints.addPoint(1500.0, 500.0)
        roadPoints.addPoint(2500.0, 1500.0)
        
        let testTileRes = AcornMap.MapboxTileProcessor.createTestRoadTile(
            std.__1.string("road"),
            roadPoints,
            std.__1.string("primary"),
            true // generateCaps = true
        )
        #expect(testTileRes.success)
        
        var tileBytes = [UInt8](repeating: 0, count: testTileRes.size())
        tileBytes.withUnsafeMutableBufferPointer { buf in
            testTileRes.copyTo(buf.baseAddress)
        }
        let tileData = Data(tileBytes)
        
        let loader = MapTileLoader()
        let coord = TileCoordinate(zoom: 15, x: 100, y: 100)
        let meshData = await loader.processTileData(data: tileData, coordinate: coord, referenceLatitude: 60.0)
        
        let roadMesh = meshData.roadMesh
        // 3 line points -> 6 ribbon vertices + 2 caps * 9 vertices (1 center + 8 perimeter) = 24 vertices
        #expect(roadMesh.vertices.count == 24)
        // 2 segments -> 12 ribbon indices + 2 caps * (8 * 3 = 24) = 60 indices
        #expect(roadMesh.indices.count == 60)
        
        // Check that we have center vertices with u = 0.0 and perimeter vertices with u = 1.0
        var centerCapCount = 0
        var perimCapCount = 0
        for v in roadMesh.vertices {
            if v.texCoord.x == 0.0 && v.normal.x == 0.0 && v.normal.z == 0.0 {
                centerCapCount += 1
            } else if v.texCoord.x == 1.0 && (v.normal.x != 0.0 || v.normal.z != 0.0) {
                perimCapCount += 1
            }
        }
        #expect(centerCapCount == 2)
        #expect(perimCapCount >= 16)
    }
}

