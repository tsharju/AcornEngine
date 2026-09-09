import Foundation
import simd

/// Unique composite key for caching a clipped geometry part for a specific H3 cell and source tile coordinate.
public struct H3ClippedTileKey: Hashable, Sendable {
    public let h3Index: H3Index
    public let sourceTile: TileCoordinate

    public init(h3Index: H3Index, sourceTile: TileCoordinate) {
        self.h3Index = h3Index
        self.sourceTile = sourceTile
    }
}

/// ECS System that manages streaming, clipping, metric positioning, and assembly of hexagonal H3 map tiles
/// from square slippy vector map tiles.
///
/// Because H3 hexagons and square slippy tiles naturally do not align, an H3 tile is assembled in the ECS
/// from multiple geometry parts clipped from different overlapping source tiles.
/// Because source tiles load asynchronously at separate times, each H3 tile incrementally attaches
/// geometry parts as they arrive, maintaining partial visibility until all source tiles are loaded.
@MainActor
public class H3MapTileSystem: System {
    /// The reference GPS coordinate that corresponds to the game world origin (0, 0, 0).
    public private(set) var referenceCoordinate: GPSCoordinate

    /// Target H3 resolution for hexagonal game tiles (default: 8, edge length ~461m).
    public var h3Resolution: Int

    /// Slippy map zoom level for source tiles (default: 15).
    public var sourceZoomLevel: Int

    /// Radius of concentric hexagonal rings around the camera to maintain loaded (default: 1, 7 cells).
    public var loadRingRadius: Int

    /// Distance in meters the camera can move away from referenceCoordinate before origin recentering is triggered.
    public var recenterThresholdMeters: Double

    /// Asynchronous tile loader actor for fetching and decompressing MVT data.
    public let tileLoader: MapTileLoader

    /// Optional closure providing raw vector tile data for a given slippy tile coordinate.
    public var tileDataProvider: (@Sendable (TileCoordinate) async throws -> Data?)?

    /// Optional renderer used to generate GPU meshes.
    public var renderer: (any Renderer)?

    /// Optional custom mesh factory to construct `any Mesh` from `CPUMeshData`.
    public var meshFactory: (@MainActor (CPUMeshData) -> (any Mesh)?)?

    /// Current camera or player GPS coordinate used for H3 tile streaming calculations.
    public var cameraCoordinate: GPSCoordinate?

    /// Active loaded H3 tile entities keyed by their `H3Index`.
    public private(set) var activeH3Entities: [H3Index: Entity] = [:]

    /// Cache of processed source `TileMeshData` keyed by `TileCoordinate`.
    public private(set) var sourceTileCache: [TileCoordinate: TileMeshData] = [:]

    /// Cache of clipped `TileMeshData` keyed by `(H3Index, TileCoordinate)`.
    public private(set) var clippedPartCache: [H3ClippedTileKey: TileMeshData] = [:]

    /// Coordinates of source tiles that failed to load (to prevent unbounded retry task loops).
    public private(set) var failedSourceCoordinates: Set<TileCoordinate> = []

    /// Maximum number of source tiles to hold in cache before evicting unneeded entries (default 64).
    public var maxSourceTileCacheSize: Int = 64

    /// Maximum number of clipped geometry parts to hold in cache before evicting unneeded entries (default 384).
    public var maxClippedPartCacheSize: Int = 384

    /// Whether to generate and display hexagonal boundary outline meshes for H3 cells (default: true).
    public var showsCellBoundaries: Bool

    /// Color applied to H3 hexagonal cell boundary outline meshes.
    public var cellBoundaryColor: SIMD4<Float>

    private var pendingSourceCoordinates: Set<TileCoordinate> = []
    private var sourceLoadingTasks: [TileCoordinate: Task<Void, Never>] = [:]

    /// Whether there are asynchronous source tile loading tasks currently in flight.
    public var hasPendingLoads: Bool {
        !pendingSourceCoordinates.isEmpty || !sourceLoadingTasks.isEmpty
    }

    /// Awaits completion of all currently pending source tile loading tasks.
    public func waitForPendingLoads() async {
        while hasPendingLoads {
            let tasks = Array(sourceLoadingTasks.values)
            for task in tasks {
                _ = await task.result
            }
            await Task.yield()
        }
    }

