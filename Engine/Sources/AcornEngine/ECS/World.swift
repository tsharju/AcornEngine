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

/// The central registry managing all entities, components, and systems.
@MainActor
public class World {
    private var nextEntityID: UInt64 = 0
    private var entities: Set<Entity> = []
    
    /// A dictionary mapping the component type's identifier to a dictionary of entity to component.
    private var components: [ObjectIdentifier: [Entity: any Component]] = [:]
    
    /// The systems registered in the world.
    private var systems: [any System] = []
    
    /// Creates a new, empty world.
    public init() {}
    
    /// Creates a new entity and adds it to the world.
    /// - Returns: The newly created entity.
    public func createEntity() -> Entity {
        let entity = Entity(id: nextEntityID)
        nextEntityID += 1
        entities.insert(entity)
        return entity
    }
    
    /// Destroys the given entity, removing it and all its components from the world.
    /// - Parameter entity: The entity to destroy.
    public func destroyEntity(_ entity: Entity) {
        entities.remove(entity)
        for typeId in components.keys {
            components[typeId]?[entity] = nil
        }
        #if DEBUG
        entityNames[entity] = nil
        #endif
    }
    
    /// Adds a component to the specified entity.
    /// - Parameters:
    ///   - component: The component to add.
    ///   - entity: The entity to add the component to.
    public func addComponent<T: Component>(_ component: T, to entity: Entity) {
        guard entities.contains(entity) else { return }
        let typeId = ObjectIdentifier(T.self)
        if components[typeId] == nil {
            components[typeId] = [:]
        }
        components[typeId]?[entity] = component
    }
    
    /// Removes a component of the specified type from the entity.
    /// - Parameters:
    ///   - type: The type of the component to remove.
    ///   - entity: The entity to remove the component from.
    public func removeComponent<T: Component>(ofType type: T.Type, from entity: Entity) {
        let typeId = ObjectIdentifier(T.self)
        components[typeId]?[entity] = nil
    }
    
    /// Retrieves a component of the specified type from the entity.
    /// - Parameters:
    ///   - type: The type of the component to retrieve.
    ///   - entity: The entity to retrieve the component for.
    /// - Returns: The component if it exists, otherwise `nil`.
    public func component<T: Component>(ofType type: T.Type, for entity: Entity) -> T? {
        let typeId = ObjectIdentifier(T.self)
        return components[typeId]?[entity] as? T
    }
    
    /// Retrieves all entities that have a specific component type, along with the component.
    /// - Parameter type: The type of the component to query.
    /// - Returns: An array of tuples containing the entity and its corresponding component.
    public func entities<T: Component>(with type: T.Type) -> [(Entity, T)] {
        let typeId = ObjectIdentifier(T.self)
        guard let componentMap = components[typeId] else { return [] }
        return componentMap.compactMap { (entity, component) in
            guard let typedComponent = component as? T else { return nil }
            return (entity, typedComponent)
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
        for system in systems {
            system.update(world: self, deltaTime: deltaTime)
        }
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
        var result: [any Component] = []
        for typeId in components.keys {
            if let component = components[typeId]?[entity] {
                result.append(component)
            }
        }
        return result
    }
#endif
}
