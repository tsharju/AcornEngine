# AcornEngine Spatial Audio Guide

AcornEngine features a native 3D spatial audio subsystem powered by Apple's `AVAudioEngine` and `AVAudioEnvironmentNode`.

---

## 1. Architecture Overview

- **`AudioSystem`**: Automatically registered by `Engine`. Syncs entity 3D transforms to audio positions and manages dynamic `AVAudioPlayerNode` voice pools.
- **`AudioClip`**: Represents loaded uncompressed or compressed audio PCM buffers (`.wav`, `.mp3`, `.m4a`, `.caf`).
- **`AudioListenerComponent`**: Defines the "ears" in the virtual world (usually attached to the active camera).
- **`AudioSourceComponent`**: Emits sound attached to an entity in 2D (direct) or 3D (spatial).
- **`PlaySoundEvent`**: Dispatches one-shot sound effects without creating entity components.

---

## 2. Loading Audio Clips

```swift
import AcornEngine

guard let url = Bundle.main.url(forResource: "laser", withExtension: "wav") else {
    fatalError("Missing audio file")
}

let laserClip = try AudioClip(contentsOf: url)
```

---

## 3. Spatial Listener (`AudioListenerComponent`)

Attach an `AudioListenerComponent` to your camera entity:

```swift
let cameraEntity = world.createEntity()
world.addComponent(TransformComponent(position: [0, 2, -5]), to: cameraEntity)
world.addComponent(
    AudioListenerComponent(
        isPrimary: true,
        masterVolume: 1.0
    ),
    to: cameraEntity
)
```

`AudioSystem` continuously synchronizes the listener's 3D position and orientation (Pitch, Yaw, Roll) with the underlying `AVAudioEnvironmentNode`.

---

## 4. Continuous Audio Emitter (`AudioSourceComponent`)

For continuous sound sources attached to game entities (e.g. engine hums, campfires, water streams):

```swift
let campfire = world.createEntity()
world.addComponent(TransformComponent(position: [10, 0, 5]), to: campfire)

var audioSource = AudioSourceComponent(
    clip: campfireClip,
    volume: 0.8,
    pitch: 1.0,
    isLooping: true,
    isSpatial: true,                  // 3D positioning
    playOnAwake: true,                // Start playing immediately
    reverbBlend: 0.2,
    renderingAlgorithm: .hrtf         // High-fidelity binaural HRTF
)

world.addComponent(audioSource, to: campfire)
```

### Spatial Algorithms (`renderingAlgorithm`)
- `.hrtf`: Binaural rendering using Head-Related Transfer Functions (highest realism with headphones).
- `.sphericalHead`: 3D spatialization using head-shadow simulation.
- `.equalPowerPanning`: High-performance 2D/3D stereo pan.
- `.soundField`: Multi-channel sound field rendering.

### Runtime Controls
```swift
world.mutateComponent(ofType: AudioSourceComponent.self, for: campfire) { source in
    source.pause()
    // Or source.resume(), source.stop(), source.play()
}
```

---

## 5. One-Shot Audio Events (`PlaySoundEvent`)

For transient effects that do not need dedicated entity tracking (e.g., UI clicks, weapon shots, explosions):

```swift
// 2D non-spatial one-shot (e.g., UI click)
world.eventBus.publish(
    PlaySoundEvent(clip: clickClip, volume: 0.5)
)

// 3D spatial one-shot (e.g., grenade explosion at coordinate)
world.eventBus.publish(
    PlaySoundEvent(
        clip: explosionClip,
        volume: 1.0,
        pitch: 0.95,
        position: SIMD3<Float>(15.0, 0.0, 20.0)
    )
)

// Silence all active sound effects (e.g. on game over)
world.eventBus.publish(StopAllSoundsEvent())
```
