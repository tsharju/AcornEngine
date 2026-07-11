import Foundation
import simd

/// A system that synchronizes `GPSPositionComponent` with `TransformComponent`, mapping real-world coordinates to game world space using the Web Mercator projection.
@MainActor
public class GPSCoordinateSystem: System {
    /// Earth's radius in meters (WGS 84 equatorial radius).
    private let earthRadius = 6378137.0
    
    /// The reference GPS coordinate that corresponds to the game world origin (0, 0, 0).
    public private(set) var referenceCoordinate: GPSCoordinate
    
    private var referenceWebMercatorX: Double = 0
    private var referenceWebMercatorY: Double = 0
    
    /// Initializes a new GPS coordinate system.
    /// - Parameter initialReference: The GPS coordinate that will map to the world origin.
    public init(initialReference: GPSCoordinate) {
        self.referenceCoordinate = initialReference
        updateReferenceWebMercator()
    }
    
    /// Resets the reference coordinate. The world origin will now be at this new GPS coordinate.
    /// To keep entities at their real-world locations, their game world `TransformComponent` positions will be updated.
    /// - Parameters:
    ///   - newReference: The new reference coordinate.
    ///   - world: The ECS world.
    public func setReferenceCoordinate(_ newReference: GPSCoordinate, world: World) {
        self.referenceCoordinate = newReference
        updateReferenceWebMercator()
        
        let entities = world.entities(with: GPSPositionComponent.self)
        for (entity, _) in entities {
            guard var transform = world.component(ofType: TransformComponent.self, for: entity) else { continue }
            guard var gps = world.component(ofType: GPSPositionComponent.self, for: entity) else { continue }
            
            // Recalculate transform from the current GPS coordinate.
            let newPosition = toWorld(coordinate: gps.coordinate)
            transform.position = newPosition
            gps.lastSyncedPosition = newPosition
            gps.lastSyncedCoordinate = gps.coordinate
            
            world.addComponent(transform, to: entity)
            world.addComponent(gps, to: entity)
        }
    }
    
    /// Converts a GPS coordinate to a game world position.
    /// - Parameter coordinate: The GPS coordinate.
    /// - Returns: The game world position.
    public func toWorld(coordinate: GPSCoordinate) -> SIMD3<Float> {
        let (wmX, wmY) = toWebMercator(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        let deltaX = wmX - referenceWebMercatorX
        let deltaY = wmY - referenceWebMercatorY
        let deltaAltitude = coordinate.altitude - referenceCoordinate.altitude
        
        // Map deltaX (East) to X, deltaAltitude (Up) to Y, and deltaY (North) to -Z
        return SIMD3<Float>(
            Float(deltaX),
            Float(deltaAltitude),
            Float(-deltaY)
        )
    }
    
    /// Converts a game world position to a GPS coordinate.
    /// - Parameter position: The game world position.
    /// - Returns: The corresponding GPS coordinate.
    public func toGPS(position: SIMD3<Float>) -> GPSCoordinate {
        let wmX = Double(position.x) + referenceWebMercatorX
        let wmY = Double(-position.z) + referenceWebMercatorY
        let altitude = Double(position.y) + referenceCoordinate.altitude
        
        let (lat, lon) = fromWebMercator(x: wmX, y: wmY)
        return GPSCoordinate(latitude: lat, longitude: lon, altitude: altitude)
    }
    
    /// Updates the entities, syncing `TransformComponent` and `GPSPositionComponent`.
    /// - Parameters:
    ///   - world: The ECS world.
    ///   - deltaTime: The time elapsed since the last update.
    public func update(world: World, deltaTime: Double) {
        let entities = world.entities(with: GPSPositionComponent.self)
        
        for (entity, gpsRef) in entities {
            guard var transform = world.component(ofType: TransformComponent.self, for: entity) else { continue }
            var gps = gpsRef
            
            let transformChanged = transform.position != gps.lastSyncedPosition
            let gpsChanged = gps.coordinate != gps.lastSyncedCoordinate
            
            if transformChanged && !gpsChanged {
                // Entity moved in the game world, update its GPS coordinate
                let newGPS = toGPS(position: transform.position)
                gps.coordinate = newGPS
                gps.lastSyncedPosition = transform.position
                gps.lastSyncedCoordinate = newGPS
                world.addComponent(gps, to: entity)
            } else if gpsChanged {
                // GPS coordinate was explicitly changed (or both changed, in which case GPS wins), update Transform
                let newPos = toWorld(coordinate: gps.coordinate)
                transform.position = newPos
                gps.lastSyncedPosition = newPos
                gps.lastSyncedCoordinate = gps.coordinate
                world.addComponent(transform, to: entity)
                world.addComponent(gps, to: entity)
            } else if gps.lastSyncedPosition == nil {
                // Initial sync: sync from GPS to Transform by default if just added
                let newPos = toWorld(coordinate: gps.coordinate)
                transform.position = newPos
                gps.lastSyncedPosition = newPos
                gps.lastSyncedCoordinate = gps.coordinate
                world.addComponent(transform, to: entity)
                world.addComponent(gps, to: entity)
            }
        }
    }
    
    private func updateReferenceWebMercator() {
        let (x, y) = toWebMercator(latitude: referenceCoordinate.latitude, longitude: referenceCoordinate.longitude)
        referenceWebMercatorX = x
        referenceWebMercatorY = y
    }
    
    private func toWebMercator(latitude: Double, longitude: Double) -> (x: Double, y: Double) {
        let latRad = latitude * .pi / 180.0
        let lonRad = longitude * .pi / 180.0
        
        let x = earthRadius * lonRad
        let y = earthRadius * log(tan(.pi / 4.0 + latRad / 2.0))
        
        return (x, y)
    }
    
    private func fromWebMercator(x: Double, y: Double) -> (latitude: Double, longitude: Double) {
        let lonRad = x / earthRadius
        let latRad = 2.0 * atan(exp(y / earthRadius)) - .pi / 2.0
        
        let lat = latRad * 180.0 / .pi
        let lon = lonRad * 180.0 / .pi
        
        return (lat, lon)
    }
}
