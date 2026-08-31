import simd

#if DEBUG
public struct ComponentMetadata: Sendable {
    public let name: String
    public let type: any Component.Type
    public let factory: @Sendable () -> any Component
    
    public init(name: String, type: any Component.Type, factory: @escaping @Sendable () -> any Component) {
        self.name = name
        self.type = type
        self.factory = factory
    }
}

/// A registry for components, used by the editor to know what component types can be added to an entity.
@MainActor
public struct ComponentRegistry {
    public static var components: [ComponentMetadata] = []
    
    public static func register<T: Component>(name: String, type: T.Type, factory: @escaping @Sendable () -> T) {
        components.append(ComponentMetadata(name: name, type: type, factory: factory))
    }
}
#endif

/// An internal type-erased interface for concrete component storage pools.
@MainActor
private protocol AnyComponentPool: AnyObject {
    func removeEntity(_ entity: Entity)
    #if DEBUG
    func getComponent(for entity: Entity) -> (any Component)?
    #endif
}

/// A strongly-typed storage pool for components of type `T`.
/// Eliminates existential boxing and avoids dynamic casting during entity lookups.
@MainActor
private final class ComponentPool<T: Component>: AnyComponentPool {
    var items: [Entity: T] = [:]
    
    func removeEntity(_ entity: Entity) {
        items.removeValue(forKey: entity)
    }
    
    #if DEBUG
    func getComponent(for entity: Entity) -> (any Component)? {
        items[entity]
    }
    #endif
}

/// The central registry managing all entities, components, and systems.
@MainActor
public class World {
    private var nextEntityID: UInt64 = 0
    private var freeEntityIDs: [UInt64] = []
    private var entities: Set<Entity> = []
    
    /// Typed component storage pools keyed by the component type's ObjectIdentifier.
    private var componentPools: [ObjectIdentifier: any AnyComponentPool] = [:]
    
    /// Tracks which component types each entity currently possesses for fast O(1) destruction.
    private var entityComponentTypes: [Entity: [ObjectIdentifier]] = [:]
    
    /// The event bus for decoupled message publishing and subscriptions.
    public let eventBus: EventBus
    
    /// The systems registered in the world.
    private var systems: [any System] = []
    
    /// Creates a new, empty world.
    public init(eventBus: EventBus = EventBus()) {
        self.eventBus = eventBus
    }
    
    /// Creates a new entity and adds it to the world (reusing destroyed IDs if available).
    /// - Returns: The newly created entity.
    public func createEntity() -> Entity {
        let id: UInt64
        if let recycled = freeEntityIDs.popLast() {
            id = recycled
        } else {
            id = nextEntityID
            nextEntityID += 1
        }
        let entity = Entity(id: id)
        entities.insert(entity)
        return entity
    }
    
    /// Destroys the given entity, removing it and all its components from the world in O(owned components).
    /// - Parameter entity: The entity to destroy.
    public func destroyEntity(_ entity: Entity) {
        guard entities.contains(entity) else { return }
        entities.remove(entity)
        freeEntityIDs.append(entity.id)
        
        if let typeIds = entityComponentTypes.removeValue(forKey: entity) {
            for typeId in typeIds {
                componentPools[typeId]?.removeEntity(entity)
            }
        }
        #if DEBUG
        entityNames[entity] = nil
        #endif
    }
    
    /// Adds a component to the specified entity without existential boxing.
    /// - Parameters:
    ///   - component: The component to add.
    ///   - entity: The entity to add the component to.
    public func addComponent<T: Component>(_ component: T, to entity: Entity) {
        guard entities.contains(entity) else { return }
        let typeId = ObjectIdentifier(T.self)
        let pool: ComponentPool<T>
        if let existing = componentPools[typeId] as? ComponentPool<T> {
            pool = existing
        } else {
            pool = ComponentPool<T>()
            componentPools[typeId] = pool
        }
        
        if pool.items[entity] == nil {
            entityComponentTypes[entity, default: []].append(typeId)
        }
        pool.items[entity] = component
    }
    
    /// Removes a component of the specified type from the entity.
    /// - Parameters:
    ///   - type: The type of the component to remove.
    ///   - entity: The entity to remove the component from.
    public func removeComponent<T: Component>(ofType type: T.Type, from entity: Entity) {
        let typeId = ObjectIdentifier(T.self)
        if let pool = componentPools[typeId] as? ComponentPool<T> {
            pool.items.removeValue(forKey: entity)
        }
        if var types = entityComponentTypes[entity] {
            types.removeAll { $0 == typeId }
            if types.isEmpty {
                entityComponentTypes.removeValue(forKey: entity)
            } else {
                entityComponentTypes[entity] = types
            }
        }
    }
    
    /// Retrieves a component of the specified type from the entity.
    /// - Parameters:
    ///   - type: The type of the component to retrieve.
    ///   - entity: The entity to retrieve the component for.
    /// - Returns: The component if it exists, otherwise `nil`.
    @inline(__always)
    public func component<T: Component>(ofType type: T.Type, for entity: Entity) -> T? {
        let typeId = ObjectIdentifier(T.self)
        guard let pool = componentPools[typeId] as? ComponentPool<T> else { return nil }
        return pool.items[entity]
    }
    
