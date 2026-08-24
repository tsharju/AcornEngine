import Foundation
@preconcurrency import AVFoundation

/// Errors that can occur when loading or creating audio clips.
public enum AudioError: Error, Sendable {
    case bufferCreationFailed
    case resourceNotFound(String)
    case readFailed
}

/// An audio asset wrapper containing an in-memory PCM audio buffer.
public final class AudioClip: @unchecked Sendable {
    /// The name or identifier of the audio clip.
    public let name: String
    
    /// The underlying PCM audio buffer.
    public let buffer: AVAudioPCMBuffer
    
    /// The duration of the audio clip in seconds.
    public var duration: TimeInterval {
        guard buffer.format.sampleRate > 0 else { return 0.0 }
        return Double(buffer.frameLength) / buffer.format.sampleRate
    }
    
    /// The sample rate in Hz.
    public var sampleRate: Double {
        buffer.format.sampleRate
    }
    
    /// The number of audio channels.
    public var channelCount: AVAudioChannelCount {
        buffer.format.channelCount
    }
    
    /// The audio format of the underlying buffer.
    public var format: AVAudioFormat {
        buffer.format
    }
    
    /// Initializes an audio clip with a name and an existing PCM buffer.
    /// - Parameters:
    ///   - name: The name of the clip. Defaults to `""`.
    ///   - buffer: The PCM buffer containing audio data.
    public init(name: String = "", buffer: AVAudioPCMBuffer) {
        self.name = name
        self.buffer = buffer
    }
    
    /// Initializes an audio clip by loading audio from a file URL.
    /// - Parameter url: The file URL of the audio file.
    public convenience init(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(max(1, file.length))
        ) else {
            throw AudioError.bufferCreationFailed
        }
        try file.read(into: pcmBuffer)
        let name = url.deletingPathExtension().lastPathComponent
        self.init(name: name, buffer: pcmBuffer)
    }
    
    /// Initializes an audio clip from a named bundle resource.
    /// - Parameters:
    ///   - name: The name of the resource file.
    ///   - bundle: The bundle containing the resource. Defaults to `.main`.
    public convenience init?(named name: String, bundle: Bundle = .main) {
        let ext = (name as NSString).pathExtension
        let baseName = (name as NSString).deletingPathExtension
        
        var url: URL?
        if !ext.isEmpty {
            url = bundle.url(forResource: baseName, withExtension: ext)
        } else {
            let extensions = ["wav", "mp3", "m4a", "aif", "aiff", "caf", "aac", "ogg"]
            for testExt in extensions {
                if let found = bundle.url(forResource: name, withExtension: testExt) {
                    url = found
                    break
                }
            }
        }
        
        guard let fileUrl = url else { return nil }
        try? self.init(url: fileUrl)
    }
    
    /// Creates a synthetic sine wave tone clip for testing or procedural sound.
    /// - Parameters:
    ///   - frequency: Frequency of the sine wave in Hz (defaults to 440.0 Hz).
    ///   - duration: Duration in seconds (defaults to 1.0s).
    ///   - sampleRate: Sample rate in Hz (defaults to 44100.0 Hz).
    ///   - volume: Volume amplitude factor 0.0...1.0 (defaults to 0.5).
    /// - Returns: A new `AudioClip` containing the sine tone.
    public static func makeTone(
        frequency: Double = 440.0,
        duration: Double = 1.0,
        sampleRate: Double = 44100.0,
        volume: Float = 0.5
    ) -> AudioClip {
        let channelCount: AVAudioChannelCount = 1
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount) else {
            fatalError("Failed to create standard audio format for tone generation")
        }
        let frameCount = AVAudioFrameCount(max(1.0, sampleRate * duration))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            fatalError("Failed to allocate AVAudioPCMBuffer for tone generation")
        }
        buffer.frameLength = frameCount
        
        if let floatData = buffer.floatChannelData {
            for channel in 0..<Int(channelCount) {
                let channelBuffer = floatData[channel]
                for frame in 0..<Int(frameCount) {
                    let sample = Float(sin(2.0 * .pi * frequency * Double(frame) / sampleRate)) * volume
                    channelBuffer[frame] = sample
                }
            }
        }
        
        return AudioClip(name: "Tone_\(Int(frequency))Hz", buffer: buffer)
    }
    
    /// Creates a synthetic silent PCM buffer of the requested duration.
    /// - Parameters:
    ///   - duration: Duration in seconds (defaults to 1.0s).
    ///   - sampleRate: Sample rate in Hz (defaults to 44100.0 Hz).
    /// - Returns: A new `AudioClip` containing silent PCM audio data.
    public static func makeSilence(
        duration: Double = 1.0,
        sampleRate: Double = 44100.0
    ) -> AudioClip {
        let channelCount: AVAudioChannelCount = 1
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount) else {
            fatalError("Failed to create standard audio format for silence generation")
        }
        let frameCount = AVAudioFrameCount(max(1.0, sampleRate * duration))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            fatalError("Failed to allocate AVAudioPCMBuffer for silence generation")
        }
        buffer.frameLength = frameCount
        
        if let floatData = buffer.floatChannelData {
            for channel in 0..<Int(channelCount) {
                floatData[channel].initialize(repeating: 0.0, count: Int(frameCount))
            }
        }
        
        return AudioClip(name: "Silence", buffer: buffer)
    }
}
