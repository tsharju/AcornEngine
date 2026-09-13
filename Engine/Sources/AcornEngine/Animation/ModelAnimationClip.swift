import Foundation

/// Represents a single named 3D model animation clip composed of multiple node animation channels.
public struct ModelAnimationClip: Sendable, Equatable {
    /// The unique name of the animation clip (e.g. "Idle", "Walk", "Run").
    public var name: String
    
    /// The total duration of the animation clip in seconds.
    public var duration: Double
    
    /// The collection of animation channels driving individual node transforms.
    public var channels: [ModelAnimationChannel]
    
    /// The default playback mode for this clip (defaults to `.loop`).
    public var playbackMode: ModelAnimationPlaybackMode
    
    /// Initializes a new model animation clip.
    /// - Parameters:
    ///   - name: The name of the clip.
    ///   - duration: The duration in seconds.
    ///   - channels: The channels modifying node properties.
    ///   - playbackMode: The playback mode (defaults to `.loop`).
    public init(
        name: String,
        duration: Double,
        channels: [ModelAnimationChannel] = [],
        playbackMode: ModelAnimationPlaybackMode = .loop
    ) {
        self.name = name
        self.duration = duration
        self.channels = channels
        self.playbackMode = playbackMode
    }
}
