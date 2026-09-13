import Foundation
import AcornMath

/// An ECS system that updates 3D model animation timers, evaluates keyframed node channels,
/// computes crossfades and transitions, synchronizes `TransformComponent` across the entity hierarchy,
/// and publishes animation events via `EventBus`.
@MainActor
public struct ModelAnimationSystem: System {
    
    /// Initializes a new `ModelAnimationSystem`.
    public init() {}
    
    /// Updates all entities with a `ModelAnimationComponent` in the world.
    /// - Parameters:
    ///   - world: The ECS world.
    ///   - deltaTime: The elapsed time in seconds since the last frame.
    public func update(world: World, deltaTime: Double) {
        world.mutateEach(ModelAnimationComponent.self) { entity, anim in
            guard anim.isPlaying, !anim.isPaused, anim.speed > 0 else {
                return
            }
            
            if let trans = anim.transition {
                updateTransition(world: world, entity: entity, anim: &anim, trans: trans, deltaTime: deltaTime)
            } else {
                updatePlayback(world: world, entity: entity, anim: &anim, deltaTime: deltaTime)
            }
        }
    }
    
    // MARK: - Normal Playback
    
    private func updatePlayback(
        world: World,
        entity: Entity,
        anim: inout ModelAnimationComponent,
        deltaTime: Double
    ) {
        guard let clip = anim.currentClip, clip.duration > 0 else {
            return
        }
        
        let mode = anim.activePlaybackMode
        anim.playbackTimer += deltaTime * anim.speed * Double(anim.pingPongDirection)
        
        switch mode {
        case .loop:
            if anim.playbackTimer > clip.duration {
                anim.playbackTimer = anim.playbackTimer.truncatingRemainder(dividingBy: clip.duration)
                world.eventBus.publish(ModelAnimationLoopedEvent(entity: entity, clipName: clip.name))
            } else if anim.playbackTimer < 0 {
                anim.playbackTimer = clip.duration + anim.playbackTimer.truncatingRemainder(dividingBy: clip.duration)
                world.eventBus.publish(ModelAnimationLoopedEvent(entity: entity, clipName: clip.name))
            }
            
        case .once:
            if anim.playbackTimer >= clip.duration {
                anim.playbackTimer = clip.duration
                anim.isPlaying = false
                world.eventBus.publish(ModelAnimationCompletedEvent(entity: entity, clipName: clip.name))
            }
            
        case .pingPong:
            if anim.playbackTimer >= clip.duration {
                anim.pingPongDirection = -1
                anim.playbackTimer = max(0.0, clip.duration - (anim.playbackTimer - clip.duration))
            } else if anim.playbackTimer <= 0 {
                anim.pingPongDirection = 1
                anim.playbackTimer = max(0.0, -anim.playbackTimer)
            }
            
        case .reverseOnce:
            if anim.playbackTimer <= 0 {
                anim.playbackTimer = 0.0
                anim.isPlaying = false
                world.eventBus.publish(ModelAnimationCompletedEvent(entity: entity, clipName: clip.name))
            }
            
        case .reverseLoop:
            if anim.playbackTimer < 0 {
                anim.playbackTimer = clip.duration + anim.playbackTimer.truncatingRemainder(dividingBy: clip.duration)
                world.eventBus.publish(ModelAnimationLoopedEvent(entity: entity, clipName: clip.name))
            }
        }
        
        applyPose(world: world, anim: anim, clip: clip, time: Float(anim.playbackTimer))
    }
    
    // MARK: - Transition / Crossfade
    
