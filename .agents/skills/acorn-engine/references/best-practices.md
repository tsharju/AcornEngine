# AcornEngine Best Practices & Performance Guidelines

Follow these core engineering guidelines to maintain high frame rates, avoid concurrency hazards, and maximize GPU instancing throughput in AcornEngine.

---

## 1. Concurrency & Swift 6 Safety

### `@MainActor` Isolation
All ECS state (`World`, `System`, `EventBus`, `Engine`, `Renderer`) is isolated to `@MainActor`:
- Do not access `world.component(...)` or `world.eventBus` from detached background `Task { ... }` blocks without `await MainActor.run`.
- When loading textures, models, or audio asynchronously in background tasks, marshal the loaded assets onto the `@MainActor` before registering them as components.

### Pure Components
- Components MUST be `struct` value types conforming to `Component & Sendable`.
- Never place reference types (`class`) or closure callbacks inside components.
- Never write business logic inside a component. Logic belongs exclusively inside `System` classes.

---

## 2. ECS Query Performance & Memory Allocation

In hot per-frame `System.update()` loops, avoid creating temporary arrays:

| ❌ Inefficient Pattern | ✅ High-Performance Pattern | Rationale |
| :--- | :--- | :--- |
| `for (e, c) in world.entities(with: T.self)` | `world.forEach(T.self) { e, c in ... }` | Eliminates heap array allocation every tick. |
| `for (e, c1) in world.entities(...)` + `world.component(T2)` | `world.forEach(T1.self, T2.self) { e, c1, c2 in ... }` | Loops over the smaller pool with $O(1)$ lookups into the second. |
| `var c = world.component(...)`<br>`c.foo = bar`<br>`world.addComponent(c, to: e)` | `world.mutateComponent(ofType: T.self, for: e) { c in`<br>`    c.foo = bar`<br>`}` | Avoids dictionary entry eviction and re-insertion overhead. |
| `world.entities(with: T.self).forEach { ... }` | `world.mutateEach(T.self) { e, c in ... }` | In-place mutation across all entities without transient arrays. |

---

## 3. GPU Instancing & Draw Call Optimization

AcornEngine's `RenderSystem` batches draw calls automatically, but its efficiency depends on asset organization:

### 1. Unified Sprite Atlases
`RenderSystem` sorts sprites by $Z$ and batches contiguous runs sharing the same `SpriteSheet.texture`:
- Pack as many game sprites (characters, items, particles) into a single sprite sheet as possible.
- Avoid alternating $Z$ depths between sprites from different sprite sheets, which forces frequent draw call pipeline flushes.

### 2. Mesh Instancing
Repeated 3D objects (trees, bullets, coins, buildings) are batched if they reference the identical `any Mesh` instance:
- Generate the mesh once (`renderer.createMesh(vertices:)`) and reuse that same mesh instance across all entities.

### 3. Dirty Flag Hygiene
Components like `SpriteComponent`, `TileMapComponent`, and `TextComponent` have an `isDirty` flag:
- Only set `isDirty = true` when visual geometry or frame names change.
- Leaving `isDirty = true` every frame forces CPU mesh regeneration and GPU buffer reallocation.

---

## 4. Physics Simulation Guidelines (Box2D v3)

### Never Overwrite Dynamic Transforms
Box2D owns the position and rotation of `.dynamicBody` entities:
- Setting `transform.position` on a dynamic body every frame overrides the physics solver and breaks momentum and collision response.
- To move a dynamic body, modify `body.linearVelocity` or apply impulses.
- Use `.kinematicBody` if an entity needs exact programmatic positioning while pushing other physical objects.

### Clean Entity Tear-Down
Always destroy entities through `world.destroyEntity(entity)`:
- Automatically deallocates Box2D body references (`b2DestroyBody`).
- Detaches spatial `AVAudioPlayerNode` instances from the audio mixer.
- Removes child hierarchies and reclaims entity index generation slots.
