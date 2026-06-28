import Foundation
import simd

/// A component that makes an entity (typically a camera) smoothly track another entity.
public struct CameraTrackingComponent: Component {
    /// The ID of the entity to track.
    public var target: Entity
    
    /// The positional offset from the target.
    public var offset: SIMD3<Float>
    
    /// The smoothing factor for interpolation (0.0 to 1.0).
    /// A value of 1.0 means instant tracking, while lower values result in smoother, delayed movement.
    public var smoothing: Float
    
    /// Initializes a new camera tracking component.
    /// - Parameters:
    ///   - target: The entity ID to track.
    ///   - offset: The positional offset. Defaults to `.zero`.
    ///   - smoothing: The smoothing factor. Defaults to 0.1.
    public init(target: Entity, offset: SIMD3<Float> = .zero, smoothing: Float = 0.1) {
        self.target = target
        self.offset = offset
        // Clamp smoothing between a small epsilon and 1.0 to prevent zero-division or overshooting
        self.smoothing = max(0.001, min(1.0, smoothing))
    }
}
