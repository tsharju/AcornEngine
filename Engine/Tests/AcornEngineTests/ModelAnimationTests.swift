import Testing
import Foundation
import AcornMath
#if canImport(Metal)
import Metal
#endif
@testable import AcornEngine

@Suite("3D Model Animation Tests")
@MainActor
struct ModelAnimationTests {
    
    @Test("ModelAnimationChannel linear, step, and cubic spline evaluation")
    func testChannelInterpolation() {
        // Translation channel with Linear interpolation
        let times: [Float] = [0.0, 1.0]
        let values: [Float] = [
            0.0, 0.0, 0.0,
            10.0, 20.0, 30.0
        ]
        let linearChannel = ModelAnimationChannel(
            targetNodeIndex: 0,
            path: .translation,
            interpolation: .linear,
            keyframeTimes: times,
            keyframeValues: values,
            valuesPerKeyframe: 3
        )
        
        let val0 = linearChannel.evaluateVec3(at: 0.0)
        #expect(val0 == SIMD3<Float>(0.0, 0.0, 0.0))
        
        let valHalf = linearChannel.evaluateVec3(at: 0.5)
        #expect(valHalf == SIMD3<Float>(5.0, 10.0, 15.0))
        
        let val1 = linearChannel.evaluateVec3(at: 1.0)
        #expect(val1 == SIMD3<Float>(10.0, 20.0, 30.0))
        
        // Out of bounds clamping
        let valBefore = linearChannel.evaluateVec3(at: -1.0)
        #expect(valBefore == SIMD3<Float>(0.0, 0.0, 0.0))
        let valAfter = linearChannel.evaluateVec3(at: 2.0)
        #expect(valAfter == SIMD3<Float>(10.0, 20.0, 30.0))
        
        // Step interpolation
        let stepChannel = ModelAnimationChannel(
            targetNodeIndex: 0,
            path: .translation,
            interpolation: .step,
            keyframeTimes: times,
            keyframeValues: values,
            valuesPerKeyframe: 3
        )
        #expect(stepChannel.evaluateVec3(at: 0.2) == SIMD3<Float>(0.0, 0.0, 0.0))
        #expect(stepChannel.evaluateVec3(at: 0.99) == SIMD3<Float>(0.0, 0.0, 0.0))
        #expect(stepChannel.evaluateVec3(at: 1.0) == SIMD3<Float>(10.0, 20.0, 30.0))
        
        // Rotation channel with SLERP
        let rotTimes: [Float] = [0.0, 1.0]
        let angle = Float.pi / 2.0
        let rotValues: [Float] = [
            0.0, 0.0, 0.0, 1.0, // identity
            0.0, 0.0, sin(angle / 2.0), cos(angle / 2.0) // 90 deg Z
        ]
        let rotChannel = ModelAnimationChannel(
            targetNodeIndex: 0,
            path: .rotation,
            interpolation: .linear,
            keyframeTimes: rotTimes,
            keyframeValues: rotValues,
            valuesPerKeyframe: 4
        )
        
        let rotMid = rotChannel.evaluateVec4(at: 0.5)
        let expectedHalfAngle = Float.pi / 4.0
        #expect(rotMid != nil)
        #expect(abs(rotMid!.z - sin(expectedHalfAngle / 2.0)) < 0.0001)
        #expect(abs(rotMid!.w - cos(expectedHalfAngle / 2.0)) < 0.0001)
    }
    
    @Test("ModelAnimationComponent multi-clip management and controls")
    func testComponentControls() {
        let idleClip = ModelAnimationClip(name: "Idle", duration: 1.0, playbackMode: .loop)
        let walkClip = ModelAnimationClip(name: "Walk", duration: 2.0, playbackMode: .loop)
        let jumpClip = ModelAnimationClip(name: "Jump", duration: 0.8, playbackMode: .once)
        
        var anim = ModelAnimationComponent(clips: [idleClip, walkClip], initialClip: "Idle")
        #expect(anim.currentClipName == "Idle")
        #expect(anim.isPlaying == true)
        #expect(anim.isPaused == false)
        #expect(anim.clips.count == 2)
        
        anim.addClip(jumpClip)
        #expect(anim.clips.count == 3)
        #expect(anim.clips["Jump"] != nil)
        
        anim.pause()
        #expect(anim.isPaused == true)
        
        anim.resume()
        #expect(anim.isPaused == false)
        
        anim.play(clipNamed: "Walk")
        #expect(anim.currentClipName == "Walk")
        #expect(anim.playbackTimer == 0.0)
        
        anim.stop()
        #expect(anim.isPlaying == false)
        #expect(anim.playbackTimer == 0.0)
        
        anim.removeClip(named: "Walk")
        #expect(anim.clips["Walk"] == nil)
    }
    
