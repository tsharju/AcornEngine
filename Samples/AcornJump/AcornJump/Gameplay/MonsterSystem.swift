import Foundation
import simd
import AcornEngine

/// System updating monster movement patterns and black hole gravitational pull.
@MainActor
public final class MonsterSystem: System {
    
    public init() {}
    
    public func update(world: World, deltaTime: Double) {
        let dt = Float(deltaTime)
        guard dt > 0 else { return }
        
        let playerTuple = world.entities(with: JumperComponent.self).first
        let playerPos = playerTuple != nil ? world.component(ofType: TransformComponent.self, for: playerTuple!.0)?.position : nil
        
        let monsters = world.entities(with: MonsterComponent.self)
        for (entity, monsterComp) in monsters {
            guard var transform = world.component(ofType: TransformComponent.self, for: entity) else { continue }
            var monster = monsterComp
            
            switch monster.type {
            case .spider(let amplitude, let speed, let startX, var phase):
                phase += speed * dt
                transform.position.x = startX + sin(phase) * amplitude
                monster.type = .spider(amplitude: amplitude, speed: speed, startX: startX, phase: phase)
                world.addComponent(transform, to: entity)
                world.addComponent(monster, to: entity)
                
            case .bat(let frequency, let amplitude, var time, let startX):
                time += dt
                transform.position.x = startX + sin(time * frequency) * amplitude * 1.5
                transform.position.y += cos(time * frequency * 2.0) * amplitude * dt
                monster.type = .bat(frequency: frequency, amplitude: amplitude, time: time, startX: startX)
                world.addComponent(transform, to: entity)
                world.addComponent(monster, to: entity)
                
            case .chestnut(let bounceSpeed, let startY):
                let bounceY = startY + abs(sin(Float(ProcessInfo.processInfo.systemUptime) * bounceSpeed)) * 0.8
                transform.position.y = bounceY
                world.addComponent(transform, to: entity)
                
            case .blackhole(let pullRadius, let pullForce):
                // Swirl rotation
                transform.rotation.z += dt * 3.0
                world.addComponent(transform, to: entity)
                
                // Pull player if nearby
                if let playerEntity = playerTuple?.0,
                   var playerTransform = world.component(ofType: TransformComponent.self, for: playerEntity),
                   var jumper = world.component(ofType: JumperComponent.self, for: playerEntity),
                   jumper.isAlive {
                    
                    let dx = transform.position.x - playerTransform.position.x
                    let dy = transform.position.y - playerTransform.position.y
                    let dist = sqrt(dx * dx + dy * dy)
                    
                    if dist < pullRadius && dist > 0.05 {
                        let pull = (1.0 - (dist / pullRadius)) * pullForce * dt
                        playerTransform.position.x += (dx / dist) * pull
                        playerTransform.position.y += (dy / dist) * pull
                        world.addComponent(playerTransform, to: playerEntity)
                    }
                }
            }
        }
    }
}
