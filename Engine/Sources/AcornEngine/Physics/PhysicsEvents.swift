import Foundation
import simd

/// Represents detailed information about a physical collision contact point.
public struct CollisionContactPoint: Sendable, Hashable {
    /// The location of the contact point in 2D world space.
    public let point: SIMD2<Float>
    
    /// The surface normal vector pointing from entity A towards entity B.
    public let normal: SIMD2<Float>
    
    /// The relative approach speed at the moment of impact (positive magnitude in m/s).
    public let approachSpeed: Float
    
    /// Initializes a new collision contact point.
    /// - Parameters:
    ///   - point: The contact point in world coordinates.
    ///   - normal: The contact normal vector.
    ///   - approachSpeed: The approach speed in meters per second.
    public init(point: SIMD2<Float>, normal: SIMD2<Float>, approachSpeed: Float = 0.0) {
        self.point = point
        self.normal = normal
        self.approachSpeed = approachSpeed
    }
}

// MARK: - Collision Events

/// Event published when two physical collider shapes first make contact.
public struct CollisionEnterEvent: Event {
    /// The first entity involved in the collision.
    public let entityA: Entity
    
    /// The second entity involved in the collision.
    public let entityB: Entity
    
    /// Information about the contact point, if available.
    public let contactPoint: CollisionContactPoint?
    
    /// Initializes a new collision enter event.
    /// - Parameters:
    ///   - entityA: The first entity.
    ///   - entityB: The second entity.
    ///   - contactPoint: Optional contact point details.
    public init(entityA: Entity, entityB: Entity, contactPoint: CollisionContactPoint? = nil) {
        self.entityA = entityA
        self.entityB = entityB
        self.contactPoint = contactPoint
    }
    
    /// Checks whether the given entity is one of the participants in this collision.
    public func involves(_ entity: Entity) -> Bool {
        return entityA == entity || entityB == entity
    }
    
    /// Returns the other entity in the collision pair given one participant.
    public func otherEntity(than entity: Entity) -> Entity? {
        if entityA == entity { return entityB }
        if entityB == entity { return entityA }
        return nil
    }
}

/// Event published every simulation frame while two physical collider shapes remain in contact.
public struct CollisionStayEvent: Event {
    /// The first entity involved in the collision.
    public let entityA: Entity
    
    /// The second entity involved in the collision.
    public let entityB: Entity
    
    /// Initializes a new collision stay event.
    /// - Parameters:
    ///   - entityA: The first entity.
    ///   - entityB: The second entity.
    public init(entityA: Entity, entityB: Entity) {
        self.entityA = entityA
        self.entityB = entityB
    }
    
    /// Checks whether the given entity is one of the participants in this collision.
    public func involves(_ entity: Entity) -> Bool {
        return entityA == entity || entityB == entity
    }
    
    /// Returns the other entity in the collision pair given one participant.
    public func otherEntity(than entity: Entity) -> Entity? {
        if entityA == entity { return entityB }
        if entityB == entity { return entityA }
        return nil
    }
}

/// Event published when two physical collider shapes stop touching.
public struct CollisionExitEvent: Event {
    /// The first entity involved in the collision.
    public let entityA: Entity
    
    /// The second entity involved in the collision.
    public let entityB: Entity
    
    /// Initializes a new collision exit event.
    /// - Parameters:
    ///   - entityA: The first entity.
    ///   - entityB: The second entity.
    public init(entityA: Entity, entityB: Entity) {
        self.entityA = entityA
        self.entityB = entityB
    }
    
    /// Checks whether the given entity is one of the participants in this collision.
    public func involves(_ entity: Entity) -> Bool {
        return entityA == entity || entityB == entity
    }
    
    /// Returns the other entity in the collision pair given one participant.
    public func otherEntity(than entity: Entity) -> Entity? {
        if entityA == entity { return entityB }
        if entityB == entity { return entityA }
        return nil
    }
}

// MARK: - Sensor / Trigger Events

/// Event published when an entity enters a non-solid sensor / trigger zone.
public struct SensorEnterEvent: Event {
    /// The entity holding the sensor / trigger volume.
    public let sensorEntity: Entity
    
    /// The visiting entity that entered the trigger volume.
    public let visitorEntity: Entity
    
    /// Initializes a new sensor enter event.
    /// - Parameters:
    ///   - sensorEntity: The trigger volume entity.
    ///   - visitorEntity: The visiting entity.
    public init(sensorEntity: Entity, visitorEntity: Entity) {
        self.sensorEntity = sensorEntity
        self.visitorEntity = visitorEntity
    }
}

/// Event published every simulation frame while an entity remains inside a sensor / trigger volume.
public struct SensorStayEvent: Event {
    /// The entity holding the sensor / trigger volume.
    public let sensorEntity: Entity
    
    /// The visiting entity inside the trigger volume.
    public let visitorEntity: Entity
    
    /// Initializes a new sensor stay event.
    /// - Parameters:
    ///   - sensorEntity: The trigger volume entity.
    ///   - visitorEntity: The visiting entity.
    public init(sensorEntity: Entity, visitorEntity: Entity) {
        self.sensorEntity = sensorEntity
        self.visitorEntity = visitorEntity
    }
}

/// Event published when an entity exits a sensor / trigger volume.
public struct SensorExitEvent: Event {
    /// The entity holding the sensor / trigger volume.
    public let sensorEntity: Entity
    
    /// The visiting entity that left the trigger volume.
    public let visitorEntity: Entity
    
    /// Initializes a new sensor exit event.
    /// - Parameters:
    ///   - sensorEntity: The trigger volume entity.
    ///   - visitorEntity: The visiting entity.
    public init(sensorEntity: Entity, visitorEntity: Entity) {
        self.sensorEntity = sensorEntity
        self.visitorEntity = visitorEntity
    }
}