    /// Clears recorded failure state for source tiles to permit retrying their loads.
    public func retryFailedSourceTiles() {
        failedSourceCoordinates.removeAll()
    }

    /// Initializes a new H3MapTileSystem.
    ///
    /// - Parameters:
    ///   - initialReference: Initial GPS coordinate mapped to world origin (0, 0, 0).
    ///   - h3Resolution: Hexagonal tile resolution (default 8).
    ///   - sourceZoomLevel: Slippy zoom level for source map tiles (default 15).
    ///   - loadRingRadius: Hexagonal ring radius around camera (default 1 = 7 cells).
    ///   - recenterThresholdMeters: Distance threshold before recentering (default 5000.0 m).
    ///   - roadConfiguration: Road rendering configuration (default `.carOnly`).
    ///   - tileLoader: Optional custom tile loader actor.
    ///   - renderer: Optional renderer for creating GPU meshes.
    ///   - showsCellBoundaries: Whether to render hexagonal cell boundary outlines (default: true).
    ///   - cellBoundaryColor: Tint color for hexagonal cell boundaries (default: neon cyan).
    public init(
        initialReference: GPSCoordinate,
        h3Resolution: Int = 8,
        sourceZoomLevel: Int = 15,
        loadRingRadius: Int = 1,
        recenterThresholdMeters: Double = 5000.0,
        roadConfiguration: RoadConfiguration = .carOnly,
        tileLoader: MapTileLoader? = nil,
        renderer: (any Renderer)? = nil,
        showsCellBoundaries: Bool = true,
        cellBoundaryColor: SIMD4<Float> = SIMD4<Float>(0.20, 0.85, 1.0, 0.85)
    ) {
        referenceCoordinate = initialReference
        self.h3Resolution = h3Resolution
        self.sourceZoomLevel = sourceZoomLevel
        self.loadRingRadius = loadRingRadius
        self.recenterThresholdMeters = recenterThresholdMeters
        self.tileLoader = tileLoader ?? MapTileLoader(roadConfiguration: roadConfiguration)
        self.renderer = renderer
        self.showsCellBoundaries = showsCellBoundaries
        self.cellBoundaryColor = cellBoundaryColor
    }

    deinit {
        for task in sourceLoadingTasks.values {
            task.cancel()
        }
    }

    // MARK: - Origin Recentering

    /// Recenters the map origin to a new GPS coordinate.
    /// Clears existing active tiles and cancels in-flight tasks so the map reloads
    /// with precise metric scale for the new location.
    public func recenterOrigin(to newReference: GPSCoordinate, world: World) {
        referenceCoordinate = newReference

        for (_, task) in sourceLoadingTasks {
            task.cancel()
        }
        sourceLoadingTasks.removeAll()
        pendingSourceCoordinates.removeAll()
        failedSourceCoordinates.removeAll()
        sourceTileCache.removeAll()
        clippedPartCache.removeAll()

        // Destroy all existing active H3 entities and their child geometry parts
        for (_, entity) in activeH3Entities {
            destroyH3TileEntity(entity, world: world)
        }
        activeH3Entities.removeAll()
    }

    /// Removes all active H3 tile entities and their child geometry parts from the ECS world.
    /// Preserves cached source tiles in `sourceTileCache` to avoid re-downloading vector tiles when toggling modes.
    public func clearActiveTiles(world: World) {
        for (_, task) in sourceLoadingTasks {
            task.cancel()
        }
        sourceLoadingTasks.removeAll()
        pendingSourceCoordinates.removeAll()
        failedSourceCoordinates.removeAll()
        for (_, entity) in activeH3Entities {
            destroyH3TileEntity(entity, world: world)
        }
        activeH3Entities.removeAll()
    }

    // MARK: - Update Loop

