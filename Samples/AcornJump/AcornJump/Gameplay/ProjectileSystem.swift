import Foundation
import simd
import AcornEngine

/// System that moves fired acorn seed projectiles and resolves bullet-monster hits.
@MainActor
public final class ProjectileSystem: System {
    
    public init() {}
    
    public func update(world: World, deltaTime: Double) {
        let dt = Float(deltaTime)
        guard dt > 0 else { return }
        
        let projectiles = world.entities(with: ProjectileComponent.self)
        let monsters = world.entities(with: MonsterComponent.self)
        
        for (bulletEntity, bulletComp) in projectiles {
            guard var transform = world.component(ofType: TransformComponent.self, for: bulletEntity) else { continue }
            var bullet = bulletComp
            
            bullet.lifetime -= dt
            if bullet.lifetime <= 0 {
                world.destroyEntity(bulletEntity)
                continue
            }
            
            transform.position.x += bullet.velocity.x * dt
            transform.position.y += bullet.velocity.y * dt
            
            // Check collisions against monsters
            var hitMonster = false
            for (monsterEntity, monsterComp) in monsters {
                guard monsterComp.isAlive,
                      let monsterTransform = world.component(ofType: TransformComponent.self, for: monsterEntity) else { continue }
                
                let dx = transform.position.x - monsterTransform.position.x
                let dy = transform.position.y - monsterTransform.position.y
                let distSq = dx * dx + dy * dy
                
                if distSq < (0.6 * 0.6) {
                    hitMonster = true
                    SoundManager.shared.playMonsterDefeated()
                    
                    // Award player score
                    if let playerTuple = world.entities(with: JumperComponent.self).first {
                        var jumper = playerTuple.1
                        jumper.score += monsterComp.type.scoreValue
                        world.addComponent(jumper, to: playerTuple.0)
                    }
                    
                    world.destroyEntity(monsterEntity)
                    break
                }
            }
            
            if hitMonster {
                world.destroyEntity(bulletEntity)
            } else {
                world.addComponent(transform, to: bulletEntity)
                world.addComponent(bullet, to: bulletEntity)
            }
        }
    }
}
