# AcornEngine 2D Physics & Collisions Guide

AcornEngine natively integrates **Box2D v3** to drive fast, accurate 2D rigid-body dynamics, contact manifold generation, and sensor trigger volumes synchronized directly with ECS transforms.

---

## 1. Enabling the Physics System

Register `PhysicsSystem` with the `World`:

```swift
import AcornEngine

let physicsSystem = PhysicsSystem()
engine.world.registerSystem(physicsSystem)
```

`PhysicsSystem` advances Box2D using fixed timesteps ($1/60$s) and automatically synchronizes simulated 2D positions and rotations back into `TransformComponent`.

---

## 2. Rigid Bodies (`PhysicsBodyComponent`)

Assign physical dynamics properties to an entity:

```swift
let ball = world.createEntity()
world.addComponent(TransformComponent(position: [0.0, 10.0, 0.0]), to: ball)

world.addComponent(
    PhysicsBodyComponent(
        type: .dynamicBody,           // .dynamicBody, .staticBody, or .kinematicBody
        isAwake: true,
        linearVelocity: SIMD2<Float>(0.0, 0.0),
        angularVelocity: 0.0,
        linearDamping: 0.1,           // Air resistance
        angularDamping: 0.05,
        gravityScale: 1.0,            // Multiplier for world gravity
        isBullet: false,              // High-speed CCD (Continuous Collision Detection)
        fixedRotation: false          // Lock rotation if true
    ),
    to: ball
)
```

---

## 3. Physical Colliders (`PhysicsColliderComponent`)

Define geometry and physical material characteristics:

```swift
world.addComponent(
    PhysicsColliderComponent(
        shapeType: .circle(radius: 0.5), // or .box(width: 1.0, height: 1.0)
        friction: 0.3,
        restitution: 0.75,              // Bounciness (0 = no bounce, 1 = elastic)
        density: 1.0,
        isSensor: false,
        enableContactEvents: true       // Enable CollisionEnter/Stay/Exit events
    ),
    to: ball
)
```

### Static Ground Example
```swift
let ground = world.createEntity()
world.addComponent(TransformComponent(position: [0.0, 0.0, 0.0]), to: ground)
world.addComponent(PhysicsBodyComponent(type: .staticBody), to: ground)
world.addComponent(
    PhysicsColliderComponent(
        shapeType: .box(width: 20.0, height: 1.0),
        friction: 0.5,
        restitution: 0.0
    ),
    to: ground
)
```

---

## 4. Collision & Contact Events

When two physical colliders make or break contact, `PhysicsSystem` publishes contact events to the `EventBus`:

### Event Types
- **`CollisionEnterEvent`**: Fired on initial contact frame.
- **`CollisionStayEvent`**: Fired each frame contact persists.
- **`CollisionExitEvent`**: Fired when separation occurs.

Each event carries:
- `entityA: Entity`, `entityB: Entity`
- `contactPoint: CollisionContactPoint` containing:
  - `point: SIMD2<Float>` (World contact position)
  - `normal: SIMD2<Float>` (Surface normal)
  - `approachSpeed: Float` (Relative impact speed)

### Contact Listener Example
```swift
world.eventBus.subscribe(CollisionEnterEvent.self) { event in
    // Check if the player collided with an enemy
    if (event.entityA == playerEntity && event.entityB == enemyEntity) ||
       (event.entityB == playerEntity && event.entityA == enemyEntity) {
        
        if event.contactPoint.approachSpeed > 5.0 {
            // High-impact collision
            world.eventBus.publish(PlaySoundEvent(clip: impactSound, volume: 1.0))
        }
    }
}
```

---

## 5. Non-Solid Sensor Trigger Volumes

Sensor triggers detect overlaps without exerting physical reaction forces (ideal for coin pickups, checkpoints, and hazard zones):

### Setup
```swift
let coin = world.createEntity()
world.addComponent(TransformComponent(position: [3.0, 1.0, 0.0]), to: coin)
world.addComponent(PhysicsBodyComponent(type: .staticBody), to: coin)
world.addComponent(
    SensorTriggerComponent(shapeType: .circle(radius: 0.75)),
    to: coin
)
```

### Handling Sensor Overlaps
```swift
world.eventBus.subscribe(SensorEnterEvent.self) { event in
    if event.sensorEntity == coin && event.visitorEntity == playerEntity {
        print("Coin collected!")
        world.destroyEntity(coin)
        world.eventBus.publish(PlaySoundEvent(clip: coinPickupClip))
    }
}
```

### Direct Overlap Querying
You can query active overlaps anytime without events:
```swift
if let sensor = world.component(ofType: SensorTriggerComponent.self, for: checkpointEntity) {
    if sensor.isOverlapping(playerEntity) {
        // Player is currently inside checkpoint
    }
}
```