    /// Updates the system, checking camera position, streaming visible H3 cells,
    /// triggering asynchronous loads for missing source tiles, and evicting out-of-range tiles.
    public func update(world: World, deltaTime _: Double) {
        // 1. Determine active camera GPS coordinate
        var activeCameraGPS = cameraCoordinate
        if activeCameraGPS == nil {
            world.forEach(GPSPositionComponent.self) { _, gps in
                if activeCameraGPS == nil {
                    activeCameraGPS = gps.coordinate
                }
            }
        }

        guard let cameraGPS = activeCameraGPS else {
            return
        }

        // 2. Check if camera moved beyond recentering threshold
        let dist = distanceInMeters(from: referenceCoordinate, to: cameraGPS)
        if dist > recenterThresholdMeters {
            recenterOrigin(to: cameraGPS, world: world)
        }

        // 3. Compute target visible H3 cells
        let centerH3 = H3Index(coordinate: cameraGPS, resolution: h3Resolution)
        let visibleH3List = centerH3.neighbors(ring: loadRingRadius)
        let visibleH3Set = Set(visibleH3List)

        // 4. Evict H3 tiles that are out of range
        var toRemove = [H3Index]()
        for (h3Index, entity) in activeH3Entities {
            if !visibleH3Set.contains(h3Index) {
                destroyH3TileEntity(entity, world: world)
                toRemove.append(h3Index)
            }
        }
        for h3 in toRemove {
            activeH3Entities.removeValue(forKey: h3)
        }

        // 5. Ensure an H3 tile entity exists for each visible H3 cell
        for h3Index in visibleH3List {
            if activeH3Entities[h3Index] == nil {
                let h3Entity = createH3TileEntity(h3Index: h3Index, world: world)
                activeH3Entities[h3Index] = h3Entity

                // Immediately attach any source tiles already present in the cache
                if let h3Comp = world.component(ofType: H3TileComponent.self, for: h3Entity) {
                    for srcCoord in h3Comp.requiredSourceTiles {
                        if let cachedData = sourceTileCache[srcCoord] {
                            attachGeometryPart(
                                sourceTile: srcCoord,
                                tileMeshData: cachedData,
                                toH3Entity: h3Entity,
                                world: world
                            )
                        }
                    }
                }
            }
        }

        // 6. Request missing source slippy map tiles
        for (_, entity) in activeH3Entities {
            guard let h3Comp = world.component(ofType: H3TileComponent.self, for: entity) else {
                continue
            }
            for sourceCoord in h3Comp.requiredSourceTiles {
                if !h3Comp.loadedSourceTiles.contains(sourceCoord),
                   !h3Comp.failedSourceTiles.contains(sourceCoord),
                   sourceTileCache[sourceCoord] == nil,
                   !pendingSourceCoordinates.contains(sourceCoord),
                   !failedSourceCoordinates.contains(sourceCoord)
                {
                    startLoadingSourceTile(coord: sourceCoord, world: world)
                }
            }
        }
    }

    // MARK: - Spawning & Geometry Part Assembly

    /// Spawns a base H3 tile entity in the ECS world without attached geometry parts.
    @discardableResult
    public func spawnH3Tile(h3Index: H3Index, world: World) -> Entity {
        if let existing = activeH3Entities[h3Index] {
            destroyH3TileEntity(existing, world: world)
        }
        let entity = createH3TileEntity(h3Index: h3Index, world: world)
        activeH3Entities[h3Index] = entity
        return entity
    }

    /// Spawns an H3 tile entity and immediately attaches pre-computed source tile geometries.
    @discardableResult
    public func spawnH3Tile(
        h3Index: H3Index,
        sourceTiles: [(TileCoordinate, TileMeshData)],
        world: World
    ) -> Entity {
        let entity = spawnH3Tile(h3Index: h3Index, world: world)
        for (coord, meshData) in sourceTiles {
            sourceTileCache[coord] = meshData
            attachGeometryPart(
                sourceTile: coord,
                tileMeshData: meshData,
                toH3Entity: entity,
                world: world
            )
        }
        return entity
    }

    /// Destroys the specified H3 tile entity and all its child geometry parts from the ECS world.
    public func destroyH3Tile(_ h3Index: H3Index, world: World) {
        if let entity = activeH3Entities.removeValue(forKey: h3Index) {
            destroyH3TileEntity(entity, world: world)
        }
    }

