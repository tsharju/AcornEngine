import Foundation
import simd

/// A lightweight Mesh implementation backed by CPU memory for headless environments and tests.
public struct CPUBackedMesh: Mesh, Sendable {
    public var vertexCount: Int { cpuData.vertices.count }
    public var indexCount: Int { cpuData.indices.count }
    public var cpuData: CPUMeshData
    
    #if DEBUG
    public var vertices: [Vertex] { cpuData.vertices }
    #endif
    
    public init(cpuData: CPUMeshData) {
        self.cpuData = cpuData
    }
}

/// ECS System that manages streaming, metric positioning, origin recentering, and lifecycle of 3D Mapbox vector tiles.
@MainActor
public class MapTileSystem: System {
    /// The reference GPS coordinate that corresponds to the game world origin (0, 0, 0).
    public private(set) var referenceCoordinate: GPSCoordinate
    
    /// Slippy map zoom level for vector tiles (e.g. zoom 15 or 16 for 3D buildings).
    public var zoomLevel: Int
    
    /// Radius of tiles around the camera to maintain loaded (in Chebyshev tile units).
    public var loadRadius: Int
    
    /// Distance in meters the camera can move away from referenceCoordinate before origin recentering is triggered.
    public var recenterThresholdMeters: Double
    
    /// Asynchronous tile loader actor.
    public let tileLoader: MapTileLoader
    
    /// Optional closure providing raw vector tile data for a given tile coordinate.
    public var tileDataProvider: (@Sendable (TileCoordinate) async throws -> Data?)?
    
    /// Optional renderer used to generate GPU meshes.
    public var renderer: (any Renderer)?
    
    /// Optional custom mesh factory to construct `any Mesh` from `CPUMeshData`.
    public var meshFactory: (@MainActor (CPUMeshData) -> (any Mesh)?)?
    
    /// Current camera or player GPS coordinate used for tile streaming calculations.
    public var cameraCoordinate: GPSCoordinate?
    
    /// Active loaded tile entities keyed by their TileCoordinate.
    public private(set) var activeTileEntities: [TileCoordinate: Entity] = [:]
    
    private var pendingCoordinates: Set<TileCoordinate> = []
    private var loadingTasks: [TileCoordinate: Task<Void, Never>] = [:]
    
    /// Initializes a new MapTileSystem.
    /// - Parameters:
    ///   - initialReference: The initial GPS coordinate mapped to world origin (0, 0, 0).
    ///   - zoomLevel: Tile zoom level (default 15).
    ///   - loadRadius: Tile load radius around camera (default 1).
    ///   - recenterThresholdMeters: Distance threshold before recentering the origin (default 5000.0 m).
    ///   - tileLoader: TileLoader actor instance.
    ///   - renderer: Optional renderer for creating GPU meshes.
    public init(
        initialReference: GPSCoordinate,
        zoomLevel: Int = 15,
        loadRadius: Int = 1,
        recenterThresholdMeters: Double = 5000.0,
        tileLoader: MapTileLoader = MapTileLoader(),
        renderer: (any Renderer)? = nil
    ) {
        self.referenceCoordinate = initialReference
        self.zoomLevel = zoomLevel
        self.loadRadius = loadRadius
        self.recenterThresholdMeters = recenterThresholdMeters
        self.tileLoader = tileLoader
        self.renderer = renderer
    }
    
    deinit {
        for task in loadingTasks.values {
            task.cancel()
        }
    }
    
    /// Recenters the map origin to a new GPS coordinate.
    /// Clears existing active tiles and cancels in-flight tasks so the map reloads
    /// with the precise metric scale for the new location.
    public func recenterOrigin(to newReference: GPSCoordinate, world: World) {
        self.referenceCoordinate = newReference
        
        // Cancel all pending loading tasks
        for (_, task) in loadingTasks {
            task.cancel()
        }
        loadingTasks.removeAll()
        pendingCoordinates.removeAll()
        
        // Destroy all existing active tile entities
        for (_, entity) in activeTileEntities {
            world.destroyEntity(entity)
        }
        activeTileEntities.removeAll()
    }
    
