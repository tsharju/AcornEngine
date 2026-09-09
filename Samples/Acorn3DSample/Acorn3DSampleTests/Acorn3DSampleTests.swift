@testable import Acorn3DSample
import AcornEngine
import CoreGraphics
import CoreLocation
import Foundation
import Testing

@Suite("Acorn3D Sample Services Tests")
struct Acorn3DSampleTests {
    // MARK: - LocationService Tests

    @Test("LocationService initializes with default Helsinki Senate Square coordinate")
    @MainActor
    func locationServiceDefaultCoordinate() {
        let service = LocationService()
        let coord = service.currentCoordinate

        #expect(abs(coord.latitude - 60.1699) < 0.0001)
        #expect(abs(coord.longitude - 24.9384) < 0.0001)
        #expect(coord.altitude == 0.0)
    }

    @Test("LocationService initializes with custom default coordinate")
    @MainActor
    func locationServiceCustomCoordinate() {
        let customCoord = GPSCoordinate(latitude: 37.7749, longitude: -122.4194, altitude: 15.0)
        let service = LocationService(defaultCoordinate: customCoord)

        #expect(service.currentCoordinate == customCoord)
    }

    @Test("LocationService updates currentCoordinate and calls onLocationUpdated when location changes")
    @MainActor
    func locationServiceUpdatesCoordinate() {
        let service = LocationService()
        var reportedCoordinate: GPSCoordinate?
        service.onLocationUpdated = { coord in
            reportedCoordinate = coord
        }

        let newLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 60.1708, longitude: 24.9414),
            altitude: 12.5,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )

        service.locationManager(CLLocationManager(), didUpdateLocations: [newLocation])

        #expect(reportedCoordinate != nil)
        #expect(abs(service.currentCoordinate.latitude - 60.1708) < 0.0001)
        #expect(abs(service.currentCoordinate.longitude - 24.9414) < 0.0001)
        #expect(service.currentCoordinate.altitude == 12.5)
        #expect(reportedCoordinate == service.currentCoordinate)
    }

    @Test("LocationService lifecycle methods (start/stop) execute without error")
    @MainActor
    func locationServiceLifecycle() {
        let service = LocationService()
        service.stop()
        service.start()
        #expect(service.currentCoordinate == LocationService.defaultSenateSquare)
    }

    // MARK: - MapboxTileService Tests

    @Test("MapboxTileService resolves custom or fallback access token")
    func mapboxTileServiceTokenResolution() async {
        let customToken = "test_custom_token_123"
        let service = MapboxTileService(accessToken: customToken)
        let token = await service.accessToken
        #expect(token == customToken)

        let defaultService = MapboxTileService()
        let resolvedToken = await defaultService.accessToken
        let expectedToken = MapboxTileService.resolveAccessToken()
        #expect(resolvedToken == expectedToken)
    }

    @Test("MapboxTileService cacheFileURL produces correct path")
    func mapboxTileServiceCachePath() async {
        let service = MapboxTileService(accessToken: "test_token")
        let coord = TileCoordinate(zoom: 15, x: 18765, y: 9341)
        let cacheURL = await service.cacheFileURL(for: coord)

        #expect(cacheURL.lastPathComponent == "15_18765_9341.pbf")
        #expect(cacheURL.path.contains("MapboxTileCache"))
    }

    @Test("MapboxTileService serves cached data without network request")
    func mapboxTileServiceCacheHit() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = MapboxTileService(accessToken: "test_token", cacheDirectoryURL: tempDir)
        let coord = TileCoordinate(zoom: 16, x: 37530, y: 18682)
        let cacheURL = await service.cacheFileURL(for: coord)

        // Ensure cache directory exists and write mock data
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let mockData = "mock_pbf_tile_data".data(using: .utf8)!
        try mockData.write(to: cacheURL)
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        // Fetch should hit cache and return mockData
        let fetchedData = try await service.fetchTileData(coordinate: coord)
        #expect(fetchedData == mockData)
    }

    @Test("MapboxTileService returns nil when access token is missing")
    func mapboxTileServiceMissingToken() async throws {
        let service = MapboxTileService(accessToken: "")
        let coord = TileCoordinate(zoom: 10, x: 500, y: 300)

        // Ensure no cache entry exists for this tile
        let cacheURL = await service.cacheFileURL(for: coord)
        try? FileManager.default.removeItem(at: cacheURL)

        let result = try await service.fetchTileData(coordinate: coord)
        #expect(result == nil)
    }

    @Test("MapboxTileService clearCache removes cached files")
    func mapboxTileServiceClearCache() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = MapboxTileService(accessToken: "test_token", cacheDirectoryURL: tempDir)
        let coord = TileCoordinate(zoom: 12, x: 200, y: 150)
        let cacheURL = await service.cacheFileURL(for: coord)

        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let mockData = "clear_cache_test".data(using: .utf8)!
        try mockData.write(to: cacheURL)
        #expect(FileManager.default.fileExists(atPath: cacheURL.path))

        try await service.clearCache()
        #expect(!FileManager.default.fileExists(atPath: cacheURL.path))
    }

    // MARK: - H3 Map Integration Tests

    @Test("MapTileMode enum titles and toggle behavior")
    func mapTileModeProperties() {
        #expect(MapTileMode.h3Hexagonal.title.contains("H3 Hex"))
        #expect(MapTileMode.classicSlippy.title.contains("Slippy"))
        #expect(MapTileMode.allCases.count == 2)
    }

    @Test("H3MapTileSystem integrates with MapboxTileService data provider")
    @MainActor
    func h3MapTileSystemDataProviderIntegration() async {
        let helsinki = LocationService.defaultSenateSquare
        let system = H3MapTileSystem(
            initialReference: helsinki,
            h3Resolution: 8,
            sourceZoomLevel: 15,
            loadRingRadius: 1,
            showsCellBoundaries: true
        )

        let service = MapboxTileService(accessToken: "mock_token")
        system.tileDataProvider = { coord in
            try await service.fetchTileData(coordinate: coord)
        }

        #expect(system.tileDataProvider != nil)
        #expect(system.showsCellBoundaries == true)
        #expect(system.h3Resolution == 8)
        #expect(system.sourceZoomLevel == 15)
    }

    @Test("H3 boundary mesh generation produces valid indexed geometry")
    @MainActor
    func h3BoundaryMeshGeneration() {
        let helsinki = LocationService.defaultSenateSquare
        let system = H3MapTileSystem(
            initialReference: helsinki,
            h3Resolution: 9,
            showsCellBoundaries: true
        )

        let h3Index = H3Index(coordinate: helsinki, resolution: 9)
        let mesh = system.createBoundaryMesh(for: h3Index)
        #expect(mesh != nil)
        #expect(mesh?.vertexCount == 12)
        #expect(mesh?.indexCount == 36)
    }

    @Test("H3 boundary outlines can be toggled across active entities in World")
    @MainActor
    func h3BoundaryMeshTogglingInWorld() {
        let world = World()
        let helsinki = LocationService.defaultSenateSquare
        let system = H3MapTileSystem(
            initialReference: helsinki,
            h3Resolution: 9,
            showsCellBoundaries: false
        )

        let h3Index = H3Index(coordinate: helsinki, resolution: 9)
        let entity = system.spawnH3Tile(h3Index: h3Index, world: world)

        // Initially no boundary MeshComponent
        #expect(world.component(ofType: MeshComponent.self, for: entity) == nil)

        // Turn on
        system.setShowsCellBoundaries(true, world: world)
        #expect(world.component(ofType: MeshComponent.self, for: entity) != nil)

        // Turn off
        system.setShowsCellBoundaries(false, world: world)
        #expect(world.component(ofType: MeshComponent.self, for: entity) == nil)
    }

    @Test("GameHUDView updates H3 metrics accurately")
    @MainActor
    func gameHUDViewH3MetricUpdates() {
        let hud = GameHUDView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        #expect(hud.currentTileMode == .h3Hexagonal)
        #expect(hud.isH3GridEnabled == true)

        let coord = GPSCoordinate(latitude: 60.1699, longitude: 24.9384, altitude: 0)
        let h3Index = H3Index(coordinate: coord, resolution: 9)
        hud.updateH3(index: h3Index, activeHexes: 7, loadedParts: 14, sourceTiles: 4)

        // Switch mode
        hud.setTileMode(.classicSlippy)
        #expect(hud.currentTileMode == .classicSlippy)

        // Switch back
        hud.setTileMode(.h3Hexagonal)
        #expect(hud.currentTileMode == .h3Hexagonal)

        // Toggle grid state
        hud.setH3GridState(false)
        #expect(hud.isH3GridEnabled == false)
        hud.setH3GridState(true)
        #expect(hud.isH3GridEnabled == true)
    }

    @Test("Player character and H3 boundary projection into camera frustum")
    @MainActor
    func playerAndH3ProjectionFrustum() {
        let world = World()
        let sf = GPSCoordinate(latitude: 37.78583, longitude: -122.40642, altitude: 28.5)

        let playerEntity = world.createEntity()
        world.addComponent(TransformComponent(position: .zero), to: playerEntity)

        let beaconEntity = world.createEntity()
        world.addComponent(TransformComponent(position: SIMD3<Float>(0, 0.15, 0)), to: beaconEntity)
        world.addComponent(ParentComponent(parent: playerEntity), to: beaconEntity)

        let cam = ThirdPersonFollowCamera.create(
            in: world,
            target: playerEntity,
            distance: 42.0,
            pitch: 0.75,
            yaw: 0.0
        )

        let viewMatrix = world.worldMatrix(for: cam.entity).inverse
        let cameraComp = world.component(ofType: CameraComponent.self, for: cam.entity)!
        let projMatrix = cameraComp.projectionMatrix()
        let vp = projMatrix * viewMatrix

        let beaconWorldPos = world.worldPosition(for: beaconEntity)
        #expect(abs(beaconWorldPos.y - 0.15) < 1e-4)

        let beaconNDC = vp * SIMD4<Float>(beaconWorldPos.x, beaconWorldPos.y, beaconWorldPos.z, 1.0)
        let beaconNDCX = beaconNDC.x / beaconNDC.w
        let beaconNDCY = beaconNDC.y / beaconNDC.w
        let beaconNDCZ = beaconNDC.z / beaconNDC.w

        #expect(abs(beaconNDCX) < 0.2)
        #expect(abs(beaconNDCY) < 0.2)
        #expect(beaconNDCZ > 0.0 && beaconNDCZ < 1.0)
    }
}