    @Test("ModelAnimationSystem loop mode advances and dispatches loop events")
    func testLoopPlaybackAndEvents() {
        let world = World()
        let animSystem = ModelAnimationSystem()
        world.registerSystem(animSystem)
        
        let times: [Float] = [0.0, 1.0]
        let values: [Float] = [
            0.0, 0.0, 0.0,
            0.0, 2.0, 0.0
        ]
        let channel = ModelAnimationChannel(
            targetNodeIndex: 0,
            path: .translation,
            interpolation: .linear,
            keyframeTimes: times,
            keyframeValues: values,
            valuesPerKeyframe: 3
        )
        let clip = ModelAnimationClip(name: "Bobbing", duration: 1.0, channels: [channel], playbackMode: .loop)
        
        let nodeEntity = world.createEntity()
        world.addComponent(TransformComponent(position: .zero), to: nodeEntity)
        
        let rootEntity = world.createEntity()
        let animComp = ModelAnimationComponent(
            clips: [clip],
            initialClip: "Bobbing",
            isPlaying: true,
            nodeEntities: [nodeEntity],
            nodeRestTransforms: [NodeRestTransform()]
        )
        world.addComponent(animComp, to: rootEntity)
        
        var loopCount = 0
        world.eventBus.subscribe(ModelAnimationLoopedEvent.self) { evt in
            if evt.entity == rootEntity && evt.clipName == "Bobbing" {
                loopCount += 1
            }
        }
        
        // Tick 0.5s -> node position should be (0, 1, 0)
        world.update(deltaTime: 0.5)
        let pos1 = world.component(ofType: TransformComponent.self, for: nodeEntity)?.position
        #expect(pos1 != nil)
        #expect(abs(pos1!.y - 1.0) < 0.001)
        #expect(loopCount == 0)
        
        // Tick another 0.6s -> total 1.1s -> wrapped past 1.0s, loop event fired!
        world.update(deltaTime: 0.6)
        #expect(loopCount == 1)
        let pos2 = world.component(ofType: TransformComponent.self, for: nodeEntity)?.position
        #expect(pos2 != nil)
        #expect(abs(pos2!.y - 0.2) < 0.001) // at t = 0.1
    }
    
    @Test("ModelAnimationSystem once mode completes and publishes completion event")
    func testOncePlaybackAndEvents() {
        let world = World()
        let animSystem = ModelAnimationSystem()
        world.registerSystem(animSystem)
        
        let times: [Float] = [0.0, 1.0]
        let values: [Float] = [0.0, 0.0, 0.0, 5.0, 0.0, 0.0]
        let channel = ModelAnimationChannel(
            targetNodeIndex: 0,
            path: .translation,
            interpolation: .linear,
            keyframeTimes: times,
            keyframeValues: values,
            valuesPerKeyframe: 3
        )
        let clip = ModelAnimationClip(name: "Slide", duration: 1.0, channels: [channel], playbackMode: .once)
        
        let nodeEntity = world.createEntity()
        world.addComponent(TransformComponent(position: .zero), to: nodeEntity)
        
        let rootEntity = world.createEntity()
        let animComp = ModelAnimationComponent(
            clips: [clip],
            initialClip: "Slide",
            isPlaying: true,
            nodeEntities: [nodeEntity],
            nodeRestTransforms: [NodeRestTransform()]
        )
        world.addComponent(animComp, to: rootEntity)
        
        var completed = false
        world.eventBus.subscribe(ModelAnimationCompletedEvent.self) { evt in
            if evt.entity == rootEntity && evt.clipName == "Slide" {
                completed = true
            }
        }
        
        world.update(deltaTime: 0.5)
        #expect(!completed)
        
        world.update(deltaTime: 0.6)
        #expect(completed)
        
        let finalPos = world.component(ofType: TransformComponent.self, for: nodeEntity)?.position
        #expect(finalPos == SIMD3<Float>(5.0, 0.0, 0.0))
        
        let currentAnim = world.component(ofType: ModelAnimationComponent.self, for: rootEntity)
        #expect(currentAnim?.isPlaying == false)
    }
    