    /// Destroys an H3 tile entity and all its child geometry parts from the ECS world.
    public func destroyH3Tile(entity: Entity, world: World) {
        if let h3Comp = world.component(ofType: H3TileComponent.self, for: entity) {
            activeH3Entities.removeValue(forKey: h3Comp.h3Index)
        }
        destroyH3TileEntity(entity, world: world)
    }

    /// Clips the source tile mesh data to the H3 cell and attaches it as a child entity in the ECS world.
    ///
    /// - Parameters:
    ///   - sourceTile: The slippy tile coordinate.
    ///   - tileMeshData: The unclipped source tile mesh data.
    ///   - h3Entity: The parent H3 tile entity.
    ///   - world: The ECS world.
    /// - Returns: The newly created child entity holding the clipped geometry part, or `nil` if no geometry intersected.
    @discardableResult
    public func attachGeometryPart(
        sourceTile: TileCoordinate,
        tileMeshData: TileMeshData,
        toH3Entity h3Entity: Entity,
        world: World
    ) -> Entity? {
        guard var h3Comp = world.component(ofType: H3TileComponent.self, for: h3Entity) else {
            return nil
        }

        // Remove previous part entity for this sourceTile if any
        if let existingPart = h3Comp.geometryPartEntities[sourceTile] {
            world.destroyEntity(existingPart)
            h3Comp.geometryPartEntities.removeValue(forKey: sourceTile)
        }

        // 1. Clip source tile mesh data against the target H3 cell (or retrieve from cache)
        let key = H3ClippedTileKey(h3Index: h3Comp.h3Index, sourceTile: sourceTile)
        let clippedPart: TileMeshData
        if let cached = clippedPartCache[key] {
            clippedPart = cached
        } else {
            clippedPart = H3GeometryClipper.clipTileToH3(
                tileMeshData: tileMeshData,
                sourceTile: sourceTile,
                targetH3: h3Comp.h3Index,
                referenceCoordinate: referenceCoordinate
            )
            clippedPartCache[key] = clippedPart
        }

        let hasSurface = !clippedPart.surfaceMesh.vertices.isEmpty
        let hasRoad = !clippedPart.roadMesh.vertices.isEmpty

        var partEntity: Entity? = nil
        if hasSurface || hasRoad {
            let child = world.createEntity()
            world.addComponent(ParentComponent(parent: h3Entity), to: child)
            world.addComponent(TransformComponent(position: .zero), to: child)

            if hasSurface, let mesh = createMesh(from: clippedPart.surfaceMesh) {
                world.addComponent(MeshComponent(mesh: mesh), to: child)
            }
            if hasRoad, let roadMesh = createMesh(from: clippedPart.roadMesh) {
                world.addComponent(RoadComponent(mesh: roadMesh), to: child)
            }

            world.addComponent(H3TileGeometryPartComponent(
                sourceTile: sourceTile,
                h3Index: h3Comp.h3Index,
                tileMeshData: clippedPart
            ), to: child)

            partEntity = child
            h3Comp.geometryPartEntities[sourceTile] = child
        }

        // 2. Update H3 tile component tracking
        h3Comp.loadedSourceTiles.insert(sourceTile)
        if h3Comp.isComplete {
            h3Comp.state = .complete
        } else {
            h3Comp.state = .loading(
                loadedParts: h3Comp.loadedSourceTiles.count,
                totalParts: h3Comp.requiredSourceTiles.count
            )
        }
        world.addComponent(h3Comp, to: h3Entity)

        return partEntity
    }

    // MARK: - Composite Mesh Generation

