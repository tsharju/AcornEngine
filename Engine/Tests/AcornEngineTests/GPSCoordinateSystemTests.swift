import Testing
import simd
@testable import AcornEngine

@MainActor
struct GPSCoordinateSystemTests {
    @Test
    func testCoordinateConversion() {
        // Known coordinates (e.g., Helsinki)
        let helsinki = GPSCoordinate(latitude: 60.1699, longitude: 24.9384, altitude: 10.0)
        let system = GPSCoordinateSystem(initialReference: helsinki)
        
        // World origin should perfectly match the reference coordinate
        let worldOrigin = SIMD3<Float>(0, 0, 0)
        let gpsAtOrigin = system.toGPS(position: worldOrigin)
        
        #expect(abs(gpsAtOrigin.latitude - helsinki.latitude) < 0.0001)
        #expect(abs(gpsAtOrigin.longitude - helsinki.longitude) < 0.0001)
        #expect(abs(gpsAtOrigin.altitude - helsinki.altitude) < 0.0001)
        
        let worldAtHelsinki = system.toWorld(coordinate: helsinki)
        #expect(abs(worldAtHelsinki.x) < 0.001)
        #expect(abs(worldAtHelsinki.y) < 0.001)
        #expect(abs(worldAtHelsinki.z) < 0.001)
    }
    
    @Test
    func testTwoWaySync() {
        let reference = GPSCoordinate(latitude: 0, longitude: 0, altitude: 0)
        let system = GPSCoordinateSystem(initialReference: reference)
        let world = World()
        
        let entity = world.createEntity()
        let initialTransform = TransformComponent(position: SIMD3<Float>(0, 0, 0))
        let initialGPS = GPSPositionComponent(coordinate: GPSCoordinate(latitude: 0, longitude: 0, altitude: 0))
        
        world.addComponent(initialTransform, to: entity)
        world.addComponent(initialGPS, to: entity)
        
        // 1. Initial sync (should sync GPS to Transform, but they are both 0)
        system.update(world: world, deltaTime: 1.0)
        
        // 2. Modify Transform, check if GPS updates
        var transform = world.component(ofType: TransformComponent.self, for: entity)!
        // Move 100 meters East, 50 meters up, 200 meters North
        // In our system: +X is East, +Y is Up, -Z is North
        transform.position = SIMD3<Float>(100.0, 50.0, -200.0)
        world.addComponent(transform, to: entity)
        
        system.update(world: world, deltaTime: 1.0)
        
        var gps = world.component(ofType: GPSPositionComponent.self, for: entity)!
        #expect(gps.coordinate.altitude == 50.0)
        #expect(gps.coordinate.longitude > 0) // Moved East, longitude should increase
        #expect(gps.coordinate.latitude > 0) // Moved North, latitude should increase
        
        // 3. Modify GPS, check if Transform updates
        gps.coordinate.altitude = 100.0
        world.addComponent(gps, to: entity)
        
        system.update(world: world, deltaTime: 1.0)
        
        transform = world.component(ofType: TransformComponent.self, for: entity)!
        #expect(transform.position.y == 100.0)
    }
    
    @Test
    func testReferenceChange() {
        let initialRef = GPSCoordinate(latitude: 0, longitude: 0, altitude: 0)
        let system = GPSCoordinateSystem(initialReference: initialRef)
        let world = World()
        
        let entity = world.createEntity()
        // Put entity at the world origin initially
        world.addComponent(TransformComponent(position: SIMD3<Float>(0, 0, 0)), to: entity)
        world.addComponent(GPSPositionComponent(coordinate: initialRef), to: entity)
        
        system.update(world: world, deltaTime: 1.0)
        
        // Change reference to 1 degree North. The entity should now be at a negative Z position (South of the new origin).
        let newRef = GPSCoordinate(latitude: 1.0, longitude: 0, altitude: 0)
        system.setReferenceCoordinate(newRef, world: world)
        
        let transform = world.component(ofType: TransformComponent.self, for: entity)!
        
        // Entity should be South of the origin, which means +Z in our mapping (where North is -Z)
        #expect(transform.position.z > 0)
        
        // X and Y should remain ~0
        #expect(abs(transform.position.x) < 0.001)
        #expect(abs(transform.position.y) < 0.001)
    }
}
