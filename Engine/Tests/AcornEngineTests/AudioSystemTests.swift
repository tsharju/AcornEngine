import Testing
import Foundation
@preconcurrency import AVFoundation
import simd
@testable import AcornEngine

private final class MockMesh: Mesh, @unchecked Sendable {
    var vertexCount: Int = 0
    #if DEBUG
    var vertices: [Vertex] = []
    #endif
}

private final class MockRenderer: Renderer, @unchecked Sendable {
    func createMesh(vertices: [Vertex]) -> (any Mesh)? {
        let mesh = MockMesh()
        mesh.vertexCount = vertices.count
        #if DEBUG
        mesh.vertices = vertices
        #endif
        return mesh
    }
    
    func render(mesh: any Mesh, texture: (any Texture)?, uniforms: GlobalUniforms, context: any RenderContext) {}
    func renderText(mesh: any Mesh, texture: any Texture, uniforms: SDFUniforms, context: any RenderContext) {}
    func renderSprite(mesh: any Mesh, texture: any Texture, uniforms: SpriteUniforms, context: any RenderContext) {}
}

@Suite("AudioSystem Tests", .serialized)
@MainActor
struct AudioSystemTests {
    
    // MARK: - 1. Synthetic AudioClip Generation
    
    @Test("Synthetic AudioClip generation (tone and silence)")
    func testSyntheticAudioClipGeneration() {
        // Tone Generation
        let toneClip = AudioClip.makeTone(frequency: 440.0, duration: 0.5, sampleRate: 44100.0, volume: 0.8)
        
        #expect(toneClip.name == "Tone_440Hz")
        #expect(toneClip.sampleRate == 44100.0)
        #expect(toneClip.channelCount == 1)
        #expect(abs(toneClip.duration - 0.5) < 0.01)
        #expect(toneClip.buffer.frameLength == 22050)
        
        if let floatData = toneClip.buffer.floatChannelData {
            let channel0 = floatData[0]
            var hasNonZero = false
            for i in 0..<Int(toneClip.buffer.frameLength) {
                if abs(channel0[i]) > 0.001 {
                    hasNonZero = true
                    break
                }
            }
            #expect(hasNonZero)
        } else {
            Issue.record("Expected floatChannelData to be non-nil")
        }
        
        // Silence Generation
        let silenceClip = AudioClip.makeSilence(duration: 0.25, sampleRate: 44100.0)
        
        #expect(silenceClip.name == "Silence")
        #expect(silenceClip.sampleRate == 44100.0)
        #expect(silenceClip.channelCount == 1)
        #expect(abs(silenceClip.duration - 0.25) < 0.01)
        #expect(silenceClip.buffer.frameLength == 11025)
        
        if let floatData = silenceClip.buffer.floatChannelData {
            let channel0 = floatData[0]
            var allZero = true
            for i in 0..<Int(silenceClip.buffer.frameLength) {
                if channel0[i] != 0.0 {
                    allZero = false
                    break
                }
            }
            #expect(allZero)
        } else {
            Issue.record("Expected floatChannelData to be non-nil")
        }
    }
    
    // MARK: - 2. Audio Listener Synchronization
    
    @Test("Audio listener position, orientation, and master volume synchronization")
    func testAudioListenerSynchronization() {
        let world = World()
        let audioSystem = AudioSystem()
        world.registerSystem(audioSystem)
        
        let listenerEntity = world.createEntity()
        world.addComponent(AudioListenerComponent(isPrimary: true, masterVolume: 0.8), to: listenerEntity)
        world.addComponent(TransformComponent(
            position: SIMD3<Float>(10, 5, -20),
            rotation: SIMD3<Float>(Float.pi / 4.0, Float.pi / 2.0, 0)
        ), to: listenerEntity)
        
        world.update(deltaTime: 0.016)
        
        #expect(audioSystem.environmentNode.listenerPosition.x == 10)
        #expect(audioSystem.environmentNode.listenerPosition.y == 5)
        #expect(audioSystem.environmentNode.listenerPosition.z == -20)
        
        // Listener orientation (degrees): pitch = 45 deg, yaw = 90 deg, roll = 0
        let orientation = audioSystem.environmentNode.listenerAngularOrientation
        #expect(abs(orientation.pitch - 45.0) < 0.1)
        #expect(abs(orientation.yaw - 90.0) < 0.1)
        #expect(abs(orientation.roll - 0.0) < 0.1)
        
        #expect(audioSystem.audioEngine.mainMixerNode.outputVolume == 0.8)
    }
    
