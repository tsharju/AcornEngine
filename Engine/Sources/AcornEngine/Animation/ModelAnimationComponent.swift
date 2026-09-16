import Foundation
import AcornMath

/// Stores the bind/rest local transform of a model node.
public struct NodeRestTransform: Sendable, Equatable {
    /// The default translation vector.
    public var translation: SIMD3<Float>
    
    /// The default rotation quaternion (x, y, z, w).
    public var rotation: SIMD4<Float>
    
    /// The default scale vector.
    public var scale: SIMD3<Float>
    
    /// Initializes a new rest transform.
    public init(
        translation: SIMD3<Float> = .zero,
        rotation: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1),
        scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    ) {
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
    }
}

/// Tracks the active crossfade transition between two animation clips.
public struct ModelAnimationTransition: Sendable, Equatable {
    /// The name of the animation clip fading out.
    public var fromClipName: String
    
    /// The name of the animation clip fading in.
    public var toClipName: String
    
    /// Current playback time for the source animation.
    public var fromTimer: Double
    
    /// Current playback time for the destination animation.
    public var toTimer: Double
    
    /// Elapsed time in seconds since the transition began.
    public var elapsed: Double
    
    /// Total duration of the transition in seconds.
    public var duration: Double
    
    /// Normalized crossfade progress `[0.0 ... 1.0]`.
    public var progress: Double {
        duration > 0.00001 ? min(1.0, max(0.0, elapsed / duration)) : 1.0
    }
    
    /// Initializes a new animation transition.
    public init(
        fromClipName: String,
        toClipName: String,
        fromTimer: Double,
        toTimer: Double,
        elapsed: Double,
        duration: Double
    ) {
        self.fromClipName = fromClipName
        self.toClipName = toClipName
        self.fromTimer = fromTimer
        self.toTimer = toTimer
        self.elapsed = elapsed
        self.duration = duration
    }
}

/// An ECS component that manages 3D model skeletal/hierarchical animation state, multi-clip playback, looping, and crossfades.
public struct ModelAnimationComponent: Component, Sendable, Equatable {
    /// The collection of animation clips loaded for this model, keyed by clip name.
    public var clips: [String: ModelAnimationClip]
    
    /// The name of the currently active animation clip.
    public var currentClipName: String?
    
    /// The elapsed playback time in seconds within the active clip.
    public var playbackTimer: Double
    
    /// Playback speed multiplier (1.0 = normal, 0.5 = half speed, 2.0 = double speed).
    public var speed: Double
    
    /// Optional playback mode override. If `nil`, the active clip's `playbackMode` is used.
    public var playbackModeOverride: ModelAnimationPlaybackMode?
    
    /// Indicates whether the animation is currently active.
    public var isPlaying: Bool
    
    /// Indicates whether playback is paused.
    public var isPaused: Bool
    
    /// Direction multiplier for ping-pong playback mode (+1 forward, -1 backward).
    public var pingPongDirection: Int
    
    /// The array of ECS entities corresponding to each node index in the loaded model hierarchy.
    public var nodeEntities: [Entity]
    
    /// The bind/rest transforms for each node in `nodeEntities`.
    public var nodeRestTransforms: [NodeRestTransform]
    
    /// Active transition/crossfade state between two animations, if in progress.
    public var transition: ModelAnimationTransition?
    
    /// The skins loaded for this model, containing joint node indices and inverse bind matrices.
    public var skins: [GLTFSkin]
    
    /// The entities in this model that have a `SkinnedMeshComponent`.
    public var skinnedMeshEntities: [Entity]
    
    /// Retrieves the currently active animation clip, if one is set.
    public var currentClip: ModelAnimationClip? {
        guard let name = currentClipName else { return nil }
        return clips[name]
    }
    
    /// The effective playback mode currently governing the animation.
    public var activePlaybackMode: ModelAnimationPlaybackMode {
        playbackModeOverride ?? currentClip?.playbackMode ?? .loop
    }
    
    /// Normalized progress `(0.0 ... 1.0)` through the current animation clip cycle.
    public var normalizedProgress: Double {
        guard let clip = currentClip, clip.duration > 0 else { return 0.0 }
        return min(1.0, max(0.0, playbackTimer / clip.duration))
    }
    
    /// Initializes a new `ModelAnimationComponent`.
    /// - Parameters:
    ///   - clips: A dictionary of named animation clips.
    ///   - initialClip: The name of the clip to play initially (defaults to first clip).
    ///   - speed: Playback speed multiplier (defaults to 1.0).
    ///   - isPlaying: Whether playback starts immediately (defaults to true).
    ///   - nodeEntities: The ECS entities representing the model's node hierarchy.
    ///   - nodeRestTransforms: The bind/rest transforms for each node.
    ///   - skins: The skins loaded for this model.
    ///   - skinnedMeshEntities: The entities with a SkinnedMeshComponent.
    public init(
        clips: [String: ModelAnimationClip] = [:],
        initialClip: String? = nil,
        speed: Double = 1.0,
        isPlaying: Bool = true,
        nodeEntities: [Entity] = [],
        nodeRestTransforms: [NodeRestTransform] = [],
        skins: [GLTFSkin] = [],
        skinnedMeshEntities: [Entity] = []
    ) {
        self.clips = clips
        let selectedClipName = initialClip ?? clips.keys.sorted().first
        self.currentClipName = selectedClipName
        self.playbackTimer = 0.0
        self.speed = speed
        self.playbackModeOverride = nil
        self.isPlaying = isPlaying
        self.isPaused = false
        self.pingPongDirection = 1
        self.nodeEntities = nodeEntities
        self.nodeRestTransforms = nodeRestTransforms
        self.transition = nil
        self.skins = skins
        self.skinnedMeshEntities = skinnedMeshEntities
    }
    
