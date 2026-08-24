import Foundation

/// A component that marks an entity as an audio listener in 3D space.
public struct AudioListenerComponent: Component {
    /// Whether this is the primary audio listener in the scene.
    public var isPrimary: Bool
    
    /// The master volume for the listener, clamped to 0.0...1.0.
    public var masterVolume: Float {
        didSet {
            masterVolume = max(0.0, min(1.0, masterVolume))
        }
    }
    
    /// Initializes a new audio listener component.
    /// - Parameters:
    ///   - isPrimary: Whether this listener is primary. Defaults to `true`.
    ///   - masterVolume: Master volume level (0.0 to 1.0). Defaults to `1.0`.
    public init(isPrimary: Bool = true, masterVolume: Float = 1.0) {
        self.isPrimary = isPrimary
        self.masterVolume = max(0.0, min(1.0, masterVolume))
    }
}
