import Testing
import Foundation
import simd
@testable import AcornEngine

@Suite("Sprite Animation Tests")
@MainActor
struct SpriteAnimationTests {
    
    @Test("SpriteAnimationClip calculation and frame access")
    func testAnimationClipCreation() {
        let frames = [
            SpriteAnimationFrame(frameName: "walk_0", duration: 0.1),
            SpriteAnimationFrame(frameName: "walk_1", duration: 0.2),
            SpriteAnimationFrame(frameName: "walk_2", duration: 0.3)
        ]
        let clip = SpriteAnimationClip(name: "walk", frames: frames, playbackMode: .loop)
        
        #expect(clip.name == "walk")
        #expect(clip.frames.count == 3)
        #expect(abs(clip.totalDuration - 0.6) < 0.0001)
        #expect(clip.frame(at: 0)?.frameName == "walk_0")
        #expect(clip.frame(at: 1)?.frameName == "walk_1")
        #expect(clip.frame(at: 2)?.frameName == "walk_2")
        #expect(clip.frame(at: 3) == nil)
        
        // Convenience FPS initializer
        let fpsClip = SpriteAnimationClip(
            name: "run",
            frameNames: ["run_0", "run_1", "run_2", "run_3"],
            fps: 10.0,
            playbackMode: .pingPong
        )
        #expect(fpsClip.frames.count == 4)
        #expect(fpsClip.frames[0].duration == 0.1)
        #expect(fpsClip.totalDuration == 0.4)
        #expect(fpsClip.playbackMode == .pingPong)
    }
    
    @Test("SpriteAnimationComponent initialization and playback controls")
    func testAnimationComponentControls() {
        let walkClip = SpriteAnimationClip(
            name: "walk",
            frameNames: ["w0", "w1", "w2"],
            fps: 10.0,
            playbackMode: .loop
        )
        let attackClip = SpriteAnimationClip(
            name: "attack",
            frameNames: ["a0", "a1"],
            fps: 10.0,
            playbackMode: .once
        )
        
        var anim = SpriteAnimationComponent(clips: ["walk": walkClip, "attack": attackClip], initialClip: "walk")
        #expect(anim.currentClipName == "walk")
        #expect(anim.currentFrameIndex == 0)
        #expect(anim.isPlaying == true)
        #expect(anim.isPaused == false)
        
        anim.pause()
        #expect(anim.isPaused == true)
        
        anim.resume()
        #expect(anim.isPaused == false)
        
        anim.play(clipNamed: "attack")
        #expect(anim.currentClipName == "attack")
        #expect(anim.currentFrameIndex == 0)
        #expect(anim.activePlaybackMode == .once)
        
        anim.step(by: 1)
        #expect(anim.currentFrameIndex == 1)
        
        anim.step(by: 1)
        #expect(anim.currentFrameIndex == 0) // Wrapped
        
        anim.stop()
        #expect(anim.isPlaying == false)
        #expect(anim.currentFrameIndex == 0)
    }
    
    @Test("SpriteAnimationSystem loops through frames in .loop mode")
    func testLoopPlaybackMode() {
        let world = World()
        let animSystem = SpriteAnimationSystem()
        world.registerSystem(animSystem)
        
        let clip = SpriteAnimationClip(
            name: "run",
            frameNames: ["run_0", "run_1", "run_2"],
            fps: 10.0, // 0.1s per frame
            playbackMode: .loop
        )
        
        let entity = world.createEntity()
        let animComp = SpriteAnimationComponent(clips: ["run": clip], initialClip: "run")
        world.addComponent(animComp, to: entity)
        
        // Frame 0 initially
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 0)
        
