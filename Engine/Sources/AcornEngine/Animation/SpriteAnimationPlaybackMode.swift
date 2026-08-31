import Foundation

/// Defines how a sprite animation clip cycles through its sequential frames.
public enum SpriteAnimationPlaybackMode: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    /// Plays forward once from the first frame to the last frame, then stops on the last frame.
    case once
    
    /// Loops continuously from the first frame to the last frame, restarting at frame 0.
    case loop
    
    /// Plays forward to the last frame, then reverses back to the first frame, repeating indefinitely.
    case pingPong
    
    /// Plays backward once from the last frame to the first frame, then stops on the first frame.
    case reverseOnce
    
    /// Loops backward continuously from the last frame to the first frame.
    case reverseLoop
}
