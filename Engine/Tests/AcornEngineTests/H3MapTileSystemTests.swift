@testable import AcornEngine
import Foundation
import simd
import Testing

@MainActor
struct H3MapTileSystemTests {
    @Test("H3 tile spawning and multi-geometry attachment in ECS World")
    func h3TileSpawningWithMultipleGeometries() {
        let world = World()
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let system = H3MapTileSystem(initialReference: helsinki, h3Resolution: 9, sourceZoomLevel: 15)

        let h3 = H3Index(coordinate: helsinki, resolution: 9)
        let h3Entity = system.spawnH3Tile(h3Index: h3, world: world)

        // H3 tile entity should have TransformComponent and H3TileComponent
        let transform = world.component(ofType: TransformComponent.self, for: h3Entity)
        let h3Comp = world.component(ofType: H3TileComponent.self, for: h3Entity)
        #expect(transform != nil)
        #expect(h3Comp != nil)
        #expect(h3Comp?.h3Index == h3)
        #expect(h3Comp?.state == .loading(loadedParts: 0, totalParts: h3Comp?.requiredSourceTiles.count ?? 0))

        // Pick 2 required source tiles
        let requiredList = Array(h3Comp!.requiredSourceTiles)
        #expect(requiredList.count >= 1)
        let tile1 = requiredList[0]

        // Create dummy mesh for tile 1 centered at H3 center in tile space
        let h3World = h3.worldPosition(relativeTo: helsinki)
        let tile1World = tile1.worldPosition(relativeTo: helsinki)
        let c1X = h3World.x - tile1World.x
        let c1Z = h3World.z - tile1World.z

        let mesh1 = CPUMeshData(
            vertices: [
                Vertex(position: SIMD3<Float>(c1X - 5, 0, c1Z - 5), color: .one),
                Vertex(position: SIMD3<Float>(c1X + 5, 0, c1Z - 5), color: .one),
                Vertex(position: SIMD3<Float>(c1X, 0, c1Z + 5), color: .one),
            ],
            indices: [0, 1, 2]
        )
        let tileMeshData1 = TileMeshData(surfaceMesh: mesh1, roadMesh: CPUMeshData())

        // Attach part 1
        let part1Entity = system.attachGeometryPart(
            sourceTile: tile1,
            tileMeshData: tileMeshData1,
            toH3Entity: h3Entity,
            world: world
        )
        #expect(part1Entity != nil)

        // Verify child entity structure
        let parentComp1 = world.component(ofType: ParentComponent.self, for: part1Entity!)
        let meshComp1 = world.component(ofType: MeshComponent.self, for: part1Entity!)
        let partComp1 = world.component(ofType: H3TileGeometryPartComponent.self, for: part1Entity!)

        #expect(parentComp1?.parent == h3Entity)
        #expect(meshComp1 != nil)
        #expect(partComp1?.sourceTile == tile1)
        #expect(partComp1?.h3Index == h3)

        // Check updated H3 tile component
        let updatedComp = world.component(ofType: H3TileComponent.self, for: h3Entity)
        #expect(updatedComp?.loadedSourceTiles.contains(tile1) == true)
        #expect(updatedComp?.geometryPartEntities[tile1] == part1Entity)
        #expect((updatedComp?.coverageFraction ?? 0) > 0.0)

        // Verify world matrix calculation walks parent transform
        let childWorldMat = world.worldMatrix(for: part1Entity!)
        let parentWorldMat = world.worldMatrix(for: h3Entity)
        #expect(childWorldMat == parentWorldMat)
    }

