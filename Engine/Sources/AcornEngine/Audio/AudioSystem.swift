import Foundation
@preconcurrency import AVFoundation
import simd

extension AudioSourceComponent.RenderingAlgorithm {
    /// Maps the engine rendering algorithm to AVFoundation's `AVAudio3DMixingRenderingAlgorithm`.
    public var avAlgorithm: AVAudio3DMixingRenderingAlgorithm {
        switch self {
        case .equalPowerPanning:
            return .equalPowerPanning
        case .sphericalHead:
            return .sphericalHead
        case .hrtf:
            return .HRTF
        case .soundField:
            return .soundField
        }
    }
}

/// A system that manages spatial 3D audio, audio source playback, audio listener orientation, and one-shot sound effects.
@MainActor
public final class AudioSystem: System {
    /// The underlying AVFoundation audio engine.
    public let audioEngine: AVAudioEngine
    
    /// The 3D environment node used for spatial audio processing and reverb.
    public let environmentNode: AVAudioEnvironmentNode
    
    /// Indicates whether the audio engine is actively running.
    public var isRunning: Bool {
        audioEngine.isRunning
    }
    
    /// Storage for player nodes associated with specific ECS entities.
    private var playerNodes: [Entity: AVAudioPlayerNode] = [:]
    
    /// Tracks whether a player node was connected via spatial or direct mixer.
    private var connectedSpatial: [Entity: Bool] = [:]
    
    /// Node pool for one-shot audio clip playback.
    private var oneShotNodes: [AVAudioPlayerNode] = []
    
    /// Retrieves the player node associated with the given entity, if one exists.
    /// - Parameter entity: The entity to query.
    /// - Returns: The active `AVAudioPlayerNode` or `nil`.
    public func playerNode(for entity: Entity) -> AVAudioPlayerNode? {
        playerNodes[entity]
    }
    
    /// The count of currently active entity player nodes.
    public var activePlayerCount: Int {
        playerNodes.count
    }
    
    /// Initializes the audio system and sets up the audio graph.
    public init() {
        self.audioEngine = AVAudioEngine()
        self.environmentNode = AVAudioEnvironmentNode()
        
        audioEngine.attach(environmentNode)
        audioEngine.connect(environmentNode, to: audioEngine.mainMixerNode, format: nil)
        
        do {
            let renderFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
            try audioEngine.enableManualRenderingMode(.offline, format: renderFormat, maximumFrameCount: 4096)
            try audioEngine.start()
        } catch {
            print("[AudioSystem] Warning: Failed to start AVAudioEngine: \(error.localizedDescription)")
        }
    }
    
    deinit {
        audioEngine.stop()
        for node in playerNodes.values {
            node.stop()
            audioEngine.disconnectNodeOutput(node)
            audioEngine.detach(node)
        }
        for node in oneShotNodes {
            node.stop()
            audioEngine.disconnectNodeOutput(node)
            audioEngine.detach(node)
        }
        audioEngine.disconnectNodeOutput(environmentNode)
        audioEngine.detach(environmentNode)
    }
    
    /// Updates audio listener properties, processes audio source playback, handles audio events, and cleans up detached nodes.
    /// - Parameters:
    ///   - world: The ECS world.
    ///   - deltaTime: The elapsed time in seconds since the last frame.
    public func update(world: World, deltaTime: Double) {
        // 1. Update Listener
        updateListener(world: world)
        
        // 2. Update Audio Sources
        updateSources(world: world)
        
        // 3. Handle One-Shot Sounds (PlaySoundEvent)
        handlePlaySoundEvents(world: world)
        
        // 4. Handle StopAllSoundsEvent
        handleStopAllSoundsEvents(world: world)
        
        // 5. Node Cleanup for removed AudioSource components or destroyed entities
        cleanupRemovedNodes(world: world)
    }
    
    // MARK: - Internal System Passes
    
    private func updateListener(world: World) {
        let listeners = world.entities(with: AudioListenerComponent.self)
        let primaryListener = listeners.first(where: { $0.1.isPrimary }) ?? listeners.first
        
        if let (listenerEntity, listenerComp) = primaryListener {
            let pos = world.worldPosition(for: listenerEntity)
            environmentNode.listenerPosition = AVAudio3DPoint(x: pos.x, y: pos.y, z: pos.z)
            
            if let transform = world.component(ofType: TransformComponent.self, for: listenerEntity) {
                let radToDeg = Float(180.0 / .pi)
                let yawDeg = transform.rotation.y * radToDeg
                let pitchDeg = transform.rotation.x * radToDeg
                let rollDeg = transform.rotation.z * radToDeg
                environmentNode.listenerAngularOrientation = AVAudio3DAngularOrientation(
                    yaw: yawDeg,
                    pitch: pitchDeg,
                    roll: rollDeg
                )
            }
            
            audioEngine.mainMixerNode.outputVolume = listenerComp.masterVolume
        }
    }
    