    private func updateTransition(
        world: World,
        entity: Entity,
        anim: inout ModelAnimationComponent,
        trans: ModelAnimationTransition,
        deltaTime: Double
    ) {
        guard let fromClip = anim.clips[trans.fromClipName],
              let toClip = anim.clips[trans.toClipName] else {
            anim.transition = nil
            return
        }
        
        var currentTrans = trans
        currentTrans.elapsed += deltaTime * anim.speed
        currentTrans.fromTimer += deltaTime * anim.speed
        currentTrans.toTimer += deltaTime * anim.speed * Double(anim.pingPongDirection)
        
        if fromClip.duration > 0 && fromClip.playbackMode == .loop && currentTrans.fromTimer > fromClip.duration {
            currentTrans.fromTimer = currentTrans.fromTimer.truncatingRemainder(dividingBy: fromClip.duration)
        }
        
        let toMode = anim.activePlaybackMode
        if toClip.duration > 0 && toMode == .loop && currentTrans.toTimer > toClip.duration {
            currentTrans.toTimer = currentTrans.toTimer.truncatingRemainder(dividingBy: toClip.duration)
        }
        
        anim.playbackTimer = currentTrans.toTimer
        let alpha = Float(currentTrans.progress)
        
        applyBlendedPose(
            world: world,
            anim: anim,
            fromClip: fromClip,
            fromTime: Float(currentTrans.fromTimer),
            toClip: toClip,
            toTime: Float(currentTrans.toTimer),
            alpha: alpha
        )
        
        if currentTrans.progress >= 1.0 {
            anim.transition = nil
            world.eventBus.publish(ModelAnimationTransitionCompletedEvent(entity: entity, clipName: toClip.name))
        } else {
            anim.transition = currentTrans
        }
    }
    
    // MARK: - Pose Evaluation & Application
    
    private struct NodeEvaluatedPose {
        var pos: SIMD3<Float>?
        var rot: SIMD4<Float>?
        var scale: SIMD3<Float>?
    }
    
    private func evaluateClipPose(clip: ModelAnimationClip, time: Float) -> [Int: NodeEvaluatedPose] {
        var result: [Int: NodeEvaluatedPose] = [:]
        for channel in clip.channels {
            let idx = channel.targetNodeIndex
            switch channel.path {
            case .translation:
                if let val = channel.evaluateVec3(at: time) {
                    result[idx, default: NodeEvaluatedPose()].pos = val
                }
            case .rotation:
                if let val = channel.evaluateVec4(at: time) {
                    result[idx, default: NodeEvaluatedPose()].rot = val
                }
            case .scale:
                if let val = channel.evaluateVec3(at: time) {
                    result[idx, default: NodeEvaluatedPose()].scale = val
                }
            case .weights:
                break
            }
        }
        return result
    }
    
    private func applyPose(
        world: World,
        anim: ModelAnimationComponent,
        clip: ModelAnimationClip,
        time: Float
    ) {
        let poseMap = evaluateClipPose(clip: clip, time: time)
        
        for (i, nodeEntity) in anim.nodeEntities.enumerated() {
            let rest = i < anim.nodeRestTransforms.count ? anim.nodeRestTransforms[i] : NodeRestTransform()
            let evaluated = poseMap[i]
            
            let pos = evaluated?.pos ?? rest.translation
            let rot = evaluated?.rot ?? rest.rotation
            let scl = evaluated?.scale ?? rest.scale
            
            world.mutateComponent(ofType: TransformComponent.self, for: nodeEntity) { transform in
                transform.position = pos
                transform.orientation = rot
                transform.rotation = quaternionToEuler(rot)
                transform.scale = scl
            }
        }
    }
    
    private func applyBlendedPose(
        world: World,
        anim: ModelAnimationComponent,
        fromClip: ModelAnimationClip,
        fromTime: Float,
        toClip: ModelAnimationClip,
        toTime: Float,
        alpha: Float
    ) {
        let fromMap = evaluateClipPose(clip: fromClip, time: fromTime)
        let toMap = evaluateClipPose(clip: toClip, time: toTime)
        
        for (i, nodeEntity) in anim.nodeEntities.enumerated() {
            let rest = i < anim.nodeRestTransforms.count ? anim.nodeRestTransforms[i] : NodeRestTransform()
            
            let posA = fromMap[i]?.pos ?? rest.translation
            let rotA = fromMap[i]?.rot ?? rest.rotation
            let sclA = fromMap[i]?.scale ?? rest.scale
            
            let posB = toMap[i]?.pos ?? rest.translation
            let rotB = toMap[i]?.rot ?? rest.rotation
            let sclB = toMap[i]?.scale ?? rest.scale
            
            let blendedPos = mix(posA, posB, t: alpha)
            let blendedRot = slerp(rotA, rotB, t: alpha)
            let blendedScale = mix(sclA, sclB, t: alpha)
            
            world.mutateComponent(ofType: TransformComponent.self, for: nodeEntity) { transform in
                transform.position = blendedPos
                transform.orientation = blendedRot
                transform.rotation = quaternionToEuler(blendedRot)
                transform.scale = blendedScale
            }
        }
    }
}