    @Test("Incremental loading lifecycle from separate source tiles")
    func incrementalLoadingLifecycle() {
        let world = World()
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let system = H3MapTileSystem(initialReference: helsinki, h3Resolution: 9, sourceZoomLevel: 15)

        let h3 = H3Index(coordinate: helsinki, resolution: 9)

        // Specify exactly 2 required source tiles
        let tileA = TileCoordinate(zoom: 15, x: 100, y: 100)
        let tileB = TileCoordinate(zoom: 15, x: 101, y: 100)
        let entity = world.createEntity()
        let comp = H3TileComponent(
            h3Index: h3,
            sourceZoomLevel: 15,
            referenceLatitude: helsinki.latitude,
            requiredSourceTiles: [tileA, tileB]
        )
        world.addComponent(comp, to: entity)
        world.addComponent(TransformComponent(position: h3.worldPosition(relativeTo: helsinki)), to: entity)

        // Initial state: loading (0 of 2)
        #expect(comp.state == .loading(loadedParts: 0, totalParts: 2))
        #expect(!comp.isComplete)
        #expect(comp.coverageFraction == 0.0)

        // Tile A arrives at time t1
        let dummyMesh = CPUMeshData(
            vertices: [
                Vertex(position: .zero, color: .one),
                Vertex(position: SIMD3<Float>(1, 0, 0), color: .one),
                Vertex(position: SIMD3<Float>(0, 0, 1), color: .one),
            ],
            indices: [0, 1, 2]
        )
        system.attachGeometryPart(sourceTile: tileA, tileMeshData: TileMeshData(surfaceMesh: dummyMesh), toH3Entity: entity, world: world)

        let stateAfterA = world.component(ofType: H3TileComponent.self, for: entity)
        #expect(stateAfterA?.state == .loading(loadedParts: 1, totalParts: 2))
        #expect(!stateAfterA!.isComplete)
        #expect(stateAfterA?.coverageFraction == 0.5)

        // Tile B arrives at time t2
        system.attachGeometryPart(sourceTile: tileB, tileMeshData: TileMeshData(surfaceMesh: dummyMesh), toH3Entity: entity, world: world)

        let stateAfterB = world.component(ofType: H3TileComponent.self, for: entity)
        #expect(stateAfterB?.state == .complete)
        #expect(stateAfterB!.isComplete)
        #expect(stateAfterB?.coverageFraction == 1.0)
        #expect(stateAfterB?.loadedSourceTiles == [tileA, tileB])
    }

    @Test("Composite mesh generation merges all child geometry parts")
    func compositeMeshGeneration() {
        let world = World()
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let system = H3MapTileSystem(initialReference: helsinki, h3Resolution: 9, sourceZoomLevel: 15)

        let h3 = H3Index(coordinate: helsinki, resolution: 9)
        let overlapping = Array(h3.overlappingTileCoordinates(zoom: 15))
        let tileA = overlapping[0]
        let tileB = overlapping.count > 1 ? overlapping[1] : TileCoordinate(zoom: 15, x: tileA.x + 1, y: tileA.y)

        let h3World = h3.worldPosition(relativeTo: helsinki)
        let tileAWorld = tileA.worldPosition(relativeTo: helsinki)
        let cAX = h3World.x - tileAWorld.x
        let cAZ = h3World.z - tileAWorld.z

        let meshA = CPUMeshData(
            vertices: [
                Vertex(position: SIMD3<Float>(cAX - 5, 0, cAZ - 5), color: .one),
                Vertex(position: SIMD3<Float>(cAX + 5, 0, cAZ - 5), color: .one),
                Vertex(position: SIMD3<Float>(cAX, 0, cAZ + 5), color: .one),
            ],
            indices: [0, 1, 2]
        )

        let tileBWorld = tileB.worldPosition(relativeTo: helsinki)
        let cBX = h3World.x - tileBWorld.x
        let cBZ = h3World.z - tileBWorld.z

        let meshB = CPUMeshData(
            vertices: [
                Vertex(position: SIMD3<Float>(cBX - 5, 0, cBZ - 5), color: .one),
                Vertex(position: SIMD3<Float>(cBX + 5, 0, cBZ - 5), color: .one),
                Vertex(position: SIMD3<Float>(cBX, 0, cBZ + 5), color: .one),
            ],
            indices: [0, 1, 2]
        )

        system.spawnH3Tile(
            h3Index: h3,
            sourceTiles: [
                (tileA, TileMeshData(surfaceMesh: meshA)),
                (tileB, TileMeshData(surfaceMesh: meshB)),
            ],
            world: world
        )

        let composite = system.compositeMeshData(for: h3, world: world)
        #expect(composite != nil)
        // Two parts with 3 vertices and 3 indices each
        #expect(composite?.surfaceMesh.vertices.count == 6)
        #expect(composite?.surfaceMesh.indices.count == 6)
        // Indices of second part should be offset by 3
        #expect(composite?.surfaceMesh.indices == [0, 1, 2, 3, 4, 5])
    }

