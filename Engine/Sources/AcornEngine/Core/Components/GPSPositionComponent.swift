import Foundation
import simd

/// A component that tracks an entity's real-world GPS location and synchronizes it with its TransformComponent.
public struct GPSPositionComponent: Component {
    /// The current GPS coordinate of the entity.
    public var coordinate: GPSCoordinate
    
    // Internal state to track changes and perform two-way synchronization
    internal var lastSyncedCoordinate: GPSCoordinate?
    internal var lastSyncedPosition: SIMD3<Float>?
    
    /// Initializes a new GPS position component.
    /// - Parameter coordinate: The initial GPS coordinate.
    public init(coordinate: GPSCoordinate) {
        self.coordinate = coordinate
    }
}