    /// Merges all currently loaded geometry parts of an H3 tile into a single consolidated `TileMeshData`.
    public func compositeMeshData(for h3Index: H3Index, world: World) -> TileMeshData? {
        guard let h3Entity = activeH3Entities[h3Index],
              let h3Comp = world.component(ofType: H3TileComponent.self, for: h3Entity)
        else {
            return nil
        }

        var combinedSurfaceVertices = [Vertex]()
        var combinedSurfaceIndices = [UInt32]()
        var combinedRoadVertices = [Vertex]()
        var combinedRoadIndices = [UInt32]()

        for (_, partEntity) in h3Comp.geometryPartEntities {
            guard let partComp = world.component(ofType: H3TileGeometryPartComponent.self, for: partEntity) else {
                continue
            }

            let surfBase = UInt32(combinedSurfaceVertices.count)
            combinedSurfaceVertices.append(contentsOf: partComp.tileMeshData.surfaceMesh.vertices)
            for idx in partComp.tileMeshData.surfaceMesh.indices {
                combinedSurfaceIndices.append(surfBase + idx)
            }

            let roadBase = UInt32(combinedRoadVertices.count)
            combinedRoadVertices.append(contentsOf: partComp.tileMeshData.roadMesh.vertices)
            for idx in partComp.tileMeshData.roadMesh.indices {
                combinedRoadIndices.append(roadBase + idx)
            }
        }

        return TileMeshData(
            surfaceMesh: CPUMeshData(vertices: combinedSurfaceVertices, indices: combinedSurfaceIndices),
            roadMesh: CPUMeshData(vertices: combinedRoadVertices, indices: combinedRoadIndices)
        )
    }

    /// Computes total number of attached clipped geometry parts across all active H3 tile entities.
    public func totalGeometryPartCount(world: World) -> Int {
        var count = 0
        for (_, entity) in activeH3Entities {
            if let comp = world.component(ofType: H3TileComponent.self, for: entity) {
                count += comp.geometryPartEntities.count
            }
        }
        return count
    }

    /// Dynamically toggles visibility of cell boundary meshes across all currently active H3 cells.
    public func setShowsCellBoundaries(_ show: Bool, world: World) {
        showsCellBoundaries = show
        for (h3Index, entity) in activeH3Entities {
            if show {
                if world.component(ofType: MeshComponent.self, for: entity) == nil,
                   let bMesh = createBoundaryMesh(for: h3Index)
                {
                    world.addComponent(MeshComponent(mesh: bMesh, color: cellBoundaryColor), to: entity)
                }
            } else {
                world.removeComponent(ofType: MeshComponent.self, from: entity)
            }
        }
    }

    /// Generates a thin hexagonal border ribbon mesh in local space for the given H3 cell.
    public func createBoundaryMesh(for h3Index: H3Index) -> (any Mesh)? {
        let latRad = referenceCoordinate.latitude * .pi / 180.0
        let cosLat = Float(max(0.001, cos(latRad)))
        let r = Float(h3Index.edgeLengthMeters) * cosLat
        let innerR = max(0.1, r - 3.5) // 3.5-meter wide border ribbon
        let yPos: Float = 0.25 // Above road and terrain surfaces to prevent z-fighting
        let normal = SIMD3<Float>(0, 1, 0)
        let color = SIMD4<Float>(1.0, 1.0, 1.0, 1.0) // Neutral white so MeshComponent color tints correctly

        var vertices = [Vertex]()
        var indices = [UInt32]()
        vertices.reserveCapacity(12)
        indices.reserveCapacity(36)

        for i in 0 ..< 6 {
            let angle = Float(i) * (.pi / 3.0)
            let cosA = cos(angle)
            let sinA = sin(angle)
            // Outer vertex
            vertices.append(Vertex(
                position: SIMD3<Float>(r * cosA, yPos, r * sinA),
                color: color,
                texCoord: SIMD2<Float>(Float(i), 1.0),
                normal: normal
            ))
            // Inner vertex
            vertices.append(Vertex(
                position: SIMD3<Float>(innerR * cosA, yPos, innerR * sinA),
                color: color,
                texCoord: SIMD2<Float>(Float(i), 0.0),
                normal: normal
            ))
        }

        for i in 0 ..< 6 {
            let next = (i + 1) % 6
            let out1 = UInt32(i * 2)
            let in1 = UInt32(i * 2 + 1)
            let out2 = UInt32(next * 2)
            let in2 = UInt32(next * 2 + 1)

            // Front-facing CCW winding with upward (+Y) normal
            indices.append(out1)
            indices.append(in2)
            indices.append(out2)

            indices.append(out1)
            indices.append(in1)
            indices.append(in2)
        }

        let cpuMesh = CPUMeshData(vertices: vertices, indices: indices)
        return createMesh(from: cpuMesh)
    }

