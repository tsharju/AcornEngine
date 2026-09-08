import Testing
import simd
import Foundation
@testable import AcornEngine

@MainActor
struct MapTileSystemTests {
    @Test("Tile spawning and component attachment in ECS World")
    func testTileSpawning() {
        let world = World()
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let system = MapTileSystem(initialReference: helsinki, zoomLevel: 15, loadRadius: 1)
        
        let coord = TileCoordinate(coordinate: helsinki, zoom: 15)
        let cpuMesh = CPUMeshData(
            vertices: [
                Vertex(position: SIMD3<Float>(0, 0, 0), color: SIMD4<Float>(1, 1, 1, 1)),
                Vertex(position: SIMD3<Float>(10, 0, 0), color: SIMD4<Float>(1, 1, 1, 1)),
                Vertex(position: SIMD3<Float>(0, 0, 10), color: SIMD4<Float>(1, 1, 1, 1))
            ],
            indices: [0, 1, 2]
        )
        
        let entity = system.spawnTile(coord: coord, cpuMesh: cpuMesh, world: world)
        
        // Entity should have TransformComponent, MeshComponent, and MapTileComponent
        let transform = world.component(ofType: TransformComponent.self, for: entity)
        let meshComp = world.component(ofType: MeshComponent.self, for: entity)
        let tileComp = world.component(ofType: MapTileComponent.self, for: entity)
        
        #expect(transform != nil)
        #expect(meshComp != nil)
        #expect(tileComp != nil)
        
        #expect(tileComp?.coordinate == coord)
        #expect(tileComp?.referenceLatitude == helsinki.latitude)
        #expect(tileComp?.state == .loaded)
        
        // Ground dimensions should reflect cos(60 deg) scaling
        let (expectedW, _) = coord.groundDimensions(atLatitude: helsinki.latitude)
        #expect(abs((tileComp?.groundDimensions.width ?? 0) - expectedW) < 0.001)
        
        #expect(system.activeTileEntities[coord] == entity)
    }
    
    @Test("Tile eviction when camera moves out of range")
    func testTileEviction() {
        let world = World()
        let centerCoord = TileCoordinate(zoom: 15, x: 100, y: 100)
        let inRangeCoord = TileCoordinate(zoom: 15, x: 101, y: 100)
        let outRangeCoord = TileCoordinate(zoom: 15, x: 110, y: 100)
        let system = MapTileSystem(initialReference: centerCoord.centerCoordinate, zoomLevel: 15, loadRadius: 1)
        
        let dummyMesh = CPUMeshData(
            vertices: [Vertex(position: SIMD3<Float>(0, 0, 0), color: SIMD4<Float>(1, 1, 1, 1))],
            indices: [0]
        )
        
        _ = system.spawnTile(coord: centerCoord, cpuMesh: dummyMesh, world: world)
        _ = system.spawnTile(coord: inRangeCoord, cpuMesh: dummyMesh, world: world)
        let outEntity = system.spawnTile(coord: outRangeCoord, cpuMesh: dummyMesh, world: world)
        
        #expect(system.activeTileEntities.count == 3)
        
        // Set camera coordinate directly to center of (100, 100)
        system.cameraCoordinate = centerCoord.centerCoordinate
        
        // Run update: tiles with Chebyshev distance > 1 should be evicted
        system.update(world: world, deltaTime: 1.0)
        
        #expect(system.activeTileEntities[centerCoord] != nil)
        #expect(system.activeTileEntities[inRangeCoord] != nil)
        #expect(system.activeTileEntities[outRangeCoord] == nil)
        #expect(system.activeTileEntities.count == 2)
        
        // Verify entity was destroyed in ECS world
        #expect(world.component(ofType: MapTileComponent.self, for: outEntity) == nil)
    }
    
    @Test("Origin recentering when camera moves beyond distance threshold")
    func testOriginRecentering() {
        let world = World()
        let startGPS = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let system = MapTileSystem(
            initialReference: startGPS,
            zoomLevel: 15,
            loadRadius: 1,
            recenterThresholdMeters: 5000.0 // 5 km threshold
        )
        
        let coord = TileCoordinate(coordinate: startGPS, zoom: 15)
        let dummyMesh = CPUMeshData(
            vertices: [Vertex(position: SIMD3<Float>(0, 0, 0), color: SIMD4<Float>(1, 1, 1, 1))],
            indices: [0]
        )
        _ = system.spawnTile(coord: coord, cpuMesh: dummyMesh, world: world)
        #expect(system.activeTileEntities.count == 1)
        
        // Move camera 15 km North (~0.135 degrees latitude)
        let farGPS = GPSCoordinate(latitude: 60.3000, longitude: 24.9384)
        system.cameraCoordinate = farGPS
        
        system.update(world: world, deltaTime: 1.0)
        
        // Reference origin must have recentered to farGPS
        #expect(system.referenceCoordinate.latitude == farGPS.latitude)
        #expect(system.referenceCoordinate.longitude == farGPS.longitude)
        
        // Old active tiles at startGPS must have been cleared for re-anchoring
        #expect(system.activeTileEntities[coord] == nil)
    }
    
    @Test("Async in-flight tile loading does not spawn stale tile when camera moves out of range")
    func testAsyncLoadingStaleCancellation() async throws {
        let world = World()
        let startCoord = TileCoordinate(zoom: 15, x: 100, y: 100)
        let system = MapTileSystem(initialReference: startCoord.centerCoordinate, zoomLevel: 15, loadRadius: 1)
        
        // Data provider with a small async suspension
        system.tileDataProvider = { coord in
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms delay
            return Data([0x00])
        }
        
        system.cameraCoordinate = startCoord.centerCoordinate
        system.update(world: world, deltaTime: 0.016)
        
        // Move camera 50 tiles away while tile (100, 100) is loading
        let farCoord = TileCoordinate(zoom: 15, x: 150, y: 150)
        system.cameraCoordinate = farCoord.centerCoordinate
        system.update(world: world, deltaTime: 0.016)
        
        // Wait for background tasks to complete
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Tile (100, 100) should NOT have been spawned because camera moved out of range
        #expect(system.activeTileEntities[startCoord] == nil)
    }
    
    @Test("Tile spawning with RoadComponent when roadMesh is present")
    func testTileSpawningWithRoadComponent() {
        let world = World()
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let system = MapTileSystem(initialReference: helsinki, zoomLevel: 15, loadRadius: 1)
        let coord = TileCoordinate(coordinate: helsinki, zoom: 15)
        
        let surfaceMesh = CPUMeshData(
            vertices: [Vertex(position: SIMD3<Float>(0, 0, 0), color: SIMD4<Float>(1, 1, 1, 1))],
            indices: [0]
        )
        let roadMesh = CPUMeshData(
            vertices: [
                Vertex(position: SIMD3<Float>(0, 0.05, 0), color: .one, texCoord: SIMD2<Float>(-1, 0.18), normal: SIMD3<Float>(0, 6.0, 1)),
                Vertex(position: SIMD3<Float>(0, 0.05, 0), color: .one, texCoord: SIMD2<Float>(1, 0.18), normal: SIMD3<Float>(0, 6.0, 1))
            ],
            indices: [0, 1]
        )
        let tileMeshData = TileMeshData(surfaceMesh: surfaceMesh, roadMesh: roadMesh)
        
        let entity = system.spawnTile(coord: coord, tileMeshData: tileMeshData, world: world)
        
        let roadComp = world.component(ofType: RoadComponent.self, for: entity)
        #expect(roadComp != nil)
        #expect(roadComp?.outlineWidth == 0.18)
        #expect(roadComp?.widthScale == 1.0)
    }
}
