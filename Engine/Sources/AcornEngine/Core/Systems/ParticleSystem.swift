import Foundation
import simd

/// An ECS System that manages the emission, lifecycle, and physics of particles.
@MainActor
public final class ParticleSystem: System {
    
    public init() {}
    
    public func update(world: World, deltaTime: Double) {
        // 1. Update existing particles (age and destroy)
        let particles = world.entities(with: ParticleComponent.self)
        for (entity, comp) in particles {
            if comp.age + deltaTime >= comp.lifetime {
                world.destroyEntity(entity)
            } else {
                world.mutateComponent(ofType: ParticleComponent.self, for: entity) { particle in
                    particle.age += deltaTime
                }
            }
        }
        
        // 2. Emit new particles
        world.forEach(ParticleEmitterComponent.self) { entity, emitter in
            var mutableEmitter = emitter
            guard mutableEmitter.isEmitting else { return }
            
            mutableEmitter.timeSinceLastEmit += deltaTime
            
            // Only emit if we have a valid rate
            guard mutableEmitter.emitRate > 0 else { return }
            
            let emitInterval = 1.0 / mutableEmitter.emitRate
            
            // Need transform to know where to spawn
            guard let transform = world.component(ofType: TransformComponent.self, for: entity) else { return }
            
            while mutableEmitter.timeSinceLastEmit >= emitInterval {
                mutableEmitter.timeSinceLastEmit -= emitInterval
                
                let particleEntity = world.createEntity()
                
                // Pick a random scale
                let scale = Float.random(in: mutableEmitter.scale)
                let pTransform = TransformComponent(
                    position: transform.position,
                    rotation: transform.rotation,
                    scale: SIMD3<Float>(repeating: scale)
                )
                world.addComponent(pTransform, to: particleEntity)
                
                // Pick a random lifetime
                let lifetime = Double.random(in: mutableEmitter.lifetime)
                let pComp = ParticleComponent(lifetime: lifetime)
                world.addComponent(pComp, to: particleEntity)
                
                // Pick a random mesh
                if let mesh = mutableEmitter.meshes.randomElement() {
                    let meshComp = MeshComponent(mesh: mesh)
                    world.addComponent(meshComp, to: particleEntity)
                }
                
                // Setup physics body
                let vx = Float.random(in: mutableEmitter.linearVelocityX)
                let vy = Float.random(in: mutableEmitter.linearVelocityY)
                let angular = Float.random(in: mutableEmitter.angularVelocity)
                
                let physicsBody = PhysicsBodyComponent(
                    type: .dynamicBody,
                    linearVelocity: SIMD2<Float>(x: vx, y: vy),
                    angularVelocity: angular
                )
                world.addComponent(physicsBody, to: particleEntity)
                
                // Add a small box collider (assuming mesh is ~1x1 scaled down by 'scale')
                let collider = PhysicsColliderComponent(
                    shapeType: .box(width: scale, height: scale),
                    restitution: 0.3,
                    density: 1.0
                )
                world.addComponent(collider, to: particleEntity)
            }
            
            world.addComponent(mutableEmitter, to: entity)
        }
    }
}
