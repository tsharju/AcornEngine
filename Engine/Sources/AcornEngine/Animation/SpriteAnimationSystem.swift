import Foundation

/// An ECS system that updates sprite animation timers, advances animation frames,
/// synchronizes active frames with `SpriteComponent`, and publishes animation events via `EventBus`.
@MainActor
public struct SpriteAnimationSystem: System {
    
    /// Initializes a new `SpriteAnimationSystem`.
    public init() {}
    
    /// Updates all entities with a `SpriteAnimationComponent` in the world.
    /// - Parameters:
    ///   - world: The ECS world.
    ///   - deltaTime: The elapsed time in seconds since the last frame.
    public func update(world: World, deltaTime: Double) {
        world.forEach(SpriteAnimationComponent.self) { entity, animComponent in
            var anim = animComponent
            
            guard anim.isPlaying, !anim.isPaused, anim.speed > 0 else {
                // Keep sprite in sync even if not playing
                if let clip = anim.currentClip, !clip.frames.isEmpty {
                    let clampedIndex = max(0, min(anim.currentFrameIndex, clip.frames.count - 1))
                    let activeFrame = clip.frames[clampedIndex]
                    world.mutateComponent(ofType: SpriteComponent.self, for: entity) { sprite in
                        if sprite.frameName != activeFrame.frameName {
                            sprite.frameName = activeFrame.frameName
                            sprite.isDirty = true
                        }
                    }
                }
                return
            }
            
            guard let clip = anim.currentClip, !clip.frames.isEmpty else {
                return
            }
            
            let frameCount = clip.frames.count
            anim.currentFrameIndex = max(0, min(anim.currentFrameIndex, frameCount - 1))
            
            // Advance timer
            anim.playbackTimer += deltaTime * anim.speed
            let mode = anim.activePlaybackMode
            
            // Step frames while timer exceeds current frame duration
            while anim.isPlaying && anim.playbackTimer >= max(0.0001, clip.frames[anim.currentFrameIndex].duration) {
                let frameDuration = max(0.0001, clip.frames[anim.currentFrameIndex].duration)
                anim.playbackTimer -= frameDuration
                
                var advanced = false
                switch mode {
                case .once:
                    if anim.currentFrameIndex + 1 < frameCount {
                        anim.currentFrameIndex += 1
                        advanced = true
                    } else {
                        anim.isPlaying = false
                        anim.playbackTimer = 0.0
                        world.eventBus.publish(SpriteAnimationCompletedEvent(entity: entity, clipName: clip.name))
                    }
                    
                case .loop:
                    anim.currentFrameIndex = (anim.currentFrameIndex + 1) % frameCount
                    advanced = true
                    
                case .pingPong:
                    if frameCount <= 1 {
                        anim.currentFrameIndex = 0
                    } else {
                        let nextIndex = anim.currentFrameIndex + anim.pingPongDirection
                        if nextIndex >= frameCount {
                            anim.pingPongDirection = -1
                            anim.currentFrameIndex = max(0, frameCount - 2)
                            advanced = true
                        } else if nextIndex < 0 {
                            anim.pingPongDirection = 1
                            anim.currentFrameIndex = min(frameCount - 1, 1)
                            advanced = true
                        } else {
                            anim.currentFrameIndex = nextIndex
                            advanced = true
                        }
                    }
                    
                case .reverseOnce:
                    if anim.currentFrameIndex > 0 {
                        anim.currentFrameIndex -= 1
                        advanced = true
                    } else {
                        anim.isPlaying = false
                        anim.playbackTimer = 0.0
                        world.eventBus.publish(SpriteAnimationCompletedEvent(entity: entity, clipName: clip.name))
                    }
                    
                case .reverseLoop:
                    anim.currentFrameIndex = (anim.currentFrameIndex - 1 + frameCount) % frameCount
                    advanced = true
                }
                
                if advanced {
                    let frame = clip.frames[anim.currentFrameIndex]
                    world.eventBus.publish(SpriteAnimationFrameEvent(
                        entity: entity,
                        clipName: clip.name,
                        frameIndex: anim.currentFrameIndex,
                        frameName: frame.frameName
                    ))
                    
                    for trigger in frame.triggers {
                        world.eventBus.publish(SpriteAnimationTriggerEvent(
                            entity: entity,
                            clipName: clip.name,
                            frameIndex: anim.currentFrameIndex,
                            payload: trigger
                        ))
                    }
                }
            }
            
            let updatedFrame = clip.frames[anim.currentFrameIndex]
            
            // Synchronize active frame with SpriteComponent
            world.mutateComponent(ofType: SpriteComponent.self, for: entity) { sprite in
                if sprite.frameName != updatedFrame.frameName {
                    sprite.frameName = updatedFrame.frameName
                    sprite.isDirty = true
                }
            }
            
            world.addComponent(anim, to: entity)
        }
    }
}
