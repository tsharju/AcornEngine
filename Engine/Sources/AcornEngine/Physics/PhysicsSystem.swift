import Foundation
import box2d
import simd

/// Key wrapper for Box2D shape identifiers to allow dictionary lookups.
private struct ShapeKey: Hashable {
    let index1: Int32
    let world0: UInt16
    let generation: UInt16
    
    init(_ shapeId: b2ShapeId) {
        self.index1 = shapeId.index1
        self.world0 = shapeId.world0
        self.generation = shapeId.generation
    }
}

/// Unordered pair of entities for tracking continuous collision contacts.
private struct EntityPair: Hashable {
    let entityA: Entity
    let entityB: Entity
    
    init(_ a: Entity, _ b: Entity) {
        if a.id < b.id {
            self.entityA = a
            self.entityB = b
        } else {
            self.entityA = b
            self.entityB = a
        }
    }
}

/// Pair tracking sensor trigger volume and visiting entity overlap.
private struct SensorPair: Hashable {
    let sensorEntity: Entity
    let visitorEntity: Entity
}

/// A system that manages the Box2D physics world and synchronizes it with ECS components.
@MainActor
public final class PhysicsSystem: System {
    /// The Box2D world ID.
    public private(set) var worldId: b2WorldId
    
    /// Physics timestep resolution (e.g. 1/60th of a second).
    public var timeStep: Float = 1.0 / 60.0
    
    /// Number of sub-steps per frame.
    public var subStepCount: Int32 = 4
    
    /// Mapping of Box2D shapes to their owning ECS entities.
    private var shapeToEntity: [ShapeKey: Entity] = [:]
    
    /// Actively persisting collision contacts between entity pairs.
    private var activeContacts: Set<EntityPair> = []
    
    /// Actively persisting sensor overlaps between sensor entities and visiting entities.
    private var activeSensors: Set<SensorPair> = []
    
    public init() {
        var worldDef = b2DefaultWorldDef()
        worldDef.gravity = b2Vec2(x: 0.0, y: -9.81)
        self.worldId = b2CreateWorld(&worldDef)
    }
    
    deinit {
        b2DestroyWorld(worldId)
    }
    
