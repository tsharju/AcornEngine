import Foundation
import box2d
import simd

/// A system that manages the Box2D physics world and synchronizes it with ECS components.
@MainActor
public final class PhysicsSystem: System {
    /// The Box2D world ID.
    public private(set) var worldId: b2WorldId
    
    /// Physics timestep resolution (e.g. 1/60th of a second).
    public var timeStep: Float = 1.0 / 60.0
    
    /// Number of sub-steps per frame.
    public var subStepCount: Int32 = 4
    
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
        
        // Ensure all entities with a PhysicsBodyComponent have a corresponding Box2D body created
        for (entity, bodyComp) in entities {
            var mutableBodyComp = bodyComp
            
            // 1. Create body if it doesn't exist
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
                
                // 2. Attach shape if Collider component exists
                if let colliderComp = world.component(ofType: PhysicsColliderComponent.self, for: entity) {
                    var mutableCollider = colliderComp
                    if mutableCollider.shapeId == nil {
                        var shapeDef = b2DefaultShapeDef()
                        shapeDef.material.friction = colliderComp.friction
                        shapeDef.material.restitution = colliderComp.restitution
                        shapeDef.density = colliderComp.density
                        
                        let shapeId: b2ShapeId
                        switch colliderComp.shapeType {
                        case .box(let width, let height):
                            // Box2D uses half-width and half-height
                            var box = b2MakeBox(width / 2.0, height / 2.0)
                            shapeId = b2CreatePolygonShape(b2Body, &shapeDef, &box)
                        case .circle(let radius):
                            var circle = b2Circle(center: b2Vec2(x: 0, y: 0), radius: radius)
                            shapeId = b2CreateCircleShape(b2Body, &shapeDef, &circle)
                        }
                        
                        mutableCollider.shapeId = shapeId
                        world.addComponent(mutableCollider, to: entity)
                    }
                }
                
                world.addComponent(mutableBodyComp, to: entity)
            } else {
                // If the body already exists, maybe its properties changed?
                // For a proper integration, we should also handle properties being updated from the Swift side
                // and applying them to Box2D. For now we assume physics owns the transform.
            }
        }
        
        // 3. Step the Box2D simulation
        // Note: For simplicity, we are stepping by a fixed timestep here regardless of deltaTime.
        // A robust physics system might accumulate deltaTime and step multiple times if needed.
        b2World_Step(worldId, timeStep, subStepCount)
        
        // 4. Update Transforms based on Box2D simulation
        for (entity, bodyComp) in entities {
            if let b2Body = bodyComp.bodyId {
                guard var transform = world.component(ofType: TransformComponent.self, for: entity) else {
                    continue
                }
                
                let position = b2Body_GetPosition(b2Body)
                let rotation = b2Body_GetRotation(b2Body)
                
                transform.position.x = position.x
                transform.position.y = position.y
                transform.rotation.z = b2Rot_GetAngle(rotation)
                
                world.addComponent(transform, to: entity)
            }
        }
    }
}
