import Foundation
import simd

/// An event to trigger playing a one-shot audio clip.
public struct PlaySoundEvent: Event {
    /// The audio clip to play.
    public let clip: AudioClip
    
    /// The playback volume.
    public let volume: Float
    
    /// The pitch/playback rate multiplier.
    public let pitch: Float
    
    /// The world-space position for spatial audio, or nil for non-spatial 2D playback.
    public let position: SIMD3<Float>?
    
    /// Initializes a new play sound event.
    /// - Parameters:
    ///   - clip: The audio clip to play.
    ///   - volume: The playback volume. Defaults to `1.0`.
    ///   - pitch: The pitch/playback rate multiplier. Defaults to `1.0`.
    ///   - position: The world position for spatial audio. Defaults to `nil`.
    public init(
        clip: AudioClip,
        volume: Float = 1.0,
        pitch: Float = 1.0,
        position: SIMD3<Float>? = nil
    ) {
        self.clip = clip
        self.volume = volume
        self.pitch = pitch
        self.position = position
    }
}

/// An event to immediately stop all active audio playback.
public struct StopAllSoundsEvent: Event {
    /// Initializes a new stop all sounds event.
    public init() {}
}
