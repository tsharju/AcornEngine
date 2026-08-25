import Foundation
import simd
import AcornEngine

/// System that tracks the player's vertical progress, scrolls the camera upwards smoothly, and enforces death boundaries.
@MainActor
public final class CameraFollowSystem: System {
    
    /// Highest camera position reached.
    public private(set) var highestCameraY: Float = 0.0
    
    /// Offset below highest camera point where falling triggers game over.
    public var deathThresholdOffset: Float = 5.8
    
    /// Callback for endless mode chunk spawning.
    public var onEndlessNeedChunk: ((_ fromY: Float, _ toY: Float) -> Void)?
    private var lastGeneratedEndlessY: Float = 60.0
    
    public init() {}
    
    public func reset(initialY: Float = 0.0) {
        highestCameraY = initialY
        lastGeneratedEndlessY = initialY + 60.0
    }
    
    public func update(world: World, deltaTime: Double) {
        let dt = Float(deltaTime)
        guard dt > 0 else { return }
        
        let jumpers = world.entities(with: JumperComponent.self)
        guard let (jumperEntity, jumperComp) = jumpers.first,
              let jumperTransform = world.component(ofType: TransformComponent.self, for: jumperEntity),
              let (cameraEntity, _) = world.entities(with: CameraComponent.self).first,
              var cameraTransform = world.component(ofType: TransformComponent.self, for: cameraEntity) else {
            return
        }
        
        var jumper = jumperComp
        
        // 1. Follow player smoothly upward (never scroll down)
        let targetY = max(highestCameraY, jumperTransform.position.y - 0.4)
        highestCameraY = targetY
        
        let followSpeed: Float = jumper.velocity.y > 0 ? 14.0 : 8.0
        cameraTransform.position.y = simd_mix(cameraTransform.position.y, highestCameraY, min(1.0, followSpeed * dt))
        cameraTransform.position.x = 0.0
        
        world.addComponent(cameraTransform, to: cameraEntity)
        
        // 2. Check Falling Death Boundary
        let deathFloor = highestCameraY - deathThresholdOffset
        if jumper.isAlive && !jumper.hasReachedFinish && jumperTransform.position.y < deathFloor {
            jumper.isAlive = false
            jumper.state = .dead
            SoundManager.shared.playGameOver()
            world.addComponent(jumper, to: jumperEntity)
        }
        
        // 3. Clean up off-screen entities far below camera
        let cleanupY = highestCameraY - 7.5
        
        let platforms = world.entities(with: PlatformComponent.self)
        for (platEntity, _) in platforms {
            if let pTransform = world.component(ofType: TransformComponent.self, for: platEntity),
               pTransform.position.y < cleanupY {
                world.destroyEntity(platEntity)
            }
        }
        
        let monsters = world.entities(with: MonsterComponent.self)
        for (monsterEntity, _) in monsters {
            if let mTransform = world.component(ofType: TransformComponent.self, for: monsterEntity),
               mTransform.position.y < cleanupY {
                world.destroyEntity(monsterEntity)
            }
        }
        
        let collectibles = world.entities(with: CollectibleComponent.self)
        for (collEntity, _) in collectibles {
            if let cTransform = world.component(ofType: TransformComponent.self, for: collEntity),
               cTransform.position.y < cleanupY {
                world.destroyEntity(collEntity)
            }
        }
        
        // 4. Endless chunk spawning
        if !jumper.isCampaign && highestCameraY + 30.0 > lastGeneratedEndlessY {
            let nextToY = lastGeneratedEndlessY + 60.0
            onEndlessNeedChunk?(lastGeneratedEndlessY, nextToY)
            lastGeneratedEndlessY = nextToY
        }
    }
}