    @Test("H3 tile eviction destroys parent entity and all child geometry parts")
    func h3TileEviction() {
        let world = World()
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let system = H3MapTileSystem(initialReference: helsinki, h3Resolution: 9, sourceZoomLevel: 15, loadRingRadius: 1)

        let h3Center = H3Index(coordinate: helsinki, resolution: 9)
        let overlapping = Array(h3Center.overlappingTileCoordinates(zoom: 15))
        let tileA = overlapping[0]
        let h3World = h3Center.worldPosition(relativeTo: helsinki)
        let tileAWorld = tileA.worldPosition(relativeTo: helsinki)
        let cAX = h3World.x - tileAWorld.x
        let cAZ = h3World.z - tileAWorld.z

        let dummyMesh = CPUMeshData(
            vertices: [
                Vertex(position: SIMD3<Float>(cAX - 5, 0, cAZ - 5), color: .one),
                Vertex(position: SIMD3<Float>(cAX + 5, 0, cAZ - 5), color: .one),
                Vertex(position: SIMD3<Float>(cAX, 0, cAZ + 5), color: .one),
            ],
            indices: [0, 1, 2]
        )

        // Spawn center H3 tile
        let h3Entity = system.spawnH3Tile(
            h3Index: h3Center,
            sourceTiles: [(tileA, TileMeshData(surfaceMesh: dummyMesh))],
            world: world
        )
        let h3Comp = world.component(ofType: H3TileComponent.self, for: h3Entity)!
        let childPartEntity = h3Comp.geometryPartEntities[tileA]!

        #expect(system.activeH3Entities.count == 1)
        #expect(world.component(ofType: H3TileComponent.self, for: h3Entity) != nil)
        #expect(world.component(ofType: H3TileGeometryPartComponent.self, for: childPartEntity) != nil)

        // Move camera far away (e.g. 10 km north)
        let farGPS = GPSCoordinate(latitude: 60.2600, longitude: 24.9384)
        system.cameraCoordinate = farGPS

        system.update(world: world, deltaTime: 1.0)

        // Old H3 tile should be evicted
        #expect(system.activeH3Entities[h3Center] == nil)
        // Both parent H3 entity and child geometry entity must be destroyed in world
        #expect(world.component(ofType: H3TileComponent.self, for: h3Entity) == nil)
        #expect(world.component(ofType: H3TileGeometryPartComponent.self, for: childPartEntity) == nil)
    }

    @Test("Origin recentering clears active H3 entities and re-anchors coordinates")
    func originRecentering() {
        let world = World()
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let system = H3MapTileSystem(
            initialReference: helsinki,
            h3Resolution: 9,
            sourceZoomLevel: 15,
            recenterThresholdMeters: 5000.0
        )

        let h3 = H3Index(coordinate: helsinki, resolution: 9)
        _ = system.spawnH3Tile(h3Index: h3, world: world)
        #expect(system.activeH3Entities.count == 1)

        // Move camera 20 km away
        let farGPS = GPSCoordinate(latitude: 60.3500, longitude: 24.9384)
        system.cameraCoordinate = farGPS

        system.update(world: world, deltaTime: 1.0)

        // Reference origin should have recentered
        #expect(system.referenceCoordinate.latitude == farGPS.latitude)
        #expect(system.referenceCoordinate.longitude == farGPS.longitude)
        // Old tiles at helsinki must be cleared
        #expect(system.activeH3Entities[h3] == nil)
    }

    @Test("Async source tile loading attaches clipped geometry parts across multiple H3 tiles")
    func asyncSourceTileStreaming() async throws {
        let world = World()
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let system = H3MapTileSystem(
            initialReference: helsinki,
            h3Resolution: 9,
            sourceZoomLevel: 15,
            loadRingRadius: 0 // Just center cell
        )

        // Mock data provider returning empty byte payload
        system.tileDataProvider = { _ in
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            return Data()
        }

        system.cameraCoordinate = helsinki
        system.update(world: world, deltaTime: 0.016)

        let centerH3 = H3Index(coordinate: helsinki, resolution: 9)
        #expect(system.activeH3Entities[centerH3] != nil)

        // Wait deterministically for asynchronous loading tasks to complete
        await system.waitForPendingLoads()

        // Verify source tile cache contains the loaded tiles
        #expect(!system.sourceTileCache.isEmpty)
        #expect(!system.hasPendingLoads)
    }

    @Test("Source tile load failure is tracked without infinite retry loop")
    func sourceTileLoadFailureHandlingAndNoInfiniteLoop() async throws {
        let world = World()
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let system = H3MapTileSystem(
            initialReference: helsinki,
            h3Resolution: 9,
            sourceZoomLevel: 15,
            loadRingRadius: 0
        )

        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var count = 0
            func increment() {
                lock.lock()
                count += 1
                lock.unlock()
            }

            func value() -> Int {
                lock.lock()
                defer { lock.unlock() }
                return count
            }
        }

        let counter = Counter()
        system.tileDataProvider = { _ in
            counter.increment()
            // Simulate tile server returning nil (e.g. 404 or empty unpopulated region)
            return nil
        }

