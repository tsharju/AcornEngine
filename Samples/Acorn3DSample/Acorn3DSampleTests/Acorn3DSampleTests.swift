import Foundation
import CoreLocation
import Testing
import AcornEngine
@testable import Acorn3DSample

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
        
        let service = MapboxTileService(accessToken: "test_token")
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
        let service = MapboxTileService(accessToken: "test_token")
        let coord = TileCoordinate(zoom: 12, x: 200, y: 150)
        let cacheURL = await service.cacheFileURL(for: coord)
        
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let mockData = "clear_cache_test".data(using: .utf8)!
        try mockData.write(to: cacheURL)
        #expect(FileManager.default.fileExists(atPath: cacheURL.path))
        
        try await service.clearCache()
        #expect(!FileManager.default.fileExists(atPath: cacheURL.path))
    }
}
