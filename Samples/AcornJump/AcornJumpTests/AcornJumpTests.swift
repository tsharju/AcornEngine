import Foundation
import Testing
import simd
import AcornEngine
@testable import AcornJump

@Suite("Level Generator & 100-Level Campaign Tests")
@MainActor
struct LevelGeneratorTests {
    
    @Test("Verify all 100 levels generate with valid layout and finish lines")
    func testAll100LevelsGeneration() {
        for level in 1...100 {
            let blueprint = LevelGenerator.generateCampaignLevel(level: level)
            
            // Basic validity checks
            #expect(blueprint.definition.levelNumber == level)
            #expect(blueprint.finishY >= 40.0)
            #expect(!blueprint.platforms.isEmpty)
            #expect(blueprint.platforms.count >= 15)
            
            // First platform should be near origin
            if let firstPlat = blueprint.platforms.first {
                #expect(abs(firstPlat.position.x) <= 2.5)
                #expect(firstPlat.position.y <= 2.5)
            }
            
            // Collectibles: should have 3 stars
            let stars = blueprint.collectibles.filter {
                if case .star = $0.type { return true }
                return false
            }
            #expect(stars.count == 3)
            
            // Golden acorns present
            let acorns = blueprint.collectibles.filter {
                if case .goldenAcorn = $0.type { return true }
                return false
            }
            #expect(acorns.count >= 3)
        }
    }
    
    @Test("Verify 10 Thematic Zones cover all 100 levels accurately")
    func testZoneProgression() {
        #expect(ZoneTheme.zone(for: 1) == .forestFloor)
        #expect(ZoneTheme.zone(for: 10) == .forestFloor)
        #expect(ZoneTheme.zone(for: 11) == .mossyBarks)
        #expect(ZoneTheme.zone(for: 20) == .mossyBarks)
        #expect(ZoneTheme.zone(for: 25) == .autumnCanopy)
        #expect(ZoneTheme.zone(for: 35) == .breezyBranches)
        #expect(ZoneTheme.zone(for: 45) == .pineNeedleHollow)
        #expect(ZoneTheme.zone(for: 55) == .mushroomKingdom)
        #expect(ZoneTheme.zone(for: 65) == .twilightTreetops)
        #expect(ZoneTheme.zone(for: 75) == .stormyCanopy)
        #expect(ZoneTheme.zone(for: 85) == .ancientRedwoods)
        #expect(ZoneTheme.zone(for: 95) == .worldTreeApex)
        #expect(ZoneTheme.zone(for: 100) == .worldTreeApex)
    }
    
    @Test("Verify Endless Chunk Generator produces scaling difficulty chunks")
    func testEndlessChunkGeneration() {
        let chunk1 = LevelGenerator.generateEndlessChunk(fromY: 0.0, toY: 50.0, currentScore: 0, seed: 100)
        #expect(!chunk1.platforms.isEmpty)
        #expect(chunk1.finishY == 50.0)
        
        let chunk2 = LevelGenerator.generateEndlessChunk(fromY: 50.0, toY: 100.0, currentScore: 15000, seed: 100)
        #expect(!chunk2.platforms.isEmpty)
        #expect(chunk2.finishY == 100.0)
    }
}

@Suite("Game Progress Persistence Tests")
@MainActor
struct GameProgressManagerTests {
    
    @Test("Verify save, progression unlocking, stars, and high scores")
    func testProgressManagerWorkflow() {
        let mgr = GameProgressManager.shared
        mgr.resetProgress()
        
        #expect(mgr.highestUnlockedLevel == 1)
        #expect(mgr.isUnlocked(level: 1))
        #expect(!mgr.isUnlocked(level: 2))
        #expect(mgr.stars(for: 1) == 0)
        #expect(mgr.highScore(for: 1) == 0)
        
        // Complete Level 1 with 3 stars and 500 score
        let result1 = mgr.recordCampaignResult(level: 1, score: 500, stars: 3, acornsCollected: 5)
        #expect(result1.isNewBestScore)
        #expect(result1.isNewStarsRecord)
        #expect(mgr.highestUnlockedLevel == 2)
        #expect(mgr.isUnlocked(level: 2))
        #expect(mgr.stars(for: 1) == 3)
        #expect(mgr.highScore(for: 1) == 500)
        #expect(mgr.totalGoldenAcorns == 5)
        
        // Play Level 1 again with lower score - should not overwrite high score
        let result2 = mgr.recordCampaignResult(level: 1, score: 300, stars: 2, acornsCollected: 2)
        #expect(!result2.isNewBestScore)
        #expect(!result2.isNewStarsRecord)
        #expect(mgr.highScore(for: 1) == 500)
        #expect(mgr.stars(for: 1) == 3)
        #expect(mgr.totalGoldenAcorns == 7)
        
        // Endless Mode score record
        let isNewEndless = mgr.recordEndlessResult(score: 2500, acornsCollected: 10)
        #expect(isNewEndless)
        #expect(mgr.endlessHighScore == 2500)
        #expect(mgr.totalGoldenAcorns == 17)
        
        // Spending Acorns
        #expect(mgr.spendAcorns(10))
        #expect(mgr.totalGoldenAcorns == 7)
        #expect(!mgr.spendAcorns(100)) // Not enough
    }
}

@Suite("Jumper Physics & ECS Mechanics Tests")
@MainActor
struct JumperPhysicsTests {
    
    @Test("Verify Jumper Component initial defaults and powerup types")
    func testJumperDefaults() {
        var jumper = JumperComponent(isCampaign: true, levelNumber: 5, targetLevelHeight: 120.0)
        #expect(jumper.velocity.y == 13.5)
        #expect(jumper.isAlive)
        #expect(!jumper.hasReachedFinish)
        #expect(jumper.screenWrapBounds == 3.2)
        #expect(jumper.maxHorizontalSpeed == 6.8)
        #expect(jumper.horizontalAcceleration == 30.0)
        #expect(jumper.horizontalDeceleration == 26.0)
        
        jumper.activePowerup = .jetpack(duration: 5.0)
        #expect(jumper.activePowerup == .jetpack(duration: 5.0))
        #expect(jumper.activePowerup?.frameName == "powerup_jetpack")
        
        jumper.activePowerup = .propeller(duration: 6.0)
        #expect(jumper.activePowerup?.frameName == "powerup_propeller")
    }
    
    @Test("Verify Platform and Monster frame mappings and properties")
    func testPlatformAndMonsterProperties() {
        let wood = PlatformComponent(type: .wood)
        #expect(wood.type.frameName == "platform_wood")
        
        let leaf = PlatformComponent(type: .leaf)
        #expect(leaf.type.frameName == "platform_leaf")
        
        let spring = PlatformComponent(type: .spring(isCompressed: false, cooldown: 0.0))
        #expect(spring.type.frameName == "platform_spring_idle")
        
        let spider = MonsterComponent(type: .spider(amplitude: 1.0, speed: 1.0, startX: 0.0, phase: 0.0))
        #expect(spider.type.frameName == "monster_spider")
        #expect(spider.type.scoreValue == 200)
        
        let bat = MonsterComponent(type: .bat(frequency: 1.0, amplitude: 1.0, time: 0.0, startX: 0.0))
        #expect(bat.type.frameName == "monster_bat")
        #expect(bat.type.scoreValue == 300)
    }
}