    @Test("ModelAnimationSystem crossfade transition blends positions and rotations")
    func testCrossfadeTransition() {
        let world = World()
        let animSystem = ModelAnimationSystem()
        world.registerSystem(animSystem)
        
        // Clip A: Translation (0, 0, 0) -> (0, 10, 0)
        let channelA = ModelAnimationChannel(
            targetNodeIndex: 0,
            path: .translation,
            interpolation: .linear,
            keyframeTimes: [0.0, 1.0],
            keyframeValues: [0, 0, 0, 0, 10, 0],
            valuesPerKeyframe: 3
        )
        let clipA = ModelAnimationClip(name: "Rise", duration: 1.0, channels: [channelA], playbackMode: .loop)
        
        // Clip B: Translation (10, 0, 0) -> (20, 0, 0)
        let channelB = ModelAnimationChannel(
            targetNodeIndex: 0,
            path: .translation,
            interpolation: .linear,
            keyframeTimes: [0.0, 1.0],
            keyframeValues: [10, 0, 0, 20, 0, 0],
            valuesPerKeyframe: 3
        )
        let clipB = ModelAnimationClip(name: "Move", duration: 1.0, channels: [channelB], playbackMode: .loop)
        
        let nodeEntity = world.createEntity()
        world.addComponent(TransformComponent(position: .zero), to: nodeEntity)
        
        let rootEntity = world.createEntity()
        let animComp = ModelAnimationComponent(
            clips: [clipA, clipB],
            initialClip: "Rise",
            isPlaying: true,
            nodeEntities: [nodeEntity],
            nodeRestTransforms: [NodeRestTransform()]
        )
        world.addComponent(animComp, to: rootEntity)
        
        // Advance Clip A to t = 0.5 -> pos = (0, 5, 0)
        world.update(deltaTime: 0.5)
        let posRise = world.component(ofType: TransformComponent.self, for: nodeEntity)?.position
        #expect(abs(posRise!.y - 5.0) < 0.01)
        
        // Start transition to Clip B over 1.0s
        world.mutateComponent(ofType: ModelAnimationComponent.self, for: rootEntity) { anim in
            anim.transition(to: "Move", duration: 1.0)
        }
        
        var transitionCompleted = false
        world.eventBus.subscribe(ModelAnimationTransitionCompletedEvent.self) { evt in
            if evt.entity == rootEntity && evt.clipName == "Move" {
                transitionCompleted = true
            }
        }
        
        // Advance 0.5s -> halfway through transition (alpha = 0.5)
        // Clip A at t = 0.5 + 0.5 = 1.0 -> posA = (0, 10, 0)
        // Clip B at t = 0.0 + 0.5 = 0.5 -> posB = (15, 0, 0)
        // Blended pos = mix(posA, posB, 0.5) = (7.5, 5.0, 0.0)
        world.update(deltaTime: 0.5)
        let posMid = world.component(ofType: TransformComponent.self, for: nodeEntity)?.position
        #expect(posMid != nil)
        #expect(abs(posMid!.x - 7.5) < 0.01)
        #expect(abs(posMid!.y - 5.0) < 0.01)
        #expect(!transitionCompleted)
        
        // Advance remaining 0.5s -> transition completes!
        // Clip B at t = 1.0 -> posB = (20, 0, 0)
        world.update(deltaTime: 0.5)
        #expect(transitionCompleted)
        
        let posFinal = world.component(ofType: TransformComponent.self, for: nodeEntity)?.position
        #expect(posFinal != nil)
        #expect(abs(posFinal!.x - 20.0) < 0.01)
        
        let finalAnim = world.component(ofType: ModelAnimationComponent.self, for: rootEntity)
        #expect(finalAnim?.currentClipName == "Move")
        #expect(finalAnim?.transition == nil)
    }
    
    @Test("Load animated glTF model and instantiate into ECS world")
    func testLoadAnimatedGLTF() throws {
        #if canImport(Metal)
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        
        let currentDir = FileManager.default.currentDirectoryPath
        let glbPath = (currentDir as NSString).appendingPathComponent("Engine/Tests/AcornEngineTests/Resources/AnimatedTestModel.glb")
        guard FileManager.default.fileExists(atPath: glbPath) else {
            return
        }
        
        let loader = GLTFModelLoader(device: device)
        let url = URL(fileURLWithPath: glbPath)
        let model = try loader.loadModel(from: url)
        
        #expect(model.meshes.count > 0)
        #expect(model.nodes.count == 2)
        #expect(model.animations.count == 2)
        
        let idleClip = model.animations.first { $0.name == "Idle" }
        let walkClip = model.animations.first { $0.name == "Walk" }
        
        #expect(idleClip != nil)
        #expect(walkClip != nil)
        #expect(idleClip!.channels.count == 2)
        #expect(walkClip!.channels.count == 2)
        #expect(abs(idleClip!.duration - 1.0) < 0.001)
        #expect(abs(walkClip!.duration - 1.0) < 0.001)
        
        // Test instantiate into World
        let world = World()
        let animSystem = ModelAnimationSystem()
        world.registerSystem(animSystem)
        
        let rootEntity = model.instantiate(in: world)
        let animComp = world.component(ofType: ModelAnimationComponent.self, for: rootEntity)
        #expect(animComp != nil)
        #expect(animComp!.clips.count == 2)
        #expect(animComp!.nodeEntities.count == 2)
        
        // Arm node is node 1
        let armEntity = animComp!.nodeEntities[1]
        
        // Update world -> Idle animation progresses
        world.update(deltaTime: 0.5)
        let armTransform = world.component(ofType: TransformComponent.self, for: armEntity)
        #expect(armTransform != nil)
        // At t = 0.5 in Idle: translation moves halfway to (0, 1, 0) -> y = 0.5
        #expect(abs(armTransform!.position.y - 0.5) < 0.01)
        // Rotation moves halfway to 90 deg around Z
        #expect(armTransform!.orientation != nil)
        let expectedZ = sin((Float.pi / 4.0) / 2.0)
        #expect(abs(armTransform!.orientation!.z - expectedZ) < 0.01)
        #endif
    }
}
