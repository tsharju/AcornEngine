import Foundation
import simd
import AcornEngine

/// The core system driving player physics, jump bounce mechanics, platform landing, power-ups, and collisions.
@MainActor
public final class JumperSystem: System {
    
    private let baseScale: Float = 0.0032
    
    public init() {}
    
    public func update(world: World, deltaTime: Double) {
        let dt = Float(deltaTime)
        guard dt > 0 else { return }
        
        let jumpers = world.entities(with: JumperComponent.self)
        guard let (jumperEntity, jumperComp) = jumpers.first,
              var transform = world.component(ofType: TransformComponent.self, for: jumperEntity) else {
            return
        }
        
        var jumper = jumperComp
        
        // If player is dead or victory has been triggered, apply simple death fall or float
        if !jumper.isAlive {
            jumper.velocity.y += jumper.baseGravity * dt
            transform.position.y += jumper.velocity.y * dt
            transform.position.x += jumper.velocity.x * dt
            transform.rotation.z += dt * 4.0 // Tumble on death
            world.addComponent(transform, to: jumperEntity)
            updateSprite(world: world, entity: jumperEntity, jumper: jumper)
            return
        }
        
        if jumper.hasReachedFinish {
            // Decelerate and float gracefully in victory
            jumper.velocity.y = max(0.0, jumper.velocity.y - 10.0 * dt)
            transform.position.y += jumper.velocity.y * dt
            transform.rotation.z = simd_mix(transform.rotation.z, 0.0, min(1.0, 8.0 * dt))
            world.addComponent(transform, to: jumperEntity)
            updateSprite(world: world, entity: jumperEntity, jumper: jumper)
            return
        }
        
        // 1. Process Active Power-Ups
        if jumper.powerupTimeRemaining > 0 {
            jumper.powerupTimeRemaining -= dt
            if jumper.powerupTimeRemaining <= 0 {
                jumper.activePowerup = nil
            }
        }
        
        if jumper.shootCooldown > 0 {
            jumper.shootCooldown -= dt
        }
        
        // 2. Vertical Physics & Flight Modes
        if let powerup = jumper.activePowerup {
            switch powerup {
            case .jetpack:
                jumper.velocity.y = jumper.jetpackThrustVelocity
                jumper.state = .flyingJetpack
                SoundManager.shared.playJetpack()
            case .propeller:
                jumper.velocity.y = jumper.propellerThrustVelocity
                jumper.state = .flyingPropeller
                SoundManager.shared.playPropeller()
            default:
                break
            }
        }
        
        // Normal Gravity with Apex Hang-Time
        if jumper.state != .flyingJetpack && jumper.state != .flyingPropeller {
            let isNearApex = abs(jumper.velocity.y) < 2.5
            let effectiveGravity = jumper.baseGravity * (isNearApex ? jumper.apexGravityMultiplier : 1.0)
            
            jumper.velocity.y += effectiveGravity * dt
            jumper.velocity.y = max(jumper.terminalVelocity, jumper.velocity.y)
            jumper.state = jumper.velocity.y >= 0 ? .jumping : .falling
        }
        
        // 3. Fluid Horizontal Inertia & Steering
        if abs(jumper.horizontalSteering) > 0.03 {
            let accel = jumper.horizontalSteering * jumper.horizontalAcceleration
            jumper.velocity.x += accel * dt
            jumper.velocity.x = max(-jumper.maxHorizontalSpeed, min(jumper.maxHorizontalSpeed, jumper.velocity.x))
            jumper.isFacingRight = jumper.horizontalSteering > 0
        } else {
            // Decelerate smoothly towards 0 when no input
            let decel = jumper.horizontalDeceleration * dt
            if jumper.velocity.x > 0 {
                jumper.velocity.x = max(0.0, jumper.velocity.x - decel)
            } else if jumper.velocity.x < 0 {
                jumper.velocity.x = min(0.0, jumper.velocity.x + decel)
            }
        }
        
        // Track previous foot position for continuous collision sweep
        let prevFootY = transform.position.y - 0.35
        jumper.previousY = transform.position.y
        
        transform.position.x += jumper.velocity.x * dt
        transform.position.y += jumper.velocity.y * dt
        let currFootY = transform.position.y - 0.35
        
        // Screen Wrap-Around
        let wrap = jumper.screenWrapBounds
        if transform.position.x > wrap {
            transform.position.x = -wrap + 0.1
        } else if transform.position.x < -wrap {
            transform.position.x = wrap - 0.1
        }
        
        jumper.currentHeight = transform.position.y
        if jumper.currentHeight > jumper.maxHeightReached {
            let heightGain = jumper.currentHeight - jumper.maxHeightReached
            jumper.maxHeightReached = jumper.currentHeight
            jumper.score += Int(heightGain * 10.0)
        }
        
        // 4. Continuous Swept Platform Landing & Bounce
        let playerX = transform.position.x
        
        if jumper.velocity.y <= 0.0 && jumper.state != .flyingJetpack && jumper.state != .flyingPropeller {
            let platforms = world.entities(with: PlatformComponent.self)
            for (platEntity, platComp) in platforms {
                guard let platTransform = world.component(ofType: TransformComponent.self, for: platEntity) else { continue }
                
                let px = platTransform.position.x
                let py = platTransform.position.y
                let halfW = platComp.width * 0.5
                
                // Horizontal bounds check
                let withinX = (playerX >= px - halfW - 0.22) && (playerX <= px + halfW + 0.22)
                
                // Continuous vertical swept segment test: platform top crossed between prevFootY and currFootY
                let minFoot = min(prevFootY, currFootY) - 0.08
                let maxFoot = max(prevFootY, currFootY) + 0.20
                let withinY = (py >= minFoot) && (py <= maxFoot)
                
                if withinX && withinY {
                    var mutablePlatform = platComp
                    mutablePlatform.isSteppedOn = true
                    
                    // Snap feet to top of platform
                    transform.position.y = py + 0.35
                    
                    switch mutablePlatform.type {
                    case .wood, .leaf, .movingHorizontal, .movingVertical:
                        if jumper.springShoesJumpsRemaining > 0 {
                            jumper.velocity.y = jumper.springJumpVelocity
                            jumper.springShoesJumpsRemaining -= 1
                            jumper.squashStretch = SIMD2<Float>(0.75, 1.35)
                            SoundManager.shared.playSpring()
                        } else {
                            jumper.velocity.y = mutablePlatform.jumpBoost
                            jumper.squashStretch = SIMD2<Float>(1.28, 0.72) // Squash on bounce
                            SoundManager.shared.playJump()
                        }
                        jumper.state = .jumping
                        
                    case .spring:
                        jumper.velocity.y = mutablePlatform.springBoost
                        mutablePlatform.type = .spring(isCompressed: true, cooldown: 0.25)
                        jumper.squashStretch = SIMD2<Float>(0.72, 1.45) // Super stretch
                        jumper.state = .jumping
                        SoundManager.shared.playSpring()
                        
                    case .breaking(let isBroken, _):
                        if !isBroken {
                            mutablePlatform.type = .breaking(isBroken: true, breakProgress: 0.0)
                            SoundManager.shared.playBreakPlatform()
                        }
                        // Brittle branch gives NO jump bounce
                        
                    case .disappearing(let lifetime, _):
                        mutablePlatform.type = .disappearing(lifetime: lifetime, isTriggered: true)
                        jumper.velocity.y = mutablePlatform.jumpBoost
                        jumper.squashStretch = SIMD2<Float>(1.25, 0.75)
                        jumper.state = .jumping
                        SoundManager.shared.playJump()
                    }
                    
                    world.addComponent(mutablePlatform, to: platEntity)
                    break
                }
            }
        }
        
        // 5. Collectible Pickup Detection
        let collectibles = world.entities(with: CollectibleComponent.self)
        for (itemEntity, itemComp) in collectibles {
            guard !itemComp.isCollected,
                  let itemTransform = world.component(ofType: TransformComponent.self, for: itemEntity) else { continue }
            
            let dx = transform.position.x - itemTransform.position.x
            let dy = transform.position.y - itemTransform.position.y
            let distSq = dx * dx + dy * dy
            
            if distSq < (0.60 * 0.60) {
                var mutableItem = itemComp
                mutableItem.isCollected = true
                jumper.score += itemComp.type.scoreValue
                
                switch itemComp.type {
                case .goldenAcorn:
                    jumper.goldenAcornsCollected += 1
                    SoundManager.shared.playAcornCollected()
                case .star:
                    jumper.starsCollected += 1
                    SoundManager.shared.playStarCollected()
                case .powerup(let powerType):
                    jumper.activePowerup = powerType
                    switch powerType {
                    case .propeller(let duration):
                        jumper.powerupTimeRemaining = duration
                        SoundManager.shared.playPropeller()
                    case .jetpack(let duration):
                        jumper.powerupTimeRemaining = duration
                        SoundManager.shared.playJetpack()
                    case .shield(let charges):
                        jumper.shieldCharges += charges
                        SoundManager.shared.playShieldHit()
                    case .springShoes(let jumps):
                        jumper.springShoesJumpsRemaining += jumps
                        SoundManager.shared.playSpring()
                    }
                }
                
                world.destroyEntity(itemEntity)
            }
        }
        
        // 6. Monster & Hazard Collisions
        let monsters = world.entities(with: MonsterComponent.self)
        for (monsterEntity, monsterComp) in monsters {
            guard monsterComp.isAlive,
                  let monsterTransform = world.component(ofType: TransformComponent.self, for: monsterEntity) else { continue }
            
            let mx = monsterTransform.position.x
            let my = monsterTransform.position.y
            let dx = transform.position.x - mx
            let dy = transform.position.y - my
            let distSq = dx * dx + dy * dy
            
            if distSq < (0.65 * 0.65) {
                // If player is descending and above monster center -> STOMP!
                if jumper.velocity.y <= 0.0 && transform.position.y > my + 0.12 && monsterComp.type.scoreValue > 0 {
                    jumper.velocity.y = 13.0
                    jumper.score += monsterComp.type.scoreValue
                    jumper.squashStretch = SIMD2<Float>(1.30, 0.70)
                    SoundManager.shared.playMonsterDefeated()
                    
                    var mutableMonster = monsterComp
                    mutableMonster.isAlive = false
                    world.destroyEntity(monsterEntity)
                } else {
                    // Side or bottom collision
                    if jumper.shieldCharges > 0 {
                        jumper.shieldCharges -= 1
                        jumper.velocity.y = 9.0
                        SoundManager.shared.playShieldHit()
                        world.destroyEntity(monsterEntity)
                    } else if jumper.state != .flyingJetpack {
                        // Player Defeated
                        jumper.isAlive = false
                        jumper.state = .dead
                        jumper.velocity.y = -6.0
                        SoundManager.shared.playGameOver()
                    }
                }
            }
        }
        
        // 7. Check Victory Finish Line (Campaign Mode)
        if jumper.isCampaign && jumper.currentHeight >= jumper.targetLevelHeight {
            jumper.hasReachedFinish = true
            jumper.state = .victory
            SoundManager.shared.playVictory()
        }
        
        // 8. Squash / Stretch & Body Lean Interpolation
        jumper.squashStretch.x = simd_mix(jumper.squashStretch.x, 1.0, min(1.0, 10.0 * dt))
        jumper.squashStretch.y = simd_mix(jumper.squashStretch.y, 1.0, min(1.0, 10.0 * dt))
        
        // Tilt body slightly in direction of horizontal motion (~12 degrees max)
        let targetLean = -max(-1.0, min(1.0, jumper.velocity.x / jumper.maxHorizontalSpeed)) * 0.20
        jumper.leanAngle = simd_mix(jumper.leanAngle, targetLean, min(1.0, 12.0 * dt))
        transform.rotation.z = jumper.leanAngle
        
        // Scale with squash/stretch
        let xSign: Float = jumper.isFacingRight ? 1.0 : -1.0
        transform.scale = SIMD3<Float>(
            baseScale * jumper.squashStretch.x * xSign,
            baseScale * jumper.squashStretch.y,
            baseScale
        )
        
        world.addComponent(transform, to: jumperEntity)
        world.addComponent(jumper, to: jumperEntity)
        
        updateSprite(world: world, entity: jumperEntity, jumper: jumper)
    }
    
    private func updateSprite(world: World, entity: Entity, jumper: JumperComponent) {
        guard var sprite = world.component(ofType: SpriteComponent.self, for: entity) else { return }
        
        let frameName: String
        switch jumper.state {
        case .idle:
            frameName = "acorn_idle"
        case .jumping:
            frameName = "acorn_jump"
        case .falling:
            frameName = "acorn_fall"
        case .flyingJetpack:
            frameName = "acorn_jetpack"
        case .flyingPropeller:
            frameName = "acorn_propeller"
        case .shooting:
            frameName = "acorn_shoot"
        case .dead:
            frameName = "acorn_fall"
        case .victory:
            frameName = "acorn_jump"
        }
        
        if sprite.frameName != frameName {
            sprite.frameName = frameName
            sprite.isDirty = true
            world.addComponent(sprite, to: entity)
        }
    }
}
