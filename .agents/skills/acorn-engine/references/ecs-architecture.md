# AcornEngine ECS Architecture Guide

AcornEngine implements a data-oriented **Entity Component System (ECS)** designed for Swift 6 with strict concurrency safety.

---

## 1. Core Principles

- **`Entity`**: A lightweight, unique, generational 64-bit ID (`UInt32` index + `UInt32` generation). Reuses destroyed slots without stale references.
- **`Component`**: A pure data `struct` conforming to `Component & Sendable`. **Components must never contain game logic or methods that mutate external state.**
- **`System`**: A logic class conforming to `System` and isolated to `@MainActor`. Runs every tick via `update(world:deltaTime:)`.
- **`World`**: The central registry managing entity lifecycles, typed component pools, and system executions.

---

## 2. Defining Components

Components should be lightweight value types (`struct`).

```swift
import AcornEngine
import simd

public struct VelocityComponent: Component, Sendable {
    public var velocity: SIMD2<Float>
    public var maxSpeed: Float

    public init(velocity: SIMD2<Float> = .zero, maxSpeed: Float = 10.0) {
        self.velocity = velocity
        self.maxSpeed = maxSpeed
    }
}

public struct HealthComponent: Component, Sendable {
    public var currentHealth: Int
    public var maxHealth: Int
    public var isInvulnerable: Bool

    public init(maxHealth: Int = 100) {
        self.currentHealth = maxHealth
        self.maxHealth = maxHealth
        self.isInvulnerable = false
    }
}
```

### Editor Inspector Registration (Debug Only)
To make your custom components visible and editable in the Acorn Editor inspector:

```swift
#if DEBUG
ComponentRegistry.register(name: "Health", type: HealthComponent.self) {
    HealthComponent(maxHealth: 100)
}
#endif
```

---

## 3. Defining Systems

Systems encapsulate all game logic. Systems are executed in the exact order they are registered in the `World`.

```swift
import AcornEngine
import simd

@MainActor
public final class MovementSystem: System {
    public init() {}

    public func update(world: World, deltaTime: Double) {
        let dt = Float(deltaTime)

        // Efficient zero-allocation dual-component iteration
        world.forEach(TransformComponent.self, VelocityComponent.self) { entity, transform, velocity in
            var updatedTransform = transform
            updatedTransform.position.x += velocity.velocity.x * dt
            updatedTransform.position.y += velocity.velocity.y * dt
            world.addComponent(updatedTransform, to: entity)
        }
    }
}
```

---

## 4. Entity Lifecycle & Manipulation

### Creating and Naming Entities
```swift
let player = world.createEntity()

#if DEBUG
world.setName("Player", for: player)
#endif
```

### Adding and Removing Components
```swift
// Add
world.addComponent(TransformComponent(position: [0, 0, 0]), to: player)
world.addComponent(HealthComponent(maxHealth: 100), to: player)

// Check / Query
if let health = world.component(ofType: HealthComponent.self, for: player) {
    print("Player health: \(health.currentHealth)")
}

// Remove
world.removeComponent(ofType: HealthComponent.self, from: player)
```

### Destroying Entities
Destroying an entity automatically cleans up all attached components, releases associated Box2D physics bodies, and tears down audio nodes:
```swift
world.destroyEntity(player)
```

---

## 5. Performance: Zero-Allocation Queries & Mutations

Avoid creating transient arrays (`world.entities(with:)`) inside hot per-frame update loops. Instead, use AcornEngine's optimized zero-allocation iteration and in-place mutation APIs:

### 1. In-place Component Mutation (`mutateComponent`)
Directly mutates the component in the storage pool without copying out and re-adding:
```swift
world.mutateComponent(ofType: HealthComponent.self, for: entity) { health in
    health.currentHealth -= damage
}
```

### 2. Mutating All Components of a Type (`mutateEach`)
```swift
world.mutateEach(VelocityComponent.self) { entity, velocity in
    velocity.velocity *= 0.98 // Apply friction/drag
}
```

### 3. Iterating Single Component (`forEach`)
```swift
world.forEach(SpriteComponent.self) { entity, sprite in
    // Read-only inspection
}
```

### 4. Iterating Pairs of Components (`forEach(T1, T2)`)
Optimized internally to loop over the smaller pool and perform $O(1)$ lookups into the second:
```swift
world.forEach(TransformComponent.self, PhysicsBodyComponent.self) { entity, transform, body in
    // Process transform and body
}
```

### 5. Finding First Matching Entity (`firstEntity`)
Useful for singletons like primary cameras or active players:
```swift
if let (cameraEntity, camera) = world.firstEntity(with: CameraComponent.self) {
    // Found active camera
}
```

---

## 6. Hierarchical Parent-Child Transforms

Entities can be organized hierarchically using `ParentComponent`. The engine automatically resolves composite matrices and world coordinates:

```swift
let vehicle = world.createEntity()
world.addComponent(TransformComponent(position: [10, 0, 0]), to: vehicle)

let turret = world.createEntity()
world.addComponent(TransformComponent(position: [0, 2, 0]), to: turret)
// Attach turret to vehicle
world.addComponent(ParentComponent(parent: vehicle), to: turret)

// Resolving world coordinates
let turretWorldPos = world.worldPosition(for: turret) // [10, 2, 0]
let turretWorldMat = world.worldMatrix(for: turret)
```

> [!TIP]
> `world.worldMatrix(for:)` has a built-in cycle-detection guard (max recursion depth: 64) preventing infinite loops if a circular hierarchy is inadvertently formed.