    /// Initializes a new `ModelAnimationComponent` with an array of clips.
    public init(
        clips: [ModelAnimationClip],
        initialClip: String? = nil,
        speed: Double = 1.0,
        isPlaying: Bool = true,
        nodeEntities: [Entity] = [],
        nodeRestTransforms: [NodeRestTransform] = [],
        skins: [GLTFSkin] = [],
        skinnedMeshEntities: [Entity] = []
    ) {
        var dict: [String: ModelAnimationClip] = [:]
        for clip in clips {
            dict[clip.name] = clip
        }
        self.init(
            clips: dict,
            initialClip: initialClip ?? clips.first?.name,
            speed: speed,
            isPlaying: isPlaying,
            nodeEntities: nodeEntities,
            nodeRestTransforms: nodeRestTransforms,
            skins: skins,
            skinnedMeshEntities: skinnedMeshEntities
        )
    }
    
    /// Adds or updates an animation clip.
    public mutating func addClip(_ clip: ModelAnimationClip) {
        clips[clip.name] = clip
        if currentClipName == nil {
            currentClipName = clip.name
        }
    }
    
    /// Removes an animation clip by name.
    public mutating func removeClip(named name: String) {
        clips.removeValue(forKey: name)
        if currentClipName == name {
            currentClipName = clips.keys.sorted().first
            playbackTimer = 0.0
            transition = nil
        }
    }
    
    /// Plays or unpauses the currently active or default animation clip.
    public mutating func play(
        mode: ModelAnimationPlaybackMode? = nil,
        restartIfAlreadyPlaying: Bool = false
    ) {
        if let name = currentClipName ?? clips.keys.sorted().first {
            play(clipNamed: name, mode: mode, restartIfAlreadyPlaying: restartIfAlreadyPlaying)
        }
    }
    
    /// Plays an animation clip by name immediately without transition.
    public mutating func play(
        clipNamed name: String,
        mode: ModelAnimationPlaybackMode? = nil,
        restartIfAlreadyPlaying: Bool = false
    ) {
        guard let clip = clips[name] else { return }
        
        transition = nil
        
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
            playbackTimer = clip.duration
            pingPongDirection = -1
        } else {
            playbackTimer = 0.0
            pingPongDirection = 1
        }
        
        isPlaying = true
        isPaused = false
    }
    
    /// Smoothly crossfades and transitions from the current animation to another clip over `duration` seconds.
    /// - Parameters:
    ///   - clipNamed: The destination animation clip name.
    ///   - duration: The transition duration in seconds.
    ///   - mode: Optional playback mode override for the destination clip.
    public mutating func transition(
        to clipNamed: String,
        duration: Double,
        mode: ModelAnimationPlaybackMode? = nil
    ) {
        guard let destClip = clips[clipNamed] else { return }
        
        // If not playing or transition duration is negligible, play directly
        guard let currentName = currentClipName, clips[currentName] != nil, isPlaying, duration > 0.0001 else {
            play(clipNamed: clipNamed, mode: mode, restartIfAlreadyPlaying: true)
            return
        }
        
        if currentName == clipNamed && transition == nil {
            return
        }
        
        let destEffectiveMode = mode ?? destClip.playbackMode
        let destStartTimer = (destEffectiveMode == .reverseOnce || destEffectiveMode == .reverseLoop) ? destClip.duration : 0.0
        
        self.transition = ModelAnimationTransition(
            fromClipName: currentName,
            toClipName: clipNamed,
            fromTimer: playbackTimer,
            toTimer: destStartTimer,
            elapsed: 0.0,
            duration: duration
        )
        
        self.currentClipName = clipNamed
        self.playbackTimer = destStartTimer
        self.playbackModeOverride = mode
        self.isPlaying = true
        self.isPaused = false
        self.pingPongDirection = (destEffectiveMode == .reverseOnce || destEffectiveMode == .reverseLoop) ? -1 : 1
    }
    
    /// Pauses playback.
    public mutating func pause() {
        isPaused = true
    }
    
    /// Resumes playback if paused.
    public mutating func resume() {
        isPaused = false
    }
    
    /// Stops playback and resets the timer to 0.
    public mutating func stop() {
        isPlaying = false
        isPaused = false
        playbackTimer = 0.0
        transition = nil
        pingPongDirection = 1
    }
}
