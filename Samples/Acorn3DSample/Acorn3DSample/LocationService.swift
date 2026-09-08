import Foundation
import CoreLocation
import AcornEngine

/// Service responsible for managing device location updates and publishing GPS coordinates.
///
/// This service wraps CoreLocation's `CLLocationManager` on the main actor, providing
/// GPS coordinate updates suitable for positioning characters and streaming map tiles.
@MainActor
public final class LocationService: NSObject, CLLocationManagerDelegate {
    /// Default coordinate fallback representing Helsinki Senate Square.
    public nonisolated static let defaultSenateSquare = GPSCoordinate(
        latitude: 60.1699,
        longitude: 24.9384,
        altitude: 0.0
    )
    
    /// Underlying CoreLocation manager instance.
    private let locationManager = CLLocationManager()
    
    /// The most recent GPS coordinate of the device, or the default fallback coordinate.
    public private(set) var currentCoordinate: GPSCoordinate
    
    /// Closure callback invoked on the main actor whenever a new GPS location update is received.
    public var onLocationUpdated: (@MainActor (GPSCoordinate) -> Void)?
    
    /// Initializes a new `LocationService`.
    ///
    /// Configures the location manager with best accuracy and a 1-meter distance filter,
    /// requests "when in use" authorization, and begins location updates.
    ///
    /// - Parameter defaultCoordinate: An optional fallback coordinate. Defaults to Helsinki Senate Square if `nil` or omitted.
    public init(defaultCoordinate: GPSCoordinate? = nil) {
        let initialCoordinate = defaultCoordinate ?? LocationService.defaultSenateSquare
        self.currentCoordinate = initialCoordinate
        super.init()
        
        configureAndStartLocationManager()
    }
    
    /// Configures location manager parameters and begins tracking location updates.
    public func start() {
        configureAndStartLocationManager()
    }
    
    /// Stops tracking location updates.
    public func stop() {
        locationManager.stopUpdatingLocation()
    }
    
    // MARK: - Private Configuration
    
    private func configureAndStartLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 1.0
        #if !targetEnvironment(simulator)
        locationManager.requestWhenInUseAuthorization()
        #endif
        locationManager.startUpdatingLocation()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = GPSCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude
        )
        self.currentCoordinate = coordinate
        onLocationUpdated?(coordinate)
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        print("LocationService failed with error: \(error.localizedDescription)")
    }
    
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        default:
            break
        }
    }
}