    /// Updates the system, checking camera position, triggering recentering if needed,
    /// evicting out-of-range tiles, and streaming new visible tiles.
    public func update(world: World, deltaTime: Double) {
        // 1. Determine active camera GPS coordinate
        var activeCameraGPS = self.cameraCoordinate
        if activeCameraGPS == nil {
            // Find first entity with GPSPositionComponent (typically player or camera)
            world.forEach(GPSPositionComponent.self) { entity, gps in
                if activeCameraGPS == nil {
                    activeCameraGPS = gps.coordinate
                }
            }
        }
        
        guard let cameraGPS = activeCameraGPS else {
            return
        }
        
        // 2. Check if camera has moved beyond recenter threshold from referenceCoordinate
        let dist = distanceInMeters(from: referenceCoordinate, to: cameraGPS)
        if dist > recenterThresholdMeters {
            recenterOrigin(to: cameraGPS, world: world)
        }
        
        // 3. Compute target visible tiles
        let centerTile = TileCoordinate(coordinate: cameraGPS, zoom: zoomLevel)
        let visibleTileList = centerTile.neighbors(radius: loadRadius)
        let visibleTileSet = Set(visibleTileList)
        
        // 4. Evict tiles that are out of range or on an old zoom level
        var toRemove = [TileCoordinate]()
        for (coord, entity) in activeTileEntities {
            if !visibleTileSet.contains(coord) {
                world.destroyEntity(entity)
                toRemove.append(coord)
            }
        }
        for coord in toRemove {
            activeTileEntities.removeValue(forKey: coord)
        }
        
        // 5. Request visible tiles that are not yet loaded or pending
        for coord in visibleTileList {
            if activeTileEntities[coord] == nil && !pendingCoordinates.contains(coord) {
                startLoadingTile(coord: coord, world: world)
            }
        }
    }
    
    /// Spawns a tile directly from pre-computed CPUMeshData (useful for synchronous tests or instant loading).
    @discardableResult
    public func spawnTile(coord: TileCoordinate, cpuMesh: CPUMeshData, world: World) -> Entity {
        // Destroy existing entity if any
        if let existing = activeTileEntities[coord] {
            world.destroyEntity(existing)
        }
        
        let entity = world.createEntity()
        let worldPos = coord.worldPosition(relativeTo: referenceCoordinate)
        world.addComponent(TransformComponent(position: worldPos), to: entity)
        
        let mesh = createMesh(from: cpuMesh)
        if let mesh = mesh {
            world.addComponent(MeshComponent(mesh: mesh), to: entity)
        }
        
        let (widthMeters, heightMeters) = coord.groundDimensions(atLatitude: referenceCoordinate.latitude)
        let tileComp = MapTileComponent(
            coordinate: coord,
            referenceLatitude: referenceCoordinate.latitude,
            groundDimensions: (widthMeters, heightMeters),
            state: .loaded
        )
        world.addComponent(tileComp, to: entity)
        
        activeTileEntities[coord] = entity
        return entity
    }
    
    private func startLoadingTile(coord: TileCoordinate, world: World) {
        guard let dataProvider = self.tileDataProvider else { return }
        
        pendingCoordinates.insert(coord)
        let refLat = referenceCoordinate.latitude
        let loader = self.tileLoader
        
        let task = Task { @MainActor [weak self] in
            do {
                guard let data = try await dataProvider(coord) else {
                    self?.finishLoading(coord: coord, cpuMesh: nil, world: world)
                    return
                }
                
                if Task.isCancelled {
                    self?.pendingCoordinates.remove(coord)
                    self?.loadingTasks.removeValue(forKey: coord)
                    return
                }
                
                let cpuMesh = await loader.processTile(
                    data: data,
                    coordinate: coord,
                    referenceLatitude: refLat
                )
                
                if Task.isCancelled {
                    self?.pendingCoordinates.remove(coord)
                    self?.loadingTasks.removeValue(forKey: coord)
                    return
                }
                
                self?.finishLoading(coord: coord, cpuMesh: cpuMesh, world: world)
            } catch {
                self?.finishLoading(coord: coord, cpuMesh: nil, world: world)
            }
        }
        
        loadingTasks[coord] = task
    }
    
    private func finishLoading(coord: TileCoordinate, cpuMesh: CPUMeshData?, world: World) {
        pendingCoordinates.remove(coord)
        loadingTasks.removeValue(forKey: coord)
        
        guard let cpuMesh = cpuMesh else { return }
        
        // Verify tile is still within the current camera visible radius
        if let cameraGPS = self.cameraCoordinate {
            let centerTile = TileCoordinate(coordinate: cameraGPS, zoom: zoomLevel)
            let visibleTileSet = Set(centerTile.neighbors(radius: loadRadius))
            guard visibleTileSet.contains(coord) else { return }
        }
        
        spawnTile(coord: coord, cpuMesh: cpuMesh, world: world)
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