    public func update(world: World, deltaTime: Double) {
        let entities = world.entities(with: PhysicsBodyComponent.self)
        
        // 1. Ensure all entities with a PhysicsBodyComponent have a corresponding Box2D body & shapes created
        for (entity, bodyComp) in entities {
            var mutableBodyComp = bodyComp
            
            // Create body if it doesn't exist
            if mutableBodyComp.bodyId == nil {
                guard let transform = world.component(ofType: TransformComponent.self, for: entity) else {
                    continue
                }
                
                var bodyDef = b2DefaultBodyDef()
                bodyDef.type = mutableBodyComp.type.b2Type
                bodyDef.position = b2Vec2(x: transform.position.x, y: transform.position.y)
                
                // Set rotation (Euler Z maps to 2D rotation)
                let angle = transform.rotation.z
                bodyDef.rotation = b2MakeRot(angle)
                
                bodyDef.linearVelocity = b2Vec2(x: mutableBodyComp.linearVelocity.x, y: mutableBodyComp.linearVelocity.y)
                bodyDef.angularVelocity = mutableBodyComp.angularVelocity
                bodyDef.linearDamping = mutableBodyComp.linearDamping
                bodyDef.angularDamping = mutableBodyComp.angularDamping
                bodyDef.gravityScale = mutableBodyComp.gravityScale
                bodyDef.isBullet = mutableBodyComp.isBullet
                bodyDef.fixedRotation = mutableBodyComp.fixedRotation
                bodyDef.isAwake = mutableBodyComp.isAwake
                
                let b2Body = b2CreateBody(worldId, &bodyDef)
                mutableBodyComp.bodyId = b2Body
                world.addComponent(mutableBodyComp, to: entity)
            }
            
            guard let b2Body = mutableBodyComp.bodyId else { continue }
            
            // Attach shape if Collider component exists
            if let colliderComp = world.component(ofType: PhysicsColliderComponent.self, for: entity) {
                var mutableCollider = colliderComp
                if mutableCollider.shapeId == nil {
                    var shapeDef = b2DefaultShapeDef()
                    shapeDef.material.friction = colliderComp.friction
                    shapeDef.material.restitution = colliderComp.restitution
                    shapeDef.density = colliderComp.density
                    shapeDef.isSensor = colliderComp.isSensor
                    shapeDef.enableContactEvents = colliderComp.enableContactEvents
                    shapeDef.enableSensorEvents = colliderComp.enableSensorEvents
                    shapeDef.enableHitEvents = true
                    
                    let shapeId: b2ShapeId
                    switch colliderComp.shapeType {
                    case .box(let width, let height):
                        var box = b2MakeBox(width / 2.0, height / 2.0)
                        shapeId = b2CreatePolygonShape(b2Body, &shapeDef, &box)
                    case .circle(let radius):
                        var circle = b2Circle(center: b2Vec2(x: 0, y: 0), radius: radius)
                        shapeId = b2CreateCircleShape(b2Body, &shapeDef, &circle)
                    }
                    
                    mutableCollider.shapeId = shapeId
                    shapeToEntity[ShapeKey(shapeId)] = entity
                    world.addComponent(mutableCollider, to: entity)
                }
            }
            
            // Attach sensor shape if SensorTriggerComponent exists
            if let sensorComp = world.component(ofType: SensorTriggerComponent.self, for: entity) {
                var mutableSensor = sensorComp
                if mutableSensor.shapeId == nil {
                    var shapeDef = b2DefaultShapeDef()
                    shapeDef.isSensor = true
                    shapeDef.enableSensorEvents = true
                    shapeDef.enableContactEvents = false
                    
                    let shapeId: b2ShapeId
                    switch sensorComp.shapeType {
                    case .box(let width, let height):
                        var box = b2MakeBox(width / 2.0, height / 2.0)
                        shapeId = b2CreatePolygonShape(b2Body, &shapeDef, &box)
                    case .circle(let radius):
                        var circle = b2Circle(center: b2Vec2(x: 0, y: 0), radius: radius)
                        shapeId = b2CreateCircleShape(b2Body, &shapeDef, &circle)
                    }
                    
                    mutableSensor.shapeId = shapeId
                    shapeToEntity[ShapeKey(shapeId)] = entity
                    world.addComponent(mutableSensor, to: entity)
                }
            }
        }
        
        // 2. Step the Box2D simulation
        b2World_Step(worldId, timeStep, subStepCount)
        
        // 3. Process Contact Events
        processContactEvents(world: world)
        
        // 4. Process Sensor Events
        processSensorEvents(world: world)
        
        // 5. Update Transforms based on Box2D simulation
        for (entity, bodyComp) in entities {
            if let b2Body = bodyComp.bodyId {
                guard var transform = world.component(ofType: TransformComponent.self, for: entity) else {
                    continue
                }
                
                let position = b2Body_GetPosition(b2Body)
                let rotation = b2Body_GetRotation(b2Body)
                
                if let parentComp = world.component(ofType: ParentComponent.self, for: entity) {
                    let parentMatrix = world.worldMatrix(for: parentComp.parent)
                    let parentInv = parentMatrix.inverse
                    let worldPos = SIMD4<Float>(position.x, position.y, 0.0, 1.0)
                    let localPos = parentInv * worldPos
                    
                    transform.position.x = localPos.x
                    transform.position.y = localPos.y
                    
                    var parentAngle: Float = 0.0
                    var curr = parentComp.parent
                    while true {
                        if let pt = world.component(ofType: TransformComponent.self, for: curr) {
                            parentAngle += pt.rotation.z
                        }
                        if let p = world.component(ofType: ParentComponent.self, for: curr) {
                            curr = p.parent
                        } else {
                            break
                        }
                    }
                    transform.rotation.z = b2Rot_GetAngle(rotation) - parentAngle
                } else {
                    transform.position.x = position.x
                    transform.position.y = position.y
                    transform.rotation.z = b2Rot_GetAngle(rotation)
                }
                
                world.addComponent(transform, to: entity)
            }
        }
    }
    
