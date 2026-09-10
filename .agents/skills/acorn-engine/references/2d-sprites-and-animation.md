# AcornEngine 2D Sprites & Animation Guide

AcornEngine provides a hardware-accelerated 2D sprite rendering pipeline backed by GPU instancing and an Entity Component System (ECS) flipbook animation engine.

---

## 1. Loading Sprite Sheets

Sprite sheets package multiple frames into a single texture atlas with accompanying JSON metadata (TexturePacker array or hash format).

```swift
import AcornEngine

// Load texture and metadata
guard let textureURL = Bundle.main.url(forResource: "characters", withExtension: "png"),
      let jsonURL = Bundle.main.url(forResource: "characters", withExtension: "json") else {
    fatalError("Missing sprite assets")
}

let texture = try TextureLoader.load(from: textureURL, device: renderer.device)
let jsonData = try Data(contentsOf: jsonURL)
let spriteSheet = try SpriteSheet(texture: texture, jsonData: jsonData)
```

> [!TIP]
> Use the [spright-spritesheet-skill](file://.agents/skills/spright-spritesheet-skill/SKILL.md) to automatically pack sprites using `spright` and custom Inja templates matching AcornEngine's decoder.

---

## 2. Static Sprites (`SpriteComponent`)

To render a 2D sprite, attach a `TransformComponent` and a `SpriteComponent`:

```swift
let coin = world.createEntity()

// World placement
world.addComponent(
    TransformComponent(
        position: SIMD3<Float>(5.0, 2.0, 0.0),
        scale: SIMD3<Float>(repeating: 0.005) // Scale quad to world units
    ),
    to: coin
)

// Sprite quad configuration
world.addComponent(
    SpriteComponent(
        spriteSheet: spriteSheet,
        frameName: "coin_gold",
        color: SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
    ),
    to: coin
)
```

### Automatic Z-Sorting & Batching
`RenderSystem` sorts all visible `SpriteComponent` entities by ascending $Z$ position (`TransformComponent.position.z`) to ensure back-to-front alpha blending. Contiguous sprites sharing the same texture are automatically batched into single instanced draw calls (`renderSpritesInstanced`).

---

## 3. 2D Flipbook Animation

Flipbook animation is managed via `SpriteAnimationComponent` and driven by `SpriteAnimationSystem`.

### 1. Automated Clip Generation
AcornEngine can automatically extract animation clips directly from your sprite sheet:

#### Method A: By Naming Convention (`makeAnimationClips`)
Groups frames by prefix separated by numbers (e.g. `hero_run_01`, `hero_run_02` becomes clip `"hero_run"`):
```swift
let clips = spriteSheet.makeAnimationClips(
    frameDuration: 0.1,
    defaultPlaybackMode: .loop
)
```

#### Method B: From Aseprite JSON Tags (`makeAnimationClipsFromTags`)
Imports frame tags exported from Aseprite (e.g., `"idle"`, `"walk"`, `"attack"`):
```swift
let clips = spriteSheet.makeAnimationClipsFromTags(
    defaultFrameDuration: 0.08,
    defaultPlaybackMode: .loop
)
```

### 2. Manual Clip Creation
Define frames with custom durations and trigger tags:
```swift
let runFrames = [
    SpriteAnimationFrame(frameName: "hero_run_00", duration: 0.08, triggers: ["step_l"]),
    SpriteAnimationFrame(frameName: "hero_run_01", duration: 0.08),
    SpriteAnimationFrame(frameName: "hero_run_02", duration: 0.08, triggers: ["step_r"]),
    SpriteAnimationFrame(frameName: "hero_run_03", duration: 0.08)
]

let runClip = SpriteAnimationClip(
    name: "run",
    frames: runFrames,
    defaultPlaybackMode: .loop
)
```

### 3. Playback Modes
| Mode | Description |
| :--- | :--- |
| `.once` | Plays forward to the last frame and stops. Fires `SpriteAnimationCompletedEvent`. |
| `.loop` | Plays forward continuously, wrapping from end to start. |
| `.pingPong` | Plays forward to end, reverses back to start, and repeats continuously. |
| `.reverseOnce` | Plays backward to first frame and stops. Fires `SpriteAnimationCompletedEvent`. |
| `.reverseLoop` | Plays backward continuously, wrapping from start to end. |

### 4. Attaching & Controlling Animation
```swift
var anim = SpriteAnimationComponent(clips: ["run": runClip])
anim.play(name: "run", playbackMode: .loop, speed: 1.0)
world.addComponent(anim, to: playerEntity)

// Control at runtime:
world.mutateComponent(ofType: SpriteAnimationComponent.self, for: playerEntity) { anim in
    anim.play(name: "jump", playbackMode: .once)
    // Other controls: anim.pause(), anim.resume(), anim.stop()
}
```

---

## 4. Animation Events

React to animation state changes via the `EventBus`:

### Footsteps / Hitboxes (`SpriteAnimationTriggerEvent`)
```swift
world.eventBus.subscribe(SpriteAnimationTriggerEvent.self) { event in
    guard event.entity == playerEntity else { return }
    if event.trigger == "step_l" || event.trigger == "step_r" {
        world.eventBus.publish(PlaySoundEvent(clip: footstepSound, volume: 0.4))
    }
}
```

### Action Completion (`SpriteAnimationCompletedEvent`)
```swift
world.eventBus.subscribe(SpriteAnimationCompletedEvent.self) { event in
    guard event.entity == playerEntity else { return }
    if event.clipName == "attack" {
        // Return to idle animation
        world.mutateComponent(ofType: SpriteAnimationComponent.self, for: playerEntity) { anim in
            anim.play(name: "idle")
        }
    }
}
```

---

## 5. Tilemaps (`TileMapComponent`)

`TileMapComponent` renders large 2D tile grids efficiently by generating a single batched vertex mesh:

```swift
let tilemapEntity = world.createEntity()
world.addComponent(TransformComponent(position: .zero), to: tilemapEntity)

var tileMap = TileMapComponent(
    spriteSheet: environmentSheet,
    columns: 20,
    rows: 15,
    tileSize: SIMD2<Float>(1.0, 1.0)
)

// Fill ground row
for col in 0..<20 {
    tileMap.setTile(column: col, row: 0, frameName: "grass_top")
}

world.addComponent(tileMap, to: tilemapEntity)
```
