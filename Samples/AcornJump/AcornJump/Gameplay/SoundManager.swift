import Foundation
import AVFoundation

/// Sound effect and audio synthesizer manager.
@MainActor
public final class SoundManager {
    public static let shared = SoundManager()
    
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    
    private init() {
        setupAudio()
    }
    
    private func setupAudio() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }
        #endif
        
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)
        if let format = format {
            engine.connect(player, to: engine.mainMixerNode, format: format)
            self.audioFormat = format
            self.playerNode = player
            self.audioEngine = engine
            
            try? engine.start()
        }
    }
    
    /// Plays a synthesized multi-frequency sound effect.
    private func playTone(frequencies: [Double], durations: [Double], waveType: String = "sine") {
        guard GameProgressManager.shared.soundEnabled,
              let player = playerNode,
              let format = audioFormat,
              let engine = audioEngine,
              engine.isRunning else { return }
        
        let sampleRate = 44100.0
        let totalDuration = durations.reduce(0, +)
        let totalFrames = AVAudioFrameCount(sampleRate * totalDuration)
        guard totalFrames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else { return }
        buffer.frameLength = totalFrames
        
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        var currentFrame = 0
        for (freq, dur) in zip(frequencies, durations) {
            let segmentFrames = Int(sampleRate * dur)
            let phaseIncrement = (2.0 * Double.pi * freq) / sampleRate
            var phase = 0.0
            
            for i in 0..<segmentFrames {
                if currentFrame >= Int(totalFrames) { break }
                let progress = Double(i) / Double(segmentFrames)
                let envelope = sin(progress * Double.pi) // smooth attack/decay
                
                var sample: Float = 0.0
                if waveType == "sine" {
                    sample = Float(sin(phase) * envelope * 0.3)
                } else if waveType == "square" {
                    sample = Float((sin(phase) > 0 ? 0.2 : -0.2) * envelope)
                } else if waveType == "noise" {
                    sample = Float((Double.random(in: -1.0...1.0)) * envelope * 0.25)
                }
                
                channelData[currentFrame] = sample
                phase += phaseIncrement
                currentFrame += 1
            }
        }
        
        if !player.isPlaying {
            player.play()
        }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }
    
    // MARK: - Game Sound Effects
    
    public func playJump() {
        playTone(frequencies: [350.0, 520.0], durations: [0.04, 0.06], waveType: "sine")
    }
    
    public func playSpring() {
        playTone(frequencies: [400.0, 600.0, 880.0, 1100.0], durations: [0.03, 0.04, 0.05, 0.08], waveType: "sine")
    }
    
    public func playPropeller() {
        playTone(frequencies: [440.0, 480.0, 520.0], durations: [0.03, 0.03, 0.03], waveType: "square")
    }
    
    public func playJetpack() {
        playTone(frequencies: [150.0, 120.0], durations: [0.05, 0.05], waveType: "noise")
    }
    
    public func playShoot() {
        playTone(frequencies: [900.0, 600.0, 300.0], durations: [0.03, 0.03, 0.04], waveType: "square")
    }
    
    public func playAcornCollected() {
        playTone(frequencies: [660.0, 990.0], durations: [0.05, 0.08], waveType: "sine")
    }
    
    public func playStarCollected() {
        playTone(frequencies: [523.25, 659.25, 783.99, 1046.50], durations: [0.06, 0.06, 0.06, 0.12], waveType: "sine")
    }
    
    public func playMonsterDefeated() {
        playTone(frequencies: [250.0, 180.0, 100.0], durations: [0.04, 0.04, 0.06], waveType: "noise")
    }
    
    public func playBreakPlatform() {
        playTone(frequencies: [180.0, 140.0], durations: [0.04, 0.05], waveType: "noise")
    }
    
    public func playShieldHit() {
        playTone(frequencies: [800.0, 1200.0, 400.0], durations: [0.04, 0.04, 0.06], waveType: "sine")
    }
    
    public func playVictory() {
        playTone(frequencies: [523.25, 659.25, 783.99, 1046.50, 1318.51], durations: [0.1, 0.1, 0.1, 0.15, 0.35], waveType: "sine")
    }
    
    public func playGameOver() {
        playTone(frequencies: [440.0, 370.0, 310.0, 220.0], durations: [0.12, 0.12, 0.15, 0.3], waveType: "sine")
    }
}