    private func updateSources(world: World) {
        let sources = world.entities(with: AudioSourceComponent.self)
        
        for (entity, sourceComp) in sources {
            let node: AVAudioPlayerNode
            let requiresReconnect: Bool
            
            if let existing = playerNodes[entity] {
                node = existing
                requiresReconnect = (connectedSpatial[entity] != sourceComp.isSpatial)
            } else {
                node = AVAudioPlayerNode()
                audioEngine.attach(node)
                playerNodes[entity] = node
                requiresReconnect = true
            }
            
            if requiresReconnect {
                audioEngine.disconnectNodeOutput(node)
                if sourceComp.isSpatial {
                    let bus = environmentNode.nextAvailableInputBus
                    audioEngine.connect(node, to: environmentNode, fromBus: 0, toBus: bus, format: sourceComp.clip?.format)
                    connectedSpatial[entity] = true
                } else {
                    let bus = audioEngine.mainMixerNode.nextAvailableInputBus
                    audioEngine.connect(node, to: audioEngine.mainMixerNode, fromBus: 0, toBus: bus, format: sourceComp.clip?.format)
                    connectedSpatial[entity] = false
                }
            }
            
            // Spatial & 3D Parameters
            if sourceComp.isSpatial {
                let pos = world.worldPosition(for: entity)
                node.position = AVAudio3DPoint(x: pos.x, y: pos.y, z: pos.z)
                node.renderingAlgorithm = sourceComp.renderingAlgorithm.avAlgorithm
                node.reverbBlend = sourceComp.reverbBlend
                if sourceComp.renderingAlgorithm == .sphericalHead {
                    node.rate = sourceComp.pitch
                }
            }
            node.volume = sourceComp.volume
            
            // Playback State Handling
            var updatedComp = sourceComp
            let shouldPlay = updatedComp.isPlayingRequested || (updatedComp.playOnAwake && updatedComp.state == .stopped)
            
            if shouldPlay {
                if let clip = updatedComp.clip {
                    node.stop()
                    let options: AVAudioPlayerNodeBufferOptions = updatedComp.isLooping ? .loops : []
                    node.scheduleBuffer(clip.buffer, at: nil, options: options, completionHandler: nil)
                    if audioEngine.isRunning && !node.isPlaying {
                        node.play()
                    }
                    updatedComp.state = .playing
                }
            } else if updatedComp.isPauseRequested {
                node.pause()
                updatedComp.state = .paused
            } else if updatedComp.isStopRequested {
                node.stop()
                updatedComp.state = .stopped
            } else if updatedComp.state == .playing && !node.isPlaying && audioEngine.isRunning {
                // Non-looping playback ended naturally
                updatedComp.state = .stopped
            }
            
            // Clear one-shot request flags
            updatedComp.isPlayingRequested = false
            updatedComp.isStopRequested = false
            updatedComp.isPauseRequested = false
            
            world.addComponent(updatedComp, to: entity)
        }
    }
    
    private func handlePlaySoundEvents(world: World) {
        let playEvents = world.eventBus.events(ofType: PlaySoundEvent.self)
        
        for event in playEvents {
            let node: AVAudioPlayerNode
            if let idleNode = oneShotNodes.first(where: { !$0.isPlaying }) {
                node = idleNode
            } else {
                node = AVAudioPlayerNode()
                audioEngine.attach(node)
                oneShotNodes.append(node)
            }
            
            audioEngine.disconnectNodeOutput(node)
            if let pos = event.position {
                let bus = environmentNode.nextAvailableInputBus
                audioEngine.connect(node, to: environmentNode, fromBus: 0, toBus: bus, format: event.clip.format)
                node.position = AVAudio3DPoint(x: pos.x, y: pos.y, z: pos.z)
            } else {
                let bus = audioEngine.mainMixerNode.nextAvailableInputBus
                audioEngine.connect(node, to: audioEngine.mainMixerNode, fromBus: 0, toBus: bus, format: event.clip.format)
            }
            
            node.volume = event.volume
            node.stop()
            node.scheduleBuffer(event.clip.buffer, at: nil, options: [], completionHandler: nil)
            if audioEngine.isRunning && !node.isPlaying {
                node.play()
            }
        }
        
        // Clean up excess idle one-shot nodes to prevent unbounded memory growth
        if oneShotNodes.count > 16 {
            var activeNodes: [AVAudioPlayerNode] = []
            for node in oneShotNodes {
                if node.isPlaying || activeNodes.count < 16 {
                    activeNodes.append(node)
                } else {
                    node.stop()
                    audioEngine.disconnectNodeOutput(node)
                    audioEngine.detach(node)
                }
            }
            oneShotNodes = activeNodes
        }
    }
    
    private func handleStopAllSoundsEvents(world: World) {
        if world.eventBus.hasEvents(ofType: StopAllSoundsEvent.self) {
            for node in playerNodes.values {
                node.stop()
            }
            for (entity, var sourceComp) in world.entities(with: AudioSourceComponent.self) {
                sourceComp.state = .stopped
                sourceComp.isPlayingRequested = false
                sourceComp.isPauseRequested = false
                sourceComp.isStopRequested = false
                world.addComponent(sourceComp, to: entity)
            }
            for node in oneShotNodes {
                node.stop()
            }
        }
    }
    
    private func cleanupRemovedNodes(world: World) {
        let currentSourceEntities = Set(world.entities(with: AudioSourceComponent.self).map(\.0))
        let trackedEntities = Array(playerNodes.keys)
        
        for entity in trackedEntities {
            if !currentSourceEntities.contains(entity) {
                if let node = playerNodes[entity] {
                    node.stop()
                    audioEngine.disconnectNodeOutput(node)
                    audioEngine.detach(node)
                    playerNodes.removeValue(forKey: entity)
                    connectedSpatial.removeValue(forKey: entity)
                }
            }
        }
    }
}