    /// Mutates an existing component in-place without copying out and re-adding.
    /// - Parameters:
    ///   - type: The type of the component to mutate.
    ///   - entity: The entity owning the component.
    ///   - modify: A closure modifying the component in place.
    @inline(__always)
    public func mutateComponent<T: Component>(ofType type: T.Type = T.self, for entity: Entity, _ modify: (inout T) -> Void) {
        let typeId = ObjectIdentifier(T.self)
        guard let pool = componentPools[typeId] as? ComponentPool<T>,
              var comp = pool.items[entity] else { return }
        modify(&comp)
        pool.items[entity] = comp
    }
    
    /// Retrieves all entities that have a specific component type, along with the component.
    /// - Parameter type: The type of the component to query.
    /// - Returns: An array of tuples containing the entity and its corresponding component.
    public func entities<T: Component>(with type: T.Type) -> [(Entity, T)] {
        let typeId = ObjectIdentifier(T.self)
        guard let pool = componentPools[typeId] as? ComponentPool<T> else { return [] }
        return Array(pool.items)
    }
    
    /// Retrieves the first entity possessing a specific component type.
    /// - Parameter type: The component type to query.
    /// - Returns: The first matching (Entity, T) tuple if found, otherwise `nil`.
    @inline(__always)
    public func firstEntity<T: Component>(with type: T.Type = T.self) -> (Entity, T)? {
        let typeId = ObjectIdentifier(T.self)
        guard let pool = componentPools[typeId] as? ComponentPool<T>,
              let first = pool.items.first else { return nil }
        return (first.key, first.value)
    }
    
    /// Iterates over all entities with a specific component type without transient array allocation.
    /// - Parameters:
    ///   - type: The component type to iterate over.
    ///   - body: A closure executed for each entity and component pair.
    @inline(__always)
    public func forEach<T: Component>(_ type: T.Type = T.self, _ body: (Entity, T) -> Void) {
        let typeId = ObjectIdentifier(T.self)
        guard let pool = componentPools[typeId] as? ComponentPool<T> else { return }
        for (entity, comp) in pool.items {
            body(entity, comp)
        }
    }
    
    /// Iterates over all entities possessing two specific component types without temporary array allocation.
    /// Iterates over the smaller component pool and performs fast O(1) lookups into the second pool.
    @inline(__always)
    public func forEach<T1: Component, T2: Component>(
        _ t1: T1.Type = T1.self,
        _ t2: T2.Type = T2.self,
        _ body: (Entity, T1, T2) -> Void
    ) {
        let id1 = ObjectIdentifier(T1.self)
        let id2 = ObjectIdentifier(T2.self)
        guard let pool1 = componentPools[id1] as? ComponentPool<T1>,
              let pool2 = componentPools[id2] as? ComponentPool<T2> else { return }
        
        if pool1.items.count <= pool2.items.count {
            for (entity, c1) in pool1.items {
                if let c2 = pool2.items[entity] {
                    body(entity, c1, c2)
                }
            }
        } else {
            for (entity, c2) in pool2.items {
                if let c1 = pool1.items[entity] {
                    body(entity, c1, c2)
                }
            }
        }
    }
    
    /// Registers a system with the world.
    /// - Parameter system: The system to register.
    public func registerSystem(_ system: any System) {
        systems.append(system)
    }
    
    /// Updates all registered systems.
    /// - Parameter deltaTime: The time elapsed since the last update.
    public func update(deltaTime: Double) {
        eventBus.publish(EngineTickEvent(deltaTime: deltaTime))
        for system in systems {
            system.update(world: self, deltaTime: deltaTime)
        }
        eventBus.clear()
    }
    
    /// Computes the world transformation matrix for the given entity by traversing its parent chain.
    public func worldMatrix(for entity: Entity) -> simd_float4x4 {
        var currentEntity = entity
        var accumulatedMatrix = simd_float4x4.identity
        
        while true {
            if let transform = self.component(ofType: TransformComponent.self, for: currentEntity) {
                accumulatedMatrix = matrix_multiply(transform.matrix, accumulatedMatrix)
            }
            if let parentComp = self.component(ofType: ParentComponent.self, for: currentEntity) {
                currentEntity = parentComp.parent
            } else {
                break
            }
        }
        
        return accumulatedMatrix
    }

    /// Computes the world position for the given entity.
    public func worldPosition(for entity: Entity) -> SIMD3<Float> {
        let matrix = worldMatrix(for: entity)
        return SIMD3<Float>(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }
    
#if DEBUG
    private var entityNames: [Entity: String] = [:]
    
    public func name(for entity: Entity) -> String {
        return entityNames[entity] ?? "Entity \(entity.id)"
    }
    
    public func setName(_ name: String, for entity: Entity) {
        entityNames[entity] = name
    }

    /// Retrieves all entities in the world. (Editor-only feature)
    public var allEntities: [Entity] {
        Array(entities)
    }
    
    /// Retrieves all components for a given entity. (Editor-only feature)
    public func allComponents(for entity: Entity) -> [any Component] {
        guard let typeIds = entityComponentTypes[entity] else { return [] }
        var result: [any Component] = []
        for typeId in typeIds {
            if let component = componentPools[typeId]?.getComponent(for: entity) {
                result.append(component)
            }
        }
        return result
    }
#endif
}