    // MARK: - Private Loading Helpers

    private func createH3TileEntity(h3Index: H3Index, world: World) -> Entity {
        let entity = world.createEntity()
        let worldPos = h3Index.worldPosition(relativeTo: referenceCoordinate)
        world.addComponent(TransformComponent(position: worldPos), to: entity)

        let required = Set(h3Index.overlappingTileCoordinates(zoom: sourceZoomLevel))
        let comp = H3TileComponent(
            h3Index: h3Index,
            sourceZoomLevel: sourceZoomLevel,
            referenceLatitude: referenceCoordinate.latitude,
            requiredSourceTiles: required
        )
        world.addComponent(comp, to: entity)

        if showsCellBoundaries, let bMesh = createBoundaryMesh(for: h3Index) {
            world.addComponent(MeshComponent(mesh: bMesh, color: cellBoundaryColor), to: entity)
        }

        return entity
    }

    private func destroyH3TileEntity(_ entity: Entity, world: World) {
        if let h3Comp = world.component(ofType: H3TileComponent.self, for: entity) {
            for (_, partEntity) in h3Comp.geometryPartEntities {
                world.destroyEntity(partEntity)
            }
        }
        world.destroyEntity(entity)
    }

    private func startLoadingSourceTile(coord: TileCoordinate, world: World) {
        guard let dataProvider = tileDataProvider else { return }

        pendingSourceCoordinates.insert(coord)
        let refLat = referenceCoordinate.latitude
        let refCoord = referenceCoordinate
        let loader = tileLoader

        let task = Task { @MainActor [weak self] in
            do {
                guard let self = self else { return }
                guard let data = try await dataProvider(coord) else {
                    self.finishLoadingSourceTile(
                        coord: coord,
                        tileMeshData: nil,
                        preClippedParts: [:],
                        error: "Data provider returned nil for tile \(coord)",
                        world: world
                    )
                    return
                }

                if Task.isCancelled {
                    self.pendingSourceCoordinates.remove(coord)
                    self.sourceLoadingTasks.removeValue(forKey: coord)
                    return
                }

                let tileMeshData = await loader.processTileData(
                    data: data,
                    coordinate: coord,
                    referenceLatitude: refLat
                )

                if Task.isCancelled {
                    self.pendingSourceCoordinates.remove(coord)
                    self.sourceLoadingTasks.removeValue(forKey: coord)
                    return
                }

                // Identify active H3 cells needing this source tile
                var targetH3s: [H3Index] = []
                for (h3Index, h3Entity) in self.activeH3Entities {
                    if let comp = world.component(ofType: H3TileComponent.self, for: h3Entity),
                       comp.requiredSourceTiles.contains(coord),
                       !comp.loadedSourceTiles.contains(coord) {
                        targetH3s.append(h3Index)
                    }
                }

                // Pre-clip concurrently off @MainActor in a background task
                let preClipped: [H3Index: TileMeshData]
                if !targetH3s.isEmpty {
                    preClipped = await Task.detached(priority: .userInitiated) {
                        var clipped = [H3Index: TileMeshData]()
                        clipped.reserveCapacity(targetH3s.count)
                        for h3 in targetH3s {
                            clipped[h3] = H3GeometryClipper.clipTileToH3(
                                tileMeshData: tileMeshData,
                                sourceTile: coord,
                                targetH3: h3,
                                referenceCoordinate: refCoord
                            )
                        }
                        return clipped
                    }.value
                } else {
                    preClipped = [:]
                }

                if Task.isCancelled {
                    self.pendingSourceCoordinates.remove(coord)
                    self.sourceLoadingTasks.removeValue(forKey: coord)
                    return
                }

                self.finishLoadingSourceTile(
                    coord: coord,
                    tileMeshData: tileMeshData,
                    preClippedParts: preClipped,
                    error: nil,
                    world: world
                )
            } catch {
                self?.finishLoadingSourceTile(
                    coord: coord,
                    tileMeshData: nil,
                    preClippedParts: [:],
                    error: error.localizedDescription,
                    world: world
                )
            }
        }

        sourceLoadingTasks[coord] = task
    }

