import box2d
import simd

/// A component representing a non-solid sensor / trigger volume attached to an entity's physics body.
///
/// Sensor triggers detect when other physical shapes overlap their boundaries without producing physical collision forces.
public struct SensorTriggerComponent: Component, @unchecked Sendable {
    /// The geometric shape of the trigger volume.
    public var shapeType: PhysicsColliderComponent.ShapeType
    
    /// The set of entities currently overlapping this sensor trigger.
    public var overlappingEntities: Set<Entity>
    
    /// Internal Box2D shape ID. Managed by `PhysicsSystem`.
    public internal(set) var shapeId: b2ShapeId?
    
    /// Initializes a new sensor trigger component.
    /// - Parameter shapeType: The geometric shape of the trigger volume.
    public init(shapeType: PhysicsColliderComponent.ShapeType) {
        self.shapeType = shapeType
        self.overlappingEntities = []
        self.shapeId = nil
    }
    
    /// Checks whether the specified entity is currently overlapping this sensor trigger.
    /// - Parameter entity: The entity to check.
    /// - Returns: `true` if overlapping, otherwise `false`.
    public func isOverlapping(_ entity: Entity) -> Bool {
        return overlappingEntities.contains(entity)
    }
    
    /// The number of entities currently inside this sensor volume.
    public var overlapCount: Int {
        return overlappingEntities.count
    }
}