        system.cameraCoordinate = helsinki
        system.update(world: world, deltaTime: 0.016)

        let centerH3 = H3Index(coordinate: helsinki, resolution: 9)
        let h3Entity = system.activeH3Entities[centerH3]
        #expect(h3Entity != nil)

        // Await task completion
        await system.waitForPendingLoads()

        // Check component state: tile failed
        let h3Comp = world.component(ofType: H3TileComponent.self, for: h3Entity!)
        #expect(h3Comp != nil)
        #expect(h3Comp?.hasFailures == true)
        #expect(!system.failedSourceCoordinates.isEmpty)
        #expect(h3Comp?.isComplete == true)
        if case .failed = h3Comp?.state {
            // Expected failure state
        } else {
            Issue.record("Expected state to be failed, but got \(String(describing: h3Comp?.state))")
        }

        let countAfterFirstLoad = counter.value()
        #expect(countAfterFirstLoad > 0)

        // Next frame update must NOT re-request the failed source tile (no infinite loop)
        system.update(world: world, deltaTime: 0.016)
        #expect(counter.value() == countAfterFirstLoad)
        #expect(!system.hasPendingLoads)

        // Calling retryFailedSourceTiles clears failure record so loads can be retried
        system.retryFailedSourceTiles()
        #expect(system.failedSourceCoordinates.isEmpty)
    }

    @Test("Public destroyH3Tile cleans up parent and all child part entities")
    func publicDestroyH3Tile() {
        let world = World()
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let system = H3MapTileSystem(initialReference: helsinki, h3Resolution: 9, sourceZoomLevel: 15)

        let h3 = H3Index(coordinate: helsinki, resolution: 9)
        let tile = TileCoordinate(coordinate: helsinki, zoom: 15)
        let h3World = h3.worldPosition(relativeTo: helsinki)
        let tileWorld = tile.worldPosition(relativeTo: helsinki)
        let cX = h3World.x - tileWorld.x
        let cZ = h3World.z - tileWorld.z

        let dummyMesh = CPUMeshData(
            vertices: [
                Vertex(position: SIMD3<Float>(cX - 5, 0, cZ - 5), color: .one),
                Vertex(position: SIMD3<Float>(cX + 5, 0, cZ - 5), color: .one),
                Vertex(position: SIMD3<Float>(cX, 0, cZ + 5), color: .one),
            ],
            indices: [0, 1, 2]
        )

        let entity = system.spawnH3Tile(h3Index: h3, sourceTiles: [(tile, TileMeshData(surfaceMesh: dummyMesh))], world: world)
        let comp = world.component(ofType: H3TileComponent.self, for: entity)!
        let childEntity = comp.geometryPartEntities[tile]!

        #expect(system.activeH3Entities[h3] != nil)
        #expect(world.component(ofType: H3TileComponent.self, for: entity) != nil)
        #expect(world.component(ofType: H3TileGeometryPartComponent.self, for: childEntity) != nil)

        // Destroy H3 tile using public API
        system.destroyH3Tile(h3, world: world)

        #expect(system.activeH3Entities[h3] == nil)
        #expect(world.component(ofType: H3TileComponent.self, for: entity) == nil)
        #expect(world.component(ofType: H3TileGeometryPartComponent.self, for: childEntity) == nil)
    }

    @Test("H3 boundary ribbon mesh generates upward +Y normals and scales by cos(latitude)")
    func createBoundaryMeshGeometryAndWinding() {
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let system = H3MapTileSystem(initialReference: helsinki, h3Resolution: 9)

        let h3 = H3Index(coordinate: helsinki, resolution: 9)
        guard let mesh = system.createBoundaryMesh(for: h3) else {
            Issue.record("Failed to create boundary mesh")
            return
        }

        guard let cpuBacked = mesh as? CPUBackedMesh else {
            Issue.record("Boundary mesh is not a CPUBackedMesh")
            return
        }
        let cpuMesh = cpuBacked.cpuData

        // 12 vertices (6 outer, 6 inner) and 36 indices (12 triangles)
        #expect(cpuMesh.vertices.count == 12)
        #expect(cpuMesh.indices.count == 36)

        // Verify radius scaling: outer vertices must be at r = edgeLength * cos(latitude)
        let cosLat = Float(cos(helsinki.latitude * .pi / 180.0))
        let expectedR = Float(h3.edgeLengthMeters) * cosLat
        let expectedInnerR = max(0.1, expectedR - 3.5)

        for i in 0 ..< 6 {
            let outerV = cpuMesh.vertices[i * 2]
            let innerV = cpuMesh.vertices[i * 2 + 1]

            let outerDist = hypot(outerV.position.x, outerV.position.z)
            let innerDist = hypot(innerV.position.x, innerV.position.z)

            #expect(abs(outerDist - expectedR) < 0.1)
            #expect(abs(innerDist - expectedInnerR) < 0.1)
            #expect(outerV.position.y == 0.25)
            #expect(innerV.position.y == 0.25)
        }

        // Verify counter-clockwise winding order with strictly positive Y geometric normal (+Y)
        for triIdx in stride(from: 0, to: cpuMesh.indices.count, by: 3) {
            let i0 = Int(cpuMesh.indices[triIdx])
            let i1 = Int(cpuMesh.indices[triIdx + 1])
            let i2 = Int(cpuMesh.indices[triIdx + 2])

            let v0 = cpuMesh.vertices[i0].position
            let v1 = cpuMesh.vertices[i1].position
            let v2 = cpuMesh.vertices[i2].position

            let e1 = v1 - v0
            let e2 = v2 - v0
            let zx: Float = e1.z * e2.x
            let xz: Float = e1.x * e2.z
            let crossY: Float = zx - xz

            // Normal must point upward (+Y > 0)
            #expect(crossY > 0.0)
        }
    }

    @Test("Dynamic boundary visibility toggle updates MeshComponent on active entities")
    func boundaryVisibilityToggle() {
        let world = World()
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let system = H3MapTileSystem(initialReference: helsinki, h3Resolution: 9, showsCellBoundaries: true)

        let h3 = H3Index(coordinate: helsinki, resolution: 9)
        let entity = system.spawnH3Tile(h3Index: h3, world: world)

        // Initially shown
        #expect(world.component(ofType: MeshComponent.self, for: entity) != nil)

        // Toggle OFF
        system.setShowsCellBoundaries(false, world: world)
        #expect(!system.showsCellBoundaries)
        #expect(world.component(ofType: MeshComponent.self, for: entity) == nil)

        // Toggle back ON
        system.setShowsCellBoundaries(true, world: world)
        #expect(system.showsCellBoundaries)
        #expect(world.component(ofType: MeshComponent.self, for: entity) != nil)
    }

    @Test("Clipped part cache hits on subsequent attachments and clears on origin recenter")
    func clippedPartCacheHitAndPurge() {
        let world = World()
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384)
        let system = H3MapTileSystem(initialReference: helsinki, h3Resolution: 9, sourceZoomLevel: 15)

        let h3 = H3Index(coordinate: helsinki, resolution: 9)
        let tile = TileCoordinate(coordinate: helsinki, zoom: 15)

        let h3World = h3.worldPosition(relativeTo: helsinki)
        let tileWorldPos = tile.worldPosition(relativeTo: helsinki)
        let cX = h3World.x - tileWorldPos.x
        let cZ = h3World.z - tileWorldPos.z

        let surfaceMesh = CPUMeshData(
            vertices: [
                Vertex(position: SIMD3<Float>(cX - 5, 0, cZ - 5), color: .one),
                Vertex(position: SIMD3<Float>(cX + 5, 0, cZ - 5), color: .one),
                Vertex(position: SIMD3<Float>(cX, 0, cZ + 5), color: .one),
            ],
            indices: [0, 1, 2]
        )
        let meshData = TileMeshData(surfaceMesh: surfaceMesh, roadMesh: CPUMeshData())

        #expect(system.clippedPartCache.isEmpty)

        // 1. Initial spawn & attach
        let entity1 = system.spawnH3Tile(h3Index: h3, sourceTiles: [(tile, meshData)], world: world)
        #expect(system.clippedPartCache.count == 1)
        let key = H3ClippedTileKey(h3Index: h3, sourceTile: tile)
        #expect(system.clippedPartCache[key] != nil)

        // 2. Destroy and re-spawn: attach should hit clippedPartCache
        system.destroyH3Tile(entity: entity1, world: world)
        let entity2 = system.spawnH3Tile(h3Index: h3, world: world)
        let partEntity = system.attachGeometryPart(
            sourceTile: tile,
            tileMeshData: meshData,
            toH3Entity: entity2,
            world: world
        )
        #expect(partEntity != nil)
        #expect(system.clippedPartCache.count == 1) // Still 1 entry (hit cache)

        // 3. Recentering should clear clippedPartCache
        let newOrigin = GPSCoordinate(latitude: 60.2000, longitude: 24.9500)
        system.recenterOrigin(to: newOrigin, world: world)
        #expect(system.clippedPartCache.isEmpty)
    }
}
