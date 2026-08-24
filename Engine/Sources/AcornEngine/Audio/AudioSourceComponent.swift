import Foundation

/// A component that emits sound in 3D or 2D space.
public struct AudioSourceComponent: Component {
    /// Playback state of the audio source.
    public enum PlaybackState: Sendable {
        case stopped
        case playing
        case paused
    }
    
    /// 3D audio rendering algorithms.
    public enum RenderingAlgorithm: Int, Sendable {
        case equalPowerPanning = 0
        case sphericalHead = 1
        case hrtf = 2
        case soundField = 3
    }
    
    /// The audio clip to play.
    public var clip: AudioClip?
    
    /// The playback volume (typically 0.0 to 1.0).
    public var volume: Float
    
    /// Pitch/playback rate multiplier (0.5 to 2.0).
    public var pitch: Float
    
    /// Whether playback should loop automatically.
    public var isLooping: Bool
    
    /// Whether the audio source participates in 3D spatial audio.
    public var isSpatial: Bool
    
    /// Whether the sound should automatically play when initialized or awake.
    public var playOnAwake: Bool
    
    /// Minimum distance for 3D attenuation.
    public var minDistance: Float
    
    /// Maximum distance for 3D attenuation.
    public var maxDistance: Float
    
    /// Reference distance for 3D attenuation.
    public var referenceDistance: Float
    
    /// Reverb blend factor (0.0 to 1.0).
    public var reverbBlend: Float
    
    /// 3D spatial rendering algorithm.
    public var renderingAlgorithm: RenderingAlgorithm
    
    /// The current playback state.
    public internal(set) var state: PlaybackState
    
    /// Request flag to start playback.
    public internal(set) var isPlayingRequested: Bool
    
    /// Request flag to stop playback.
    public internal(set) var isStopRequested: Bool
    
    /// Request flag to pause playback.
    public internal(set) var isPauseRequested: Bool
    
    /// Initializes a new audio source component.
    public init(
        clip: AudioClip? = nil,
        volume: Float = 1.0,
        pitch: Float = 1.0,
        isLooping: Bool = false,
        isSpatial: Bool = true,
        playOnAwake: Bool = false,
        minDistance: Float = 1.0,
        maxDistance: Float = 100.0,
        referenceDistance: Float = 1.0,
        reverbBlend: Float = 0.0,
        renderingAlgorithm: RenderingAlgorithm = .equalPowerPanning
    ) {
        self.clip = clip
        self.volume = max(0.0, volume)
        self.pitch = max(0.5, min(2.0, pitch))
        self.isLooping = isLooping
        self.isSpatial = isSpatial
        self.playOnAwake = playOnAwake
        self.minDistance = minDistance
        self.maxDistance = maxDistance
        self.referenceDistance = referenceDistance
        self.reverbBlend = max(0.0, min(1.0, reverbBlend))
        self.renderingAlgorithm = renderingAlgorithm
        self.state = .stopped
        self.isPlayingRequested = false
        self.isStopRequested = false
        self.isPauseRequested = false
    }
    
    /// Requests playback of the audio source.
    public mutating func play() {
        isPlayingRequested = true
        isStopRequested = false
        isPauseRequested = false
    }
    
    /// Requests playback to stop.
    public mutating func stop() {
        isStopRequested = true
        isPlayingRequested = false
        isPauseRequested = false
    }
    
    /// Requests playback to pause.
    public mutating func pause() {
        isPauseRequested = true
        isPlayingRequested = false
        isStopRequested = false
    }
    
    /// Requests playback to resume from paused state.
    public mutating func resume() {
        isPlayingRequested = true
        isStopRequested = false
        isPauseRequested = false
    }
}
