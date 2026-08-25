import Foundation
import simd
import AcornEngine

/// System updating moving platform trajectories and animating fragile/disappearing platforms.
@MainActor
public final class PlatformSystem: System {
    
    public init() {}
    
    public func update(world: World, deltaTime: Double) {
        let dt = Float(deltaTime)
        guard dt > 0 else { return }
        
        let platforms = world.entities(with: PlatformComponent.self)
        for (entity, platComp) in platforms {
            guard var transform = world.component(ofType: TransformComponent.self, for: entity) else { continue }
            var platform = platComp
            
            switch platform.type {
            case .movingHorizontal(let amplitude, let speed, let startX, var phase):
                phase += speed * dt
                let newX = startX + sin(phase) * amplitude
                transform.position.x = newX
                platform.type = .movingHorizontal(amplitude: amplitude, speed: speed, startX: startX, phase: phase)
                world.addComponent(transform, to: entity)
                world.addComponent(platform, to: entity)
                
            case .movingVertical(let amplitude, let speed, let startY, var phase):
                phase += speed * dt
                let newY = startY + sin(phase) * amplitude
                transform.position.y = newY
                platform.type = .movingVertical(amplitude: amplitude, speed: speed, startY: startY, phase: phase)
                world.addComponent(transform, to: entity)
                world.addComponent(platform, to: entity)
                
            case .breaking(let isBroken, var breakProgress):
                if isBroken {
                    breakProgress += dt * 3.5
                    transform.position.y -= dt * 4.0 // Broken halves fall
                    if breakProgress >= 1.0 {
                        world.destroyEntity(entity)
                        continue
                    } else {
                        platform.type = .breaking(isBroken: true, breakProgress: breakProgress)
                        world.addComponent(transform, to: entity)
                        world.addComponent(platform, to: entity)
                        updatePlatformSprite(world: world, entity: entity, frameName: "platform_broken_1")
                    }
                }
                
            case .disappearing(var lifetime, let isTriggered):
                if isTriggered {
                    lifetime -= dt
                    if lifetime <= 0 {
                        world.destroyEntity(entity)
                        continue
                    } else {
                        platform.type = .disappearing(lifetime: lifetime, isTriggered: true)
                        world.addComponent(platform, to: entity)
                    }
                }
                
            case .spring(let isCompressed, var cooldown):
                if isCompressed {
                    cooldown -= dt
                    if cooldown <= 0 {
                        platform.type = .spring(isCompressed: false, cooldown: 0.0)
                        world.addComponent(platform, to: entity)
                        updatePlatformSprite(world: world, entity: entity, frameName: "platform_spring_idle")
                    } else {
                        platform.type = .spring(isCompressed: true, cooldown: cooldown)
                        world.addComponent(platform, to: entity)
                        updatePlatformSprite(world: world, entity: entity, frameName: "platform_spring_active")
                    }
                }
                
            default:
                break
            }
        }
    }
    
    private func updatePlatformSprite(world: World, entity: Entity, frameName: String) {
        if var sprite = world.component(ofType: SpriteComponent.self, for: entity),
           sprite.frameName != frameName {
            sprite.frameName = frameName
            sprite.isDirty = true
            world.addComponent(sprite, to: entity)
        }
    }
}