    // MARK: - 3. Audio Source Playback Lifecycle
    
    @Test("AudioSourceComponent playback lifecycle: play, pause, resume, stop")
    func testAudioSourcePlaybackLifecycle() {
        let world = World()
        let audioSystem = AudioSystem()
        world.registerSystem(audioSystem)
        
        let clip = AudioClip.makeTone(frequency: 440.0, duration: 1.0)
        let entity = world.createEntity()
        var source = AudioSourceComponent(clip: clip, playOnAwake: false)
        
        // 1. Play
        source.play()
        world.addComponent(source, to: entity)
        
        world.update(deltaTime: 1.0 / 60.0)
        
        guard let playerNode = audioSystem.playerNode(for: entity) else {
            Issue.record("Player node should exist for entity")
            return
        }
        
        let playingComp = world.component(ofType: AudioSourceComponent.self, for: entity)
        #expect(playingComp?.state == .playing)
        if audioSystem.audioEngine.isRunning {
            #expect(playerNode.isPlaying)
        }
        
        // 2. Pause
        guard var currentSource = world.component(ofType: AudioSourceComponent.self, for: entity) else {
            Issue.record("Expected AudioSourceComponent on entity")
            return
        }
        currentSource.pause()
        world.addComponent(currentSource, to: entity)
        
        world.update(deltaTime: 0.016)
        
        let pausedComp = world.component(ofType: AudioSourceComponent.self, for: entity)
        #expect(pausedComp?.state == .paused)
        #expect(!playerNode.isPlaying)
        
        // 3. Resume
        guard var pausedSource = world.component(ofType: AudioSourceComponent.self, for: entity) else {
            Issue.record("Expected AudioSourceComponent on entity")
            return
        }
        pausedSource.resume()
        world.addComponent(pausedSource, to: entity)
        
        world.update(deltaTime: 0.016)
        
        let resumedComp = world.component(ofType: AudioSourceComponent.self, for: entity)
        #expect(resumedComp?.state == .playing)
        if audioSystem.audioEngine.isRunning {
            #expect(playerNode.isPlaying)
        }
        
        // 4. Stop
        guard var playingAgainSource = world.component(ofType: AudioSourceComponent.self, for: entity) else {
            Issue.record("Expected AudioSourceComponent on entity")
            return
        }
        playingAgainSource.stop()
        world.addComponent(playingAgainSource, to: entity)
        
        world.update(deltaTime: 0.016)
        
        let stoppedComp = world.component(ofType: AudioSourceComponent.self, for: entity)
        #expect(stoppedComp?.state == .stopped)
        #expect(!playerNode.isPlaying)
    }
    
    // MARK: - 4. Audio Source Spatial Positioning
    
    @Test("AudioSourceComponent 3D spatial positioning synchronization")
    func testAudioSourceSpatialPositioning() {
        let world = World()
        let audioSystem = AudioSystem()
        world.registerSystem(audioSystem)
        
        let clip = AudioClip.makeTone(frequency: 440.0, duration: 1.0)
        let entity = world.createEntity()
        var source = AudioSourceComponent(clip: clip, isSpatial: true)
        source.play()
        world.addComponent(TransformComponent(position: SIMD3<Float>(1.0, 2.0, 3.0)), to: entity)
        world.addComponent(source, to: entity)
        
        world.update(deltaTime: 0.016)
        
        guard let playerNode = audioSystem.playerNode(for: entity) else {
            Issue.record("Expected playerNode for entity")
            return
        }
        
        #expect(playerNode.position.x == 1.0)
        #expect(playerNode.position.y == 2.0)
        #expect(playerNode.position.z == 3.0)
        
        // Change transform position to (12, 3, -5)
        world.addComponent(TransformComponent(position: SIMD3<Float>(12.0, 3.0, -5.0)), to: entity)
        world.update(deltaTime: 0.016)
        
        #expect(playerNode.position.x == 12.0)
        #expect(playerNode.position.y == 3.0)
        #expect(playerNode.position.z == -5.0)
    }
    