    private func processContactEvents(world: World) {
        let contactEvents = b2World_GetContactEvents(worldId)
        var newBeginPairs = Set<EntityPair>()
        var newEndPairs = Set<EntityPair>()
        
        // Process Begin Touch Events (CollisionEnterEvent)
        if contactEvents.beginCount > 0, let beginEvents = contactEvents.beginEvents {
            for i in 0..<Int(contactEvents.beginCount) {
                let event = beginEvents[i]
                guard let entityA = shapeToEntity[ShapeKey(event.shapeIdA)],
                      let entityB = shapeToEntity[ShapeKey(event.shapeIdB)],
                      entityA != entityB else { continue }
                
                let pair = EntityPair(entityA, entityB)
                newBeginPairs.insert(pair)
                activeContacts.insert(pair)
                
                var contactPoint: CollisionContactPoint? = nil
                if event.manifold.pointCount > 0 {
                    let pt = event.manifold.points.0.point
                    let normal = event.manifold.normal
                    contactPoint = CollisionContactPoint(
                        point: SIMD2<Float>(pt.x, pt.y),
                        normal: SIMD2<Float>(normal.x, normal.y)
                    )
                }
                
                world.eventBus.publish(CollisionEnterEvent(
                    entityA: entityA,
                    entityB: entityB,
                    contactPoint: contactPoint
                ))
            }
        }
        
        // Process End Touch Events (CollisionExitEvent)
        if contactEvents.endCount > 0, let endEvents = contactEvents.endEvents {
            for i in 0..<Int(contactEvents.endCount) {
                let event = endEvents[i]
                guard let entityA = shapeToEntity[ShapeKey(event.shapeIdA)],
                      let entityB = shapeToEntity[ShapeKey(event.shapeIdB)],
                      entityA != entityB else { continue }
                
                let pair = EntityPair(entityA, entityB)
                newEndPairs.insert(pair)
                activeContacts.remove(pair)
                
                world.eventBus.publish(CollisionExitEvent(
                    entityA: entityA,
                    entityB: entityB
                ))
            }
        }
        
        // Process Continuing Contacts (CollisionStayEvent)
        for pair in activeContacts {
            if !newBeginPairs.contains(pair) && !newEndPairs.contains(pair) {
                world.eventBus.publish(CollisionStayEvent(
                    entityA: pair.entityA,
                    entityB: pair.entityB
                ))
            }
        }
    }
    
    private func processSensorEvents(world: World) {
        let sensorEvents = b2World_GetSensorEvents(worldId)
        var newSensorBegins = Set<SensorPair>()
        var newSensorEnds = Set<SensorPair>()
        
        // Process Sensor Begin Touch Events (SensorEnterEvent)
        if sensorEvents.beginCount > 0, let beginEvents = sensorEvents.beginEvents {
            for i in 0..<Int(sensorEvents.beginCount) {
                let event = beginEvents[i]
                guard let sensorEntity = shapeToEntity[ShapeKey(event.sensorShapeId)],
                      let visitorEntity = shapeToEntity[ShapeKey(event.visitorShapeId)],
                      sensorEntity != visitorEntity else { continue }
                
                let pair = SensorPair(sensorEntity: sensorEntity, visitorEntity: visitorEntity)
                newSensorBegins.insert(pair)
                activeSensors.insert(pair)
                
                if var triggerComp = world.component(ofType: SensorTriggerComponent.self, for: sensorEntity) {
                    triggerComp.overlappingEntities.insert(visitorEntity)
                    world.addComponent(triggerComp, to: sensorEntity)
                }
                
                world.eventBus.publish(SensorEnterEvent(
                    sensorEntity: sensorEntity,
                    visitorEntity: visitorEntity
                ))
            }
        }
        
        // Process Sensor End Touch Events (SensorExitEvent)
        if sensorEvents.endCount > 0, let endEvents = sensorEvents.endEvents {
            for i in 0..<Int(sensorEvents.endCount) {
                let event = endEvents[i]
                guard let sensorEntity = shapeToEntity[ShapeKey(event.sensorShapeId)],
                      let visitorEntity = shapeToEntity[ShapeKey(event.visitorShapeId)],
                      sensorEntity != visitorEntity else { continue }
                
                let pair = SensorPair(sensorEntity: sensorEntity, visitorEntity: visitorEntity)
                newSensorEnds.insert(pair)
                activeSensors.remove(pair)
                
                if var triggerComp = world.component(ofType: SensorTriggerComponent.self, for: sensorEntity) {
                    triggerComp.overlappingEntities.remove(visitorEntity)
                    world.addComponent(triggerComp, to: sensorEntity)
                }
                
                world.eventBus.publish(SensorExitEvent(
                    sensorEntity: sensorEntity,
                    visitorEntity: visitorEntity
                ))
            }
        }
        
        // Process Continuing Sensor Overlaps (SensorStayEvent)
        for pair in activeSensors {
            if !newSensorBegins.contains(pair) && !newSensorEnds.contains(pair) {
                world.eventBus.publish(SensorStayEvent(
                    sensorEntity: pair.sensorEntity,
                    visitorEntity: pair.visitorEntity
                ))
            }
        }
    }
}