        // Advance by 0.05s (still frame 0)
        world.update(deltaTime: 0.05)
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 0)
        
        // Advance another 0.06s (total 0.11s -> should be frame 1)
        world.update(deltaTime: 0.06)
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 1)
        
        // Advance by 0.1s -> frame 2
        world.update(deltaTime: 0.1)
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 2)
        
        // Advance by 0.1s -> wrapped to frame 0
        world.update(deltaTime: 0.1)
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 0)
    }
    
    @Test("SpriteAnimationSystem stops and dispatches completion event in .once mode")
    func testOncePlaybackMode() {
        let world = World()
        let animSystem = SpriteAnimationSystem()
        world.registerSystem(animSystem)
        
        let clip = SpriteAnimationClip(
            name: "die",
            frameNames: ["d0", "d1"],
            fps: 10.0, // 0.1s per frame
            playbackMode: .once
        )
        
        let entity = world.createEntity()
        let animComp = SpriteAnimationComponent(clips: ["die": clip], initialClip: "die")
        world.addComponent(animComp, to: entity)
        
        var completedEvents: [SpriteAnimationCompletedEvent] = []
        let sub = world.eventBus.subscribe(SpriteAnimationCompletedEvent.self) { event in
            completedEvents.append(event)
        }
        _ = sub
        
        // Frame 0 initially
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 0)
        
        // Advance by 0.1s -> frame 1
        world.update(deltaTime: 0.1)
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 1)
        #expect(completedEvents.isEmpty)
        
        // Advance by 0.1s -> completed!
        world.update(deltaTime: 0.1)
        let state = world.component(ofType: SpriteAnimationComponent.self, for: entity)
        #expect(state?.currentFrameIndex == 1) // Remains on final frame
        #expect(state?.isPlaying == false)
        #expect(completedEvents.count == 1)
        #expect(completedEvents.first?.clipName == "die")
        #expect(completedEvents.first?.entity == entity)
    }
    
    @Test("SpriteAnimationSystem bounces correctly in .pingPong mode")
    func testPingPongPlaybackMode() {
        let world = World()
        let animSystem = SpriteAnimationSystem()
        world.registerSystem(animSystem)
        
        let clip = SpriteAnimationClip(
            name: "idle",
            frameNames: ["f0", "f1", "f2"],
            fps: 10.0, // 0.1s per frame
            playbackMode: .pingPong
        )
        
        let entity = world.createEntity()
        let animComp = SpriteAnimationComponent(clips: ["idle": clip], initialClip: "idle")
        world.addComponent(animComp, to: entity)
        
        // Frame 0
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 0)
        
        // Step 1 -> Frame 1
        world.update(deltaTime: 0.1)
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 1)
        
        // Step 2 -> Frame 2 (End of forward sequence)
        world.update(deltaTime: 0.1)
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 2)
        
        // Step 3 -> Bounces back to Frame 1
        world.update(deltaTime: 0.1)
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 1)
        
        // Step 4 -> Frame 0 (Start of sequence)
        world.update(deltaTime: 0.1)
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 0)
        
        // Step 5 -> Bounces back up to Frame 1
        world.update(deltaTime: 0.1)
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 1)
    }
    
    @Test("SpriteAnimationSystem synchronizes frameName to SpriteComponent")
    func testSpriteComponentSync() {
        let world = World()
        let animSystem = SpriteAnimationSystem()
        world.registerSystem(animSystem)
        
        // Create a dummy sprite sheet
        let metadata = SpriteSheetMetadata(
            frames: [
                SpriteFrame(filename: "hero_0", frame: SpriteRect(x: 0, y: 0, w: 16, h: 16), rotated: false, trimmed: false, spriteSourceSize: SpriteRect(x: 0, y: 0, w: 16, h: 16), sourceSize: SpriteSize(w: 16, h: 16)),
                SpriteFrame(filename: "hero_1", frame: SpriteRect(x: 16, y: 0, w: 16, h: 16), rotated: false, trimmed: false, spriteSourceSize: SpriteRect(x: 0, y: 0, w: 16, h: 16), sourceSize: SpriteSize(w: 16, h: 16))
            ],
            meta: SpriteSheetMeta(app: "Test", version: "1.0", image: "test.png", format: "RGBA8888", size: SpriteSize(w: 32, h: 16), scale: "1")
        )
        
        final class DummyTexture: Texture, @unchecked Sendable {
            var width: Int = 32
            var height: Int = 16
        }
        
        let sheet = SpriteSheet(texture: DummyTexture(), metadata: metadata)
        
        let entity = world.createEntity()
        let sprite = SpriteComponent(spriteSheet: sheet, frameName: "hero_0")
        world.addComponent(sprite, to: entity)
        
        let clip = SpriteAnimationClip(
            name: "walk",
            frameNames: ["hero_0", "hero_1"],
            fps: 10.0,
            playbackMode: .loop
        )
        let anim = SpriteAnimationComponent(clips: ["walk": clip], initialClip: "walk")
        world.addComponent(anim, to: entity)
        
        // Advance time to transition from hero_0 to hero_1
        world.update(deltaTime: 0.1)
        
        let updatedSprite = world.component(ofType: SpriteComponent.self, for: entity)
        #expect(updatedSprite?.frameName == "hero_1")
        #expect(updatedSprite?.isDirty == true)
    }
    
    @Test("SpriteAnimationSystem publishes Frame and Trigger events")
    func testAnimationEventBusDispatch() throws {
        let world = World()
        let animSystem = SpriteAnimationSystem()
        world.registerSystem(animSystem)
        
        let frame0 = SpriteAnimationFrame(frameName: "atk_0", duration: 0.1, triggers: [])
        let frame1 = SpriteAnimationFrame(frameName: "atk_1", duration: 0.1, triggers: ["hitbox_active", "slash_sfx"])
        let clip = SpriteAnimationClip(name: "attack", frames: [frame0, frame1], playbackMode: .loop)
        
        let entity = world.createEntity()
        let anim = SpriteAnimationComponent(clips: ["attack": clip], initialClip: "attack")
        world.addComponent(anim, to: entity)
        
        var frameEvents: [SpriteAnimationFrameEvent] = []
        var triggerEvents: [SpriteAnimationTriggerEvent] = []
        
        _ = world.eventBus.subscribe(SpriteAnimationFrameEvent.self) { frameEvents.append($0) }
        _ = world.eventBus.subscribe(SpriteAnimationTriggerEvent.self) { triggerEvents.append($0) }
        
        // Advance by 0.1s to hit frame 1
        world.update(deltaTime: 0.1)
        
        #expect(frameEvents.count == 1)
        let frameEvent = try #require(frameEvents.first)
        #expect(frameEvent.clipName == "attack")
        #expect(frameEvent.frameIndex == 1)
        #expect(frameEvent.frameName == "atk_1")
        
        try #require(triggerEvents.count == 2)
        #expect(triggerEvents[0].payload == "hitbox_active")
        #expect(triggerEvents[1].payload == "slash_sfx")
    }
    
    @Test("SpriteAnimationSystem plays correctly in .reverseOnce mode")
    func testReverseOncePlaybackMode() throws {
        let world = World()
        let animSystem = SpriteAnimationSystem()
        world.registerSystem(animSystem)
        
        let clip = SpriteAnimationClip(
            name: "rewind",
            frameNames: ["f0", "f1", "f2"],
            fps: 10.0, // 0.1s per frame
            playbackMode: .reverseOnce
        )
        
        let entity = world.createEntity()
        let animComp = SpriteAnimationComponent(clips: ["rewind": clip], initialClip: "rewind")
        world.addComponent(animComp, to: entity)
        
        var completedEvents: [SpriteAnimationCompletedEvent] = []
        _ = world.eventBus.subscribe(SpriteAnimationCompletedEvent.self) { completedEvents.append($0) }
        
        // Should start at frame 2 for reverse mode
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 2)
        
        // Advance 0.1s -> frame 1
        world.update(deltaTime: 0.1)
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 1)
        #expect(completedEvents.isEmpty)
        
        // Advance 0.1s -> frame 0
        world.update(deltaTime: 0.1)
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 0)
        #expect(completedEvents.isEmpty)
        
        // Advance 0.1s -> stops on frame 0 and completes
        world.update(deltaTime: 0.1)
        let state = try #require(world.component(ofType: SpriteAnimationComponent.self, for: entity))
        #expect(state.currentFrameIndex == 0)
        #expect(state.isPlaying == false)
        #expect(completedEvents.count == 1)
        #expect(completedEvents.first?.clipName == "rewind")
    }
    
    @Test("SpriteAnimationSystem loops continuously in .reverseLoop mode")
    func testReverseLoopPlaybackMode() {
        let world = World()
        let animSystem = SpriteAnimationSystem()
        world.registerSystem(animSystem)
        
        let clip = SpriteAnimationClip(
            name: "backLoop",
            frameNames: ["f0", "f1", "f2"],
            fps: 10.0,
            playbackMode: .reverseLoop
        )
        
        let entity = world.createEntity()
        let animComp = SpriteAnimationComponent(clips: ["backLoop": clip], initialClip: "backLoop")
        world.addComponent(animComp, to: entity)
        
        // Starts at frame 2
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 2)
        
        // Advance -> frame 1
        world.update(deltaTime: 0.1)
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 1)
        
        // Advance -> frame 0
        world.update(deltaTime: 0.1)
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 0)
        
        // Advance -> wraps back to frame 2
        world.update(deltaTime: 0.1)
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 2)
    }
    
    @Test("SpriteAnimationSystem fires all intermediate triggers during multi-frame catch-up")
    func testMultiFrameTriggerTraversal() throws {
        let world = World()
        let animSystem = SpriteAnimationSystem()
        world.registerSystem(animSystem)
        
        let frame0 = SpriteAnimationFrame(frameName: "f0", duration: 0.1, triggers: ["t0"])
        let frame1 = SpriteAnimationFrame(frameName: "f1", duration: 0.1, triggers: ["t1"])
        let frame2 = SpriteAnimationFrame(frameName: "f2", duration: 0.1, triggers: ["t2"])
        let frame3 = SpriteAnimationFrame(frameName: "f3", duration: 0.1, triggers: ["t3"])
        let clip = SpriteAnimationClip(name: "sequence", frames: [frame0, frame1, frame2, frame3], playbackMode: .loop)
        
        let entity = world.createEntity()
        let anim = SpriteAnimationComponent(clips: ["sequence": clip], initialClip: "sequence")
        world.addComponent(anim, to: entity)
        
        var triggerEvents: [SpriteAnimationTriggerEvent] = []
        _ = world.eventBus.subscribe(SpriteAnimationTriggerEvent.self) { triggerEvents.append($0) }
        
        // Advance by 0.35s (spans frames 1, 2, and lands on frame 3)
        world.update(deltaTime: 0.35)
        
        // Should have fired triggers for frame 1, 2, and 3
        try #require(triggerEvents.count == 3)
        #expect(triggerEvents[0].payload == "t1")
        #expect(triggerEvents[1].payload == "t2")
        #expect(triggerEvents[2].payload == "t3")
    }
    
    @Test("SpriteAnimationSystem handles zero and negative playback speed")
    func testSpeedMultiplier() {
        let world = World()
        let animSystem = SpriteAnimationSystem()
        world.registerSystem(animSystem)
        
        let clip = SpriteAnimationClip(
            name: "test",
            frameNames: ["f0", "f1"],
            fps: 10.0,
            playbackMode: .loop
        )
        
        let entity = world.createEntity()
        var animComp = SpriteAnimationComponent(clips: ["test": clip], initialClip: "test", speed: 0.0)
        world.addComponent(animComp, to: entity)
        
        // With speed = 0, frames do not advance
        world.update(deltaTime: 0.5)
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 0)
        
        // Set negative speed (frozen)
        animComp.speed = -1.0
        world.addComponent(animComp, to: entity)
        world.update(deltaTime: 0.5)
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 0)
        
        // Set double speed (2.0)
        animComp.speed = 2.0
        world.addComponent(animComp, to: entity)
        world.update(deltaTime: 0.05) // 0.05 * 2.0 = 0.1s -> frame 1
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 1)
    }
    
    @Test("SpriteAnimationSystem handles single-frame and zero-duration edge cases without hang")
    func testEdgeCases() {
        let world = World()
        let animSystem = SpriteAnimationSystem()
        world.registerSystem(animSystem)
        
        // Single frame clip
        let singleFrameClip = SpriteAnimationClip(name: "static", frames: [SpriteAnimationFrame(frameName: "s0", duration: 0.0)], playbackMode: .pingPong)
        let entity = world.createEntity()
        let animComp = SpriteAnimationComponent(clips: ["static": singleFrameClip], initialClip: "static")
        world.addComponent(animComp, to: entity)
        
        // Should not hang in while loop despite duration 0.0
        world.update(deltaTime: 1.0)
        #expect(world.component(ofType: SpriteAnimationComponent.self, for: entity)?.currentFrameIndex == 0)
    }
    
    @Test("SpriteAnimationSystem handles large deltaTime spanning multiple frames")
    func testMultiFrameCatchUp() {
        let world = World()
        let animSystem = SpriteAnimationSystem()
        world.registerSystem(animSystem)
        
        let clip = SpriteAnimationClip(
            name: "fast",
            frameNames: ["f0", "f1", "f2", "f3", "f4"],
            fps: 10.0, // 0.1s per frame
            playbackMode: .loop
        )
        
        let entity = world.createEntity()
        let anim = SpriteAnimationComponent(clips: ["fast": clip], initialClip: "fast")
        world.addComponent(anim, to: entity)
        
        // Advance by 0.35s (3.5 frames -> should land on frame 3 with 0.05s timer)
        world.update(deltaTime: 0.35)
        
        let state = world.component(ofType: SpriteAnimationComponent.self, for: entity)
        #expect(state?.currentFrameIndex == 3)
        #expect(abs((state?.playbackTimer ?? 0) - 0.05) < 0.001)
    }
    
    @Test("SpriteSheet automated animation clip generation from naming patterns and tags")
    func testSpriteSheetClipGenerators() throws {
        let metadata = SpriteSheetMetadata(
            frames: [
                SpriteFrame(filename: "knight_walk_0", frame: SpriteRect(x: 0, y: 0, w: 16, h: 16), rotated: false, trimmed: false, spriteSourceSize: SpriteRect(x: 0, y: 0, w: 16, h: 16), sourceSize: SpriteSize(w: 16, h: 16), duration: 100),
                SpriteFrame(filename: "knight_walk_1", frame: SpriteRect(x: 16, y: 0, w: 16, h: 16), rotated: false, trimmed: false, spriteSourceSize: SpriteRect(x: 0, y: 0, w: 16, h: 16), sourceSize: SpriteSize(w: 16, h: 16), duration: 100),
                SpriteFrame(filename: "knight_attack_0", frame: SpriteRect(x: 32, y: 0, w: 16, h: 16), rotated: false, trimmed: false, spriteSourceSize: SpriteRect(x: 0, y: 0, w: 16, h: 16), sourceSize: SpriteSize(w: 16, h: 16), duration: 150)
            ],
            meta: SpriteSheetMeta(
                app: "Test",
                version: "1.0",
                image: "sheet.png",
                format: "RGBA8888",
                size: SpriteSize(w: 64, h: 16),
                scale: "1",
                frameTags: [
                    SpriteSheetFrameTag(name: "walk", from: 0, to: 1, direction: "forward"),
                    SpriteSheetFrameTag(name: "attack", from: 2, to: 2, direction: "forward")
                ]
            )
        )
        
        final class DummyTexture: Texture, @unchecked Sendable {
            var width: Int = 64
            var height: Int = 16
        }
        
        let sheet = SpriteSheet(texture: DummyTexture(), metadata: metadata)
        
        // Pattern-based clips
        let patternClips = sheet.makeAnimationClips(fps: 10.0)
        let walkClip = try #require(patternClips["knight_walk"])
        #expect(walkClip.frames.count == 2)
        let attackClip = try #require(patternClips["knight_attack"])
        #expect(attackClip.frames.count == 1)
        
        // Tag-based clips
        let tagClips = sheet.makeAnimationClipsFromTags()
        let tagWalk = try #require(tagClips["walk"])
        #expect(tagWalk.frames.count == 2)
        let tagAttack = try #require(tagClips["attack"])
        #expect(tagAttack.frames.count == 1)
    }
}