    private func finishLoadingSourceTile(
        coord: TileCoordinate,
        tileMeshData: TileMeshData?,
        preClippedParts: [H3Index: TileMeshData] = [:],
        error: String?,
        world: World
    ) {
        pendingSourceCoordinates.remove(coord)
        sourceLoadingTasks.removeValue(forKey: coord)

        if let error = error {
            failedSourceCoordinates.insert(coord)
            for (_, h3Entity) in activeH3Entities {
                guard var h3Comp = world.component(ofType: H3TileComponent.self, for: h3Entity) else {
                    continue
                }
                if h3Comp.requiredSourceTiles.contains(coord) {
                    h3Comp.failedSourceTiles.insert(coord)
                    if h3Comp.isComplete {
                        if h3Comp.loadedSourceTiles.isEmpty {
                            h3Comp.state = .failed("All required source tiles failed: \(error)")
                        } else {
                            h3Comp.state = .complete
                        }
                    } else {
                        h3Comp.state = .loading(
                            loadedParts: h3Comp.loadedSourceTiles.count,
                            totalParts: h3Comp.requiredSourceTiles.count
                        )
                    }
                    world.addComponent(h3Comp, to: h3Entity)
                }
            }
            return
        }

        guard let tileMeshData = tileMeshData else { return }
        sourceTileCache[coord] = tileMeshData

        // Populate pre-clipped geometry parts into cache
        for (h3Index, clippedData) in preClippedParts {
            let key = H3ClippedTileKey(h3Index: h3Index, sourceTile: coord)
            clippedPartCache[key] = clippedData
        }

        pruneSourceTileCacheIfNeeded(world: world)

        // Find all active H3 tile entities that need this source tile
        for (_, h3Entity) in activeH3Entities {
            guard let h3Comp = world.component(ofType: H3TileComponent.self, for: h3Entity) else {
                continue
            }
            if h3Comp.requiredSourceTiles.contains(coord), !h3Comp.loadedSourceTiles.contains(coord) {
                attachGeometryPart(
                    sourceTile: coord,
                    tileMeshData: tileMeshData,
                    toH3Entity: h3Entity,
                    world: world
                )
            }
        }
    }

    private func pruneSourceTileCacheIfNeeded(world: World) {
        if sourceTileCache.count > maxSourceTileCacheSize {
            var needed = Set<TileCoordinate>()
            for (_, entity) in activeH3Entities {
                if let h3Comp = world.component(ofType: H3TileComponent.self, for: entity) {
                    needed.formUnion(h3Comp.requiredSourceTiles)
                }
            }
            for coord in sourceTileCache.keys {
                if !needed.contains(coord) {
                    sourceTileCache.removeValue(forKey: coord)
                    clippedPartCache = clippedPartCache.filter { $0.key.sourceTile != coord }
                    if sourceTileCache.count <= maxSourceTileCacheSize {
                        break
                    }
                }
            }
        }
        if clippedPartCache.count > maxClippedPartCacheSize {
            let activeH3Set = Set(activeH3Entities.keys)
            clippedPartCache = clippedPartCache.filter { activeH3Set.contains($0.key.h3Index) }
        }
    }

    private func createMesh(from cpuMesh: CPUMeshData) -> (any Mesh)? {
        if let factory = meshFactory {
            return factory(cpuMesh)
        }
        if let renderer = renderer {
            return renderer.createMesh(meshData: cpuMesh)
        }
        return CPUBackedMesh(cpuData: cpuMesh)
    }

    private func distanceInMeters(from c1: GPSCoordinate, to c2: GPSCoordinate) -> Double {
        let lat1Rad = c1.latitude * .pi / 180.0
        let lat2Rad = c2.latitude * .pi / 180.0
        let dLat = lat2Rad - lat1Rad
        let dLon = (c2.longitude - c1.longitude) * .pi / 180.0

        let meanLat = (lat1Rad + lat2Rad) / 2.0
        let dx = dLon * TileCoordinate.earthEquatorialRadius * cos(meanLat)
        let dz = dLat * TileCoordinate.earthEquatorialRadius
        return sqrt(dx * dx + dz * dz)
    }
}
