import Foundation

/// An ECS component that manages sprite flipbook animation state and playback for an entity.
public struct SpriteAnimationComponent: Component, Codable, Sendable, Equatable {
    /// The collection of animation clips available to this entity, keyed by clip name.
    public var clips: [String: SpriteAnimationClip]
    
    /// The name of the currently active animation clip.
    public var currentClipName: String?
    
    /// The 0-based index of the currently active frame within the active clip.
    public var currentFrameIndex: Int
    
    /// The accumulated playback time (in seconds) within the current frame.
    public var playbackTimer: Double
    
    /// Playback speed multiplier (1.0 = normal, 0.5 = half speed, 2.0 = double speed).
    public var speed: Double
    
    /// An optional playback mode override. If `nil`, the active clip's `playbackMode` is used.
    public var playbackModeOverride: SpriteAnimationPlaybackMode?
    
    /// A boolean value indicating whether the animation is currently active.
    public var isPlaying: Bool
    
    /// A boolean value indicating whether playback is paused.
    public var isPaused: Bool
    
    /// Direction multiplier for ping-pong playback mode (+1 forward, -1 backward).
    public var pingPongDirection: Int
    
    /// Retrieves the currently active animation clip, if one is set.
    public var currentClip: SpriteAnimationClip? {
        guard let name = currentClipName else { return nil }
        return clips[name]
    }
    
    /// Retrieves the currently active animation frame, if available.
    public var currentFrame: SpriteAnimationFrame? {
        guard let clip = currentClip,
              currentFrameIndex >= 0,
              currentFrameIndex < clip.frames.count else {
            return nil
        }
        return clip.frames[currentFrameIndex]
    }
    
    /// The effective playback mode currently governing the animation.
    public var activePlaybackMode: SpriteAnimationPlaybackMode {
        playbackModeOverride ?? currentClip?.playbackMode ?? .loop
    }
    
    /// The normalized progress `(0.0 ... 1.0)` through the current animation clip cycle.
    public var normalizedProgress: Double {
        guard let clip = currentClip, clip.totalDuration > 0 else { return 0.0 }
        var elapsed: Double = 0.0
        for i in 0..<min(currentFrameIndex, clip.frames.count) {
            elapsed += clip.frames[i].duration
        }
        elapsed += min(playbackTimer, currentFrame?.duration ?? 0.0)
        return min(1.0, max(0.0, elapsed / clip.totalDuration))
    }
    
    /// Initializes a new `SpriteAnimationComponent`.
    /// - Parameters:
    ///   - clips: A dictionary of named animation clips.
    ///   - initialClip: The name of the clip to select initially (defaults to first available in `clips`).
    ///   - speed: Playback speed multiplier (defaults to `1.0`).
    ///   - isPlaying: Whether animation starts playing immediately (defaults to `true`).
    public init(
        clips: [String: SpriteAnimationClip] = [:],
        initialClip: String? = nil,
        speed: Double = 1.0,
        isPlaying: Bool = true
    ) {
        self.clips = clips
        self.currentClipName = initialClip ?? clips.keys.sorted().first
        self.currentFrameIndex = 0
        self.playbackTimer = 0.0
        self.speed = speed
        self.playbackModeOverride = nil
        self.isPlaying = isPlaying
        self.isPaused = false
        self.pingPongDirection = 1
    }
    
    /// Initializes a new `SpriteAnimationComponent` with a list of clips.
    /// - Parameters:
    ///   - clipList: An array of animation clips.
    ///   - initialClip: The name of the clip to select initially (defaults to first clip's name).
    ///   - speed: Playback speed multiplier (defaults to `1.0`).
    ///   - isPlaying: Whether animation starts playing immediately (defaults to `true`).
    public init(
        clipList: [SpriteAnimationClip],
        initialClip: String? = nil,
        speed: Double = 1.0,
        isPlaying: Bool = true
    ) {
        var dict: [String: SpriteAnimationClip] = [:]
        for clip in clipList {
            dict[clip.name] = clip
        }
        self.init(
            clips: dict,
            initialClip: initialClip ?? clipList.first?.name,
            speed: speed,
            isPlaying: isPlaying
        )
    }
    
    /// Adds or updates an animation clip in the component.
    /// - Parameter clip: The clip to add.
    public mutating func addClip(_ clip: SpriteAnimationClip) {
        clips[clip.name] = clip
        if currentClipName == nil {
            currentClipName = clip.name
        }
    }
    
    /// Removes an animation clip by name.
    /// - Parameter name: The name of the clip to remove.
    public mutating func removeClip(named name: String) {
        clips.removeValue(forKey: name)
        if currentClipName == name {
            currentClipName = clips.keys.sorted().first
            currentFrameIndex = 0
            playbackTimer = 0.0
        }
    }
    
    /// Plays an animation clip by name.
    /// - Parameters:
    ///   - name: The name of the animation clip to play.
    ///   - mode: An optional playback mode override for this playback.
    ///   - restartIfAlreadyPlaying: If `false` and the clip is already playing, playback continues without interruption. Defaults to `false`.
    public mutating func play(
        clipNamed name: String,
        mode: SpriteAnimationPlaybackMode? = nil,
        restartIfAlreadyPlaying: Bool = false
    ) {
        guard let clip = clips[name] else { return }
        
        if currentClipName == name && isPlaying && !restartIfAlreadyPlaying {
            isPaused = false
            if let mode = mode {
                playbackModeOverride = mode
            }
            return
        }
        
        currentClipName = name
        playbackModeOverride = mode
        let effectiveMode = mode ?? clip.playbackMode
        
        if effectiveMode == .reverseOnce || effectiveMode == .reverseLoop {
            currentFrameIndex = max(0, clip.frames.count - 1)
        } else {
            currentFrameIndex = 0
        }
        
        playbackTimer = 0.0
        pingPongDirection = 1
        isPlaying = true
        isPaused = false
    }
    
    /// Pauses playback at the current frame.
    public mutating func pause() {
        isPaused = true
    }
    
    /// Resumes playback if currently paused.
    public mutating func resume() {
        isPaused = false
    }
    
    /// Stops playback and resets the animation to the initial frame.
    public mutating func stop() {
        isPlaying = false
        isPaused = false
        playbackTimer = 0.0
        currentFrameIndex = 0
        pingPongDirection = 1
    }
    
    /// Manually steps the animation by a given number of frames.
    /// - Parameter deltaFrames: The relative frame count to step (+1, -1, etc.).
    public mutating func step(by deltaFrames: Int) {
        guard let clip = currentClip, !clip.frames.isEmpty else { return }
        let total = clip.frames.count
        currentFrameIndex = (currentFrameIndex + deltaFrames) % total
        if currentFrameIndex < 0 {
            currentFrameIndex += total
        }
        playbackTimer = 0.0
    }
}
