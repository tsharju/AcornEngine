# AcornEngine Recipes & Code Patterns

This document provides complete, copy-pasteable architectural patterns for common game engine workflows in AcornEngine.

---

## Recipe 1: 2D Animated Platformer Character

Combines:
- `SpriteComponent` & `SpriteAnimationComponent`
- Box2D dynamic body with locked rotation
- Continuous `InputSystem` polling for horizontal run & jump
- Audio playback triggered by animation events

```swift
import AcornEngine
import simd

@MainActor
public struct PlayerCharacterRecipe {
    public static func spawn(
        in world: World,
        spriteSheet: SpriteSheet,
        footstepAudio: AudioClip,
        position: SIMD3<Float> = [0, 5, 0]
    ) -> Entity {
        let player = world.createEntity()

        // 1. Transform & Scale
        world.addComponent(
            TransformComponent(position: position, scale: SIMD3<Float>(repeating: 0.004)),
            to: player
        )

        // 2. Initial Sprite Quad
        world.addComponent(
            SpriteComponent(spriteSheet: spriteSheet, frameName: "hero_idle_00"),
            to: player
        )

        // 3. Animation Clips with Sound Triggers
        let idleFrames = [
            SpriteAnimationFrame(frameName: "hero_idle_00", duration: 0.15),
            SpriteAnimationFrame(frameName: "hero_idle_01", duration: 0.15)
        ]
        let runFrames = [
            SpriteAnimationFrame(frameName: "hero_run_00", duration: 0.08, triggers: ["footstep"]),
            SpriteAnimationFrame(frameName: "hero_run_01", duration: 0.08),
            SpriteAnimationFrame(frameName: "hero_run_02", duration: 0.08, triggers: ["footstep"]),
            SpriteAnimationFrame(frameName: "hero_run_03", duration: 0.08)
        ]

        var anim = SpriteAnimationComponent(clips: [
            "idle": SpriteAnimationClip(name: "idle", frames: idleFrames, defaultPlaybackMode: .loop),
            "run": SpriteAnimationClip(name: "run", frames: runFrames, defaultPlaybackMode: .loop)
        ])
        anim.play(name: "idle")
        world.addComponent(anim, to: player)

        // 4. Box2D Physics Dynamics
        world.addComponent(
            PhysicsBodyComponent(
                type: .dynamicBody,
                linearDamping: 0.1,
                fixedRotation: true // Prevent character from tipping over
            ),
            to: player
        )

        world.addComponent(
            PhysicsColliderComponent(
                shapeType: .box(width: 0.8, height: 1.6),
                friction: 0.2,
                restitution: 0.0,
                density: 1.0,
                enableContactEvents: true
            ),
            to: player
        )

        // 5. Connect Footstep Audio Trigger
        world.eventBus.subscribe(SpriteAnimationTriggerEvent.self) { event in
            guard event.entity == player, event.trigger == "footstep" else { return }
            world.eventBus.publish(PlaySoundEvent(clip: footstepAudio, volume: 0.3))
        }

        return player
    }
}
```

### Accompanying Movement Controller System
```swift
@MainActor
public final class PlayerControllerSystem: System {
    private let playerEntity: Entity
    private let moveSpeed: Float = 6.0
    private let jumpForce: Float = 14.0

    public init(playerEntity: Entity) {
        self.playerEntity = playerEntity
    }

    public func update(world: World, deltaTime: Double) {
        guard let engine = world.firstEntity(with: CameraComponent.self) else { return }
        // Access input state from the engine coordinator or world
        guard var body = world.component(ofType: PhysicsBodyComponent.self, for: playerEntity),
              var anim = world.component(ofType: SpriteAnimationComponent.self, for: playerEntity) else { return }

        // In your controller: evaluate input
        var horizontal: Float = 0.0
        // (Assuming input checked via world.eventBus or continuous InputState)

        body.linearVelocity.x = horizontal * moveSpeed

        if abs(horizontal) > 0.01 {
            if anim.currentClipName != "run" { anim.play(name: "run") }
        } else {
            if anim.currentClipName != "idle" { anim.play(name: "idle") }
        }

        world.addComponent(body, to: playerEntity)
        world.addComponent(anim, to: playerEntity)
    }
}
```

---

## Recipe 2: Complete 3D Scene Setup

Combines camera, directional sunlight, horizon ground plane, and smooth target tracking.

```swift
@MainActor
public struct Scene3DSetup {
    public static func setup(in world: World, renderer: any Renderer, targetEntity: Entity) {
        // 1. Perspective Camera
        let cameraEntity = world.createEntity()
        world.addComponent(TransformComponent(position: [0, 6, -14]), to: cameraEntity)
        world.addComponent(
            CameraComponent(
                projectionType: .perspective,
                fovY: .pi / 3.0,
                nearZ: 0.1,
                farZ: 1000.0,
                aspectRatio: 16.0 / 9.0
            ),
            to: cameraEntity
        )
        // Follow target smoothly
        world.addComponent(
            CameraTrackingComponent(target: targetEntity, offset: [0, 5, -12], smoothing: 0.08),
            to: cameraEntity
        )

        // 2. Sunlight (Directional Light)
        let sun = world.createEntity()
        var sunTransform = TransformComponent()
        sunTransform.rotation = SIMD3<Float>(-.pi / 4.0, -.pi / 3.0, 0.0)
        world.addComponent(sunTransform, to: sun)
        world.addComponent(
            LightComponent(type: .directional, color: [1.0, 0.98, 0.9], intensity: 1.2),
            to: sun
        )

        // 3. Ambient Lighting
        let ambient = world.createEntity()
        world.addComponent(
            LightComponent(type: .ambient, color: [0.25, 0.28, 0.35], intensity: 0.8),
            to: ambient
        )

        // 4. Ground Plane
        let ground = world.createEntity()
        let planeVertices = BasicShapeGenerator.generatePlane(width: 500.0, length: 500.0)
        if let mesh = renderer.createMesh(vertices: planeVertices) {
            world.addComponent(
                MeshComponent(mesh: mesh, color: SIMD4<Float>(0.35, 0.40, 0.32, 1.0)),
                to: ground
            )
            world.addComponent(TransformComponent(position: [0, -0.1, 0]), to: ground)
        }
    }
}
```

---

## Recipe 3: Scene Transitions & Cleanup

When transitioning between menus, levels, or game-over states, query and destroy dynamic gameplay entities:

```swift
public enum GameState: Equatable, Sendable {
    case mainMenu
    case playing(level: Int)
    case gameOver(score: Int)
}

public func clearLevelEntities(in world: World) {
    // Collect all dynamic gameplay entities
    let gameplayEntities = world.entities(with: PhysicsBodyComponent.self).map(\.0)
    for entity in gameplayEntities {
        world.destroyEntity(entity)
    }
}
```
