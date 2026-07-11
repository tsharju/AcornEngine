import Foundation

/// A real-world coordinate based on latitude, longitude, and altitude.
public struct GPSCoordinate: Equatable, Sendable {
    /// Latitude in degrees.
    public var latitude: Double
    
    /// Longitude in degrees.
    public var longitude: Double
    
    /// Altitude in meters.
    public var altitude: Double
    
    /// Initializes a new GPS coordinate.
    /// - Parameters:
    ///   - latitude: Latitude in degrees.
    ///   - longitude: Longitude in degrees.
    ///   - altitude: Altitude in meters. Defaults to 0.0.
    public init(latitude: Double, longitude: Double, altitude: Double = 0.0) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }
}
