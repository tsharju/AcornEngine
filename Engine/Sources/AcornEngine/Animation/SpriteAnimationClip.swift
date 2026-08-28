import Foundation

/// A named animation sequence consisting of ordered sprite frames and playback settings.
public struct SpriteAnimationClip: Codable, Sendable, Equatable {
    /// The unique name of the animation clip (e.g. "idle", "run", "jump", "attack").
    public var name: String
    
    /// The sequential list of frames in this clip.
    public var frames: [SpriteAnimationFrame]
    
    /// The default playback mode for this clip.
    public var playbackMode: SpriteAnimationPlaybackMode
    
    /// The total duration of one complete cycle of the clip in seconds.
    public var totalDuration: Double {
        frames.reduce(0.0) { $0 + $1.duration }
    }
    
    /// Initializes an animation clip with explicit frames and a playback mode.
    /// - Parameters:
    ///   - name: The name of the animation clip.
    ///   - frames: The ordered list of animation frames.
    ///   - playbackMode: The playback mode (defaults to `.loop`).
    public init(
        name: String,
        frames: [SpriteAnimationFrame],
        playbackMode: SpriteAnimationPlaybackMode = .loop
    ) {
        self.name = name
        self.frames = frames
        self.playbackMode = playbackMode
    }
    
    /// Initializes an animation clip with uniform frame rate across all frames.
    /// - Parameters:
    ///   - name: The name of the animation clip.
    ///   - frameNames: The frame identifiers in order.
    ///   - fps: The playback frame rate in frames per second (e.g. 10.0 for 10 FPS).
    ///   - playbackMode: The playback mode (defaults to `.loop`).
    ///   - triggers: A dictionary mapping frame index to event trigger identifiers.
    public init(
        name: String,
        frameNames: [String],
        fps: Double,
        playbackMode: SpriteAnimationPlaybackMode = .loop,
        triggers: [Int: [String]] = [:]
    ) {
        let frameDuration = 1.0 / max(0.001, fps)
        self.name = name
        self.frames = frameNames.enumerated().map { index, frameName in
            SpriteAnimationFrame(
                frameName: frameName,
                duration: frameDuration,
                triggers: triggers[index] ?? []
            )
        }
        self.playbackMode = playbackMode
    }
    
    /// Initializes an animation clip with a fixed duration per frame.
    /// - Parameters:
    ///   - name: The name of the animation clip.
    ///   - frameNames: The frame identifiers in order.
    ///   - frameDuration: The display duration for each frame in seconds.
    ///   - playbackMode: The playback mode (defaults to `.loop`).
    ///   - triggers: A dictionary mapping frame index to event trigger identifiers.
    public init(
        name: String,
        frameNames: [String],
        frameDuration: Double,
        playbackMode: SpriteAnimationPlaybackMode = .loop,
        triggers: [Int: [String]] = [:]
    ) {
        self.name = name
        self.frames = frameNames.enumerated().map { index, frameName in
            SpriteAnimationFrame(
                frameName: frameName,
                duration: frameDuration,
                triggers: triggers[index] ?? []
            )
        }
        self.playbackMode = playbackMode
    }
    
    /// Retrieves the frame at the specified index if it exists.
    /// - Parameter index: The 0-based index.
    /// - Returns: The `SpriteAnimationFrame` or `nil` if index is out of bounds.
    public func frame(at index: Int) -> SpriteAnimationFrame? {
        guard index >= 0, index < frames.count else { return nil }
        return frames[index]
    }
}