    // MARK: - 5. Audio Source Looping, Volume, and Pitch
    
    @Test("AudioSourceComponent looping, volume, and pitch configuration")
    func testAudioSourceLoopingAndVolume() {
        let world = World()
        let audioSystem = AudioSystem()
        world.registerSystem(audioSystem)
        
        let clip = AudioClip.makeTone(frequency: 440.0, duration: 1.0)
        let entity = world.createEntity()
        var source = AudioSourceComponent(
            clip: clip,
            volume: 0.5,
            pitch: 1.2,
            isLooping: true,
            renderingAlgorithm: .sphericalHead
        )
        source.play()
        world.addComponent(source, to: entity)
        
        world.update(deltaTime: 0.016)
        
        guard let playerNode = audioSystem.playerNode(for: entity) else {
            Issue.record("Expected playerNode for entity")
            return
        }
        
        #expect(playerNode.volume == 0.5)
        #expect(playerNode.rate == 1.2)
        
        let comp = world.component(ofType: AudioSourceComponent.self, for: entity)
        #expect(comp?.isLooping == true)
        #expect(comp?.volume == 0.5)
        #expect(comp?.pitch == 1.2)
    }
    
    // MARK: - 6. PlaySoundEvent One-Shot
    
    @Test("PlaySoundEvent one-shot playback event processing")
    func testPlaySoundEventOneShot() {
        let world = World()
        let audioSystem = AudioSystem()
        world.registerSystem(audioSystem)
        
        let clip = AudioClip.makeTone(frequency: 880.0, duration: 0.2)
        world.eventBus.publish(PlaySoundEvent(
            clip: clip,
            volume: 0.8,
            pitch: 1.0,
            position: SIMD3<Float>(2.0, 4.0, 6.0)
        ))
        
        #expect(world.eventBus.hasEvents(ofType: PlaySoundEvent.self))
        world.update(deltaTime: 0.016)
        #expect(!world.eventBus.hasEvents(ofType: PlaySoundEvent.self))
    }
    
    // MARK: - 7. Entity Destruction Node Cleanup
    
    @Test("Entity destruction cleans up and detaches player nodes")
    func testEntityDestructionNodeCleanup() {
        let world = World()
        let audioSystem = AudioSystem()
        world.registerSystem(audioSystem)
        
        let clip = AudioClip.makeSilence(duration: 1.0)
        let entity = world.createEntity()
        var source = AudioSourceComponent(clip: clip)
        source.play()
        world.addComponent(source, to: entity)
        
        world.update(deltaTime: 0.016)
        
        #expect(audioSystem.playerNode(for: entity) != nil)
        #expect(audioSystem.activePlayerCount == 1)
        
        world.destroyEntity(entity)
        world.update(deltaTime: 0.016)
        
        #expect(audioSystem.playerNode(for: entity) == nil)
        #expect(audioSystem.activePlayerCount == 0)
    }
    
    // MARK: - 8. AudioListenerComponent Defaults & Clamping
    
    @Test("AudioListenerComponent default values and volume clamping")
    func testAudioListenerComponent() {
        var listener = AudioListenerComponent()
        #expect(listener.isPrimary == true)
        #expect(listener.masterVolume == 1.0)
        
        listener.masterVolume = 1.5
        #expect(listener.masterVolume == 1.0)
        
        listener.masterVolume = -0.5
        #expect(listener.masterVolume == 0.0)
        
        let customListener = AudioListenerComponent(isPrimary: false, masterVolume: 0.6)
        #expect(customListener.isPrimary == false)
        #expect(customListener.masterVolume == 0.6)
    }
    
    // MARK: - 9. Engine Audio Integration
    
    @Test("Engine integrates and updates AudioSystem")
    func testEngineAudioIntegration() {
        let renderer = MockRenderer()
        let audioSystem = AudioSystem()
        let engine = Engine(renderer: renderer, audioSystem: audioSystem)
        
        let entity = engine.world.createEntity()
        let clip = AudioClip.makeTone()
        let source = AudioSourceComponent(clip: clip, playOnAwake: true)
        engine.world.addComponent(source, to: entity)
        
        engine.tick(deltaTime: 0.016)
        
        let updatedSource = engine.world.component(ofType: AudioSourceComponent.self, for: entity)
        #expect(updatedSource?.state == .playing)
    }
}
