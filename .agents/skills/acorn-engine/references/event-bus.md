# AcornEngine EventBus Guide

The `EventBus` provides a type-safe, decoupled messaging system supporting two distinct communication patterns:
1. **Immediate Dispatches**: Direct closures executed synchronously at publish time.
2. **Frame-Buffered Queries**: Buffered event arrays queried during system update ticks and automatically cleared at the end of each frame.

---

## 1. Defining Custom Events

All events must conform to `Event & Sendable`.

```swift
import AcornEngine

public struct PlayerDiedEvent: Event, Sendable {
    public let playerEntity: Entity
    public let finalScore: Int
    public let killerEntity: Entity?

    public init(playerEntity: Entity, finalScore: Int, killerEntity: Entity? = nil) {
        self.playerEntity = playerEntity
        self.finalScore = finalScore
        self.killerEntity = killerEntity
    }
}

public struct ScoreChangedEvent: Event, Sendable {
    public let newScore: Int
    public let delta: Int
}
```

---

## 2. Publishing Events

Publish events from anywhere with access to the `World` or `EventBus`:

```swift
world.eventBus.publish(PlayerDiedEvent(playerEntity: player, finalScore: 1420))
```

Publishing an event:
1. Immediately dispatches to all active `subscribe` handlers.
2. Buffers the event in the current frame's event list for `events(ofType:)` queries.

---

## 3. Subscriptions (Immediate Execution)

Use `subscribe` when a system or controller needs to react immediately (e.g., UI sound effects, state transitions).

```swift
// Returns an EventSubscription token
let subscription = world.eventBus.subscribe(PlayerDiedEvent.self) { [weak self] event in
    self?.handleGameOver(score: event.finalScore)
}

// To cancel a subscription:
subscription.cancel()
```

> [!NOTE]
> `EventSubscription` maintains a strong reference to its cancellation token. Store it in a collection or property if you need to cancel it explicitly before world destruction.

---

## 4. Per-Frame Event Queries (Polled by Systems)

Inside `System.update(world:deltaTime:)`, you can query all events of a given type that arrived during the current tick:

```swift
@MainActor
public final class ScoreTrackingSystem: System {
    public func update(world: World, deltaTime: Double) {
        // Query all buffered events
        let scoreEvents = world.eventBus.events(ofType: ScoreChangedEvent.self)
        for event in scoreEvents {
            print("Score increased by \(event.delta)")
        }

        // Or simply check if any occurred
        if world.eventBus.hasEvents(ofType: PlayerDiedEvent.self) {
            // Halt score multipliers
        }
    }
}
```

At the end of each `world.update()`, `world.eventBus.clear()` is called automatically to flush the frame buffers.

---

## 5. Built-in Engine Events Reference

| Event Type | Subsystem | Description |
| :--- | :--- | :--- |
| `EngineTickEvent` | Core | Dispatched at the start of each `world.update()`, carries `deltaTime: Double`. |
| `AppPauseEvent` | Lifecycle | Dispatched when the engine pauses (e.g. app backgrounded). |
| `AppResumeEvent` | Lifecycle | Dispatched when the engine resumes. |
| `SurfaceCreatedEvent` | Graphics | Dispatched when the native render surface becomes available. |
| `SurfaceDestroyedEvent` | Graphics | Dispatched when the native render surface is torn down. |
| `CollisionEnterEvent` | Physics | Fired when two solid physics bodies begin contact. |
| `CollisionStayEvent` | Physics | Fired each frame two solid bodies remain in contact. |
| `CollisionExitEvent` | Physics | Fired when two solid bodies separate. |
| `SensorEnterEvent` | Physics | Fired when an entity enters a trigger volume. |
| `SensorStayEvent` | Physics | Fired each frame an entity remains inside a trigger volume. |
| `SensorExitEvent` | Physics | Fired when an entity leaves a trigger volume. |
| `SpriteAnimationFrameEvent` | Animation | Fired when an animated sprite advances to a new frame. |
| `SpriteAnimationCompletedEvent` | Animation | Fired when a `.once` or `.reverseOnce` clip finishes. |
| `SpriteAnimationTriggerEvent` | Animation | Fired on frames declaring custom string tags (e.g. footsteps). |
| `PlaySoundEvent` | Audio | Requests immediate one-shot playback of an `AudioClip`. |
| `StopAllSoundsEvent` | Audio | Silences all active audio voices. |
| `KeyDownEvent` / `KeyUpEvent` | Input | Dispatched on hardware keyboard key events. |
| `MouseDownEvent` / `MouseUpEvent` | Input | Dispatched on mouse/trackpad pointer clicks. |
| `TouchBeganEvent` / `TouchEndedEvent` | Input | Dispatched on touchscreen contact phases. |
| `GamepadConnectedEvent` / `...` | Input | Dispatched when gamepads connect or buttons are pressed. |
