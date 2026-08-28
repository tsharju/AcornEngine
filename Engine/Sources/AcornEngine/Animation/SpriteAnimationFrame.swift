import Foundation

/// Represents an individual frame within a sprite animation clip, including display duration and frame trigger tags.
public struct SpriteAnimationFrame: Codable, Sendable, Equatable {
    /// The name of the frame corresponding to a frame identifier in the `SpriteSheet`.
    public var frameName: String
    
    /// The duration (in seconds) this frame remains active.
    public var duration: Double
    
    /// Optional event trigger identifiers dispatched when this frame becomes active.
    public var triggers: [String]
    
    /// Initializes a new sprite animation frame.
    /// - Parameters:
    ///   - frameName: The frame name matching a sprite in the sprite sheet.
    ///   - duration: The duration in seconds (must be greater than 0; defaults to 0.1s).
    ///   - triggers: Optional trigger identifiers to dispatch via the event bus when this frame is entered.
    public init(frameName: String, duration: Double = 0.1, triggers: [String] = []) {
        self.frameName = frameName
        self.duration = max(0.0001, duration)
        self.triggers = triggers
    }
}
