import Foundation

/// Defines how a 3D model animation clip cycles during playback.
public enum ModelAnimationPlaybackMode: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    /// Plays forward once from beginning to end, then stops on the final frame.
    case once
    
    /// Loops continuously from beginning to end, seamlessly restarting from the start.
    case loop
    
    /// Plays forward to the end, then reverses back to the beginning, repeating indefinitely.
    case pingPong
    
    /// Plays backward once from the end to the beginning, then stops.
    case reverseOnce
    
    /// Loops backward continuously from end to beginning.
    case reverseLoop
}
