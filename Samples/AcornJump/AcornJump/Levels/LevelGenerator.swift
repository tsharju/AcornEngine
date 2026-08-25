import Foundation
import simd

/// Spawn descriptor for a platform entity.
public struct PlatformSpawnData: Sendable {
    public var position: SIMD3<Float>
    public var type: PlatformType
    public var width: Float
    public var height: Float
    
    public init(position: SIMD3<Float>, type: PlatformType, width: Float = 1.2, height: Float = 0.3) {
        self.position = position
        self.type = type
        self.width = width
        self.height = height
    }
}

/// Spawn descriptor for a monster hazard.
public struct MonsterSpawnData: Sendable {
    public var position: SIMD3<Float>
    public var type: MonsterType
    
    public init(position: SIMD3<Float>, type: MonsterType) {
        self.position = position
        self.type = type
    }
}

/// Spawn descriptor for a collectible item.
public struct CollectibleSpawnData: Sendable {
    public var position: SIMD3<Float>
    public var type: CollectibleType
    
    public init(position: SIMD3<Float>, type: CollectibleType) {
        self.position = position
        self.type = type
    }
}

/// A complete level blueprint ready to be instantiated in the ECS World.
public struct LevelBlueprint: Sendable {
    public var definition: LevelDefinition
    public var platforms: [PlatformSpawnData]
    public var monsters: [MonsterSpawnData]
    public var collectibles: [CollectibleSpawnData]
    public var finishY: Float
    
    public init(
        definition: LevelDefinition,
        platforms: [PlatformSpawnData] = [],
        monsters: [MonsterSpawnData] = [],
        collectibles: [CollectibleSpawnData] = [],
        finishY: Float = 100.0
    ) {
        self.definition = definition
        self.platforms = platforms
        self.monsters = monsters
        self.collectibles = collectibles
        self.finishY = finishY
    }
}

/// Seeded pseudo-random number generator for deterministic procedural level generation.
public struct SeededRandomGenerator: Sendable {
    private var state: UInt64
    
    public init(seed: UInt64) {
        self.state = seed == 0 ? 0x853c49e6748fea9b : seed
    }
    
    public mutating func nextUInt64() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
    
    public mutating func nextFloat() -> Float {
        let val = Float(nextUInt64() & 0xFFFFFF)
        return val / Float(0xFFFFFF)
    }
    
    public mutating func nextFloat(in range: ClosedRange<Float>) -> Float {
        return range.lowerBound + nextFloat() * (range.upperBound - range.lowerBound)
    }
    
    public mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        let f = nextFloat()
        return range.lowerBound + Int(f * Float(range.upperBound - range.lowerBound + 1))
    }
}

/// Procedural level generator creating 100 balanced campaign levels and endless climb chunks.
public struct LevelGenerator: Sendable {
    
    /// Generates a complete campaign level given its level number (1...100).
    public static func generateCampaignLevel(level: Int) -> LevelBlueprint {
        let def = LevelDefinition.definition(for: level)
        var rng = SeededRandomGenerator(seed: UInt64(level) * 1337 + 42)
        
        var platforms: [PlatformSpawnData] = []
        var monsters: [MonsterSpawnData] = []
        var collectibles: [CollectibleSpawnData] = []
        
        // 1. Initial starting platform directly under the player
        platforms.append(PlatformSpawnData(
            position: SIMD3<Float>(0.0, 0.0, 0.0),
            type: .wood,
            width: 1.8,
            height: 0.3
        ))
        
        // Add a safety platform to the left and right at the bottom
        platforms.append(PlatformSpawnData(
            position: SIMD3<Float>(-1.4, 0.8, 0.0),
            type: .wood,
            width: 1.3,
            height: 0.3
        ))
        platforms.append(PlatformSpawnData(
            position: SIMD3<Float>(1.4, 0.8, 0.0),
            type: .wood,
            width: 1.3,
            height: 0.3
        ))
        
        var currentY: Float = 1.6
        var lastX: Float = 0.0
        
        // 3 Stars heights (at 25%, 50%, and 75% of level height)
        let starHeights: [Float] = [
            def.targetHeight * 0.25,
            def.targetHeight * 0.50,
            def.targetHeight * 0.75
        ]
        var starsPlaced = 0
        
        // Golden acorns target placement intervals
        let acornInterval = def.targetHeight / Float(max(1, def.goldenAcornsCount))
        var nextAcornY = acornInterval * 0.8
        
        // Ascend upward to target height
        while currentY < def.targetHeight {
            let dy = rng.nextFloat(in: def.platformSpacingMin...def.platformSpacingMax)
            currentY += dy
            
            // X position with maximum reach from last platform
            let maxReachX: Float = 2.4
            let minX = max(-2.4, lastX - maxReachX)
            let maxX = min(2.4, lastX + maxReachX)
            let posX = rng.nextFloat(in: minX...maxX)
            lastX = posX
            
            // Determine platform type based on probabilities
            let roll = rng.nextFloat()
            let pType: PlatformType
            
            if roll < def.springRatio {
                pType = .spring(isCompressed: false, cooldown: 0.0)
            } else if roll < def.springRatio + def.movingHorizontalRatio {
                let range = rng.nextFloat(in: 1.0...2.2)
                let speed = rng.nextFloat(in: 1.2...2.6)
                pType = .movingHorizontal(amplitude: range, speed: speed, startX: posX, phase: rng.nextFloat(in: 0...Float.pi * 2))
            } else if roll < def.springRatio + def.movingHorizontalRatio + def.movingVerticalRatio {
                let range = rng.nextFloat(in: 0.8...1.5)
                let speed = rng.nextFloat(in: 1.0...2.0)
                pType = .movingVertical(amplitude: range, speed: speed, startY: currentY, phase: rng.nextFloat(in: 0...Float.pi * 2))
            } else if roll < def.springRatio + def.movingHorizontalRatio + def.movingVerticalRatio + def.breakingRatio {
                pType = .breaking(isBroken: false, breakProgress: 0.0)
            } else if roll < def.springRatio + def.movingHorizontalRatio + def.movingVerticalRatio + def.breakingRatio + def.disappearingRatio {
                pType = .disappearing(lifetime: 0.8, isTriggered: false)
            } else {
                pType = def.zone == .mossyBarks || def.zone == .mushroomKingdom ? .leaf : .wood
            }
            
            let platformWidth: Float = def.zone.rawValue >= 7 ? 1.0 : 1.3
            platforms.append(PlatformSpawnData(
                position: SIMD3<Float>(posX, currentY, 0.0),
                type: pType,
                width: platformWidth,
                height: 0.3
            ))
            
            // Check if we should place a Star above this platform
            if starsPlaced < 3 && currentY >= starHeights[starsPlaced] {
                collectibles.append(CollectibleSpawnData(
                    position: SIMD3<Float>(posX, currentY + 0.65, 0.0),
                    type: .star(index: starsPlaced + 1)
                ))
                starsPlaced += 1
            }
            // Check if we should place a Golden Acorn
            else if currentY >= nextAcornY && currentY < def.targetHeight - 5.0 {
                collectibles.append(CollectibleSpawnData(
                    position: SIMD3<Float>(posX, currentY + 0.55, 0.0),
                    type: .goldenAcorn
                ))
                nextAcornY += acornInterval
            }
            // Check for Powerup placement
            else if rng.nextFloat() < def.powerupSpawnChance && currentY > 10.0 && currentY < def.targetHeight - 10.0 {
                let pRoll = rng.nextFloat()
                let powerType: PowerupType
                if pRoll < 0.35 {
                    powerType = .propeller(duration: 6.0)
                } else if pRoll < 0.60 {
                    powerType = .shield(charges: 1)
                } else if pRoll < 0.85 {
                    powerType = .springShoes(jumpsRemaining: 4)
                } else {
                    powerType = .jetpack(duration: 5.0)
                }
                collectibles.append(CollectibleSpawnData(
                    position: SIMD3<Float>(posX, currentY + 0.55, 0.0),
                    type: .powerup(powerType)
                ))
            }
            // Check for Monster placement (placed higher up between platform lanes)
            else if rng.nextFloat() < def.monsterSpawnChance && currentY > 15.0 && currentY < def.targetHeight - 8.0 {
                let mRoll = rng.nextFloat()
                let monsterType: MonsterType
                let monsterX = rng.nextFloat(in: -2.0...2.0)
                let monsterY = currentY + rng.nextFloat(in: 1.0...1.6)
                
                if mRoll < 0.35 {
                    monsterType = .spider(amplitude: 1.2, speed: 1.8, startX: monsterX, phase: 0.0)
                } else if mRoll < 0.65 {
                    monsterType = .bat(frequency: 2.0, amplitude: 0.8, time: 0.0, startX: monsterX)
                } else if mRoll < 0.85 {
                    monsterType = .chestnut(bounceSpeed: 2.5, startY: monsterY)
                } else {
                    monsterType = .blackhole(pullRadius: 1.8, pullForce: 3.5)
                }
                
                monsters.append(MonsterSpawnData(
                    position: SIMD3<Float>(monsterX, monsterY, 0.0),
                    type: monsterType
                ))
            }
        }
        
        // 2. Add final Victory platform and Finish Banner at targetHeight
        platforms.append(PlatformSpawnData(
            position: SIMD3<Float>(0.0, def.targetHeight, 0.0),
            type: .wood,
            width: 2.4,
            height: 0.4
        ))
        
        return LevelBlueprint(
            definition: def,
            platforms: platforms,
            monsters: monsters,
            collectibles: collectibles,
            finishY: def.targetHeight
        )
    }
    
    /// Generates a chunk of platforms and items for Endless Mode.
    public static func generateEndlessChunk(fromY: Float, toY: Float, currentScore: Int, seed: UInt64) -> LevelBlueprint {
        var rng = SeededRandomGenerator(seed: seed ^ UInt64(fromY * 100))
        let difficulty = min(1.0, Float(currentScore) / 25000.0) // scales up to 25k points
        
        let spacingMin = 1.2 + difficulty * 0.4
        let spacingMax = 1.9 + difficulty * 0.7
        
        var platforms: [PlatformSpawnData] = []
        var monsters: [MonsterSpawnData] = []
        var collectibles: [CollectibleSpawnData] = []
        
        var currentY = fromY
        var lastX: Float = 0.0
        
        while currentY < toY {
            let dy = rng.nextFloat(in: spacingMin...spacingMax)
            currentY += dy
            
            let posX = rng.nextFloat(in: -2.3...2.3)
            lastX = posX
            
            let roll = rng.nextFloat()
            let pType: PlatformType
            
            let springRatio: Float = 0.10
            let movingRatio: Float = 0.15 + difficulty * 0.20
            let breakingRatio: Float = 0.10 + difficulty * 0.20
            let dispRatio: Float = 0.05 + difficulty * 0.15
            
            if roll < springRatio {
                pType = .spring(isCompressed: false, cooldown: 0.0)
            } else if roll < springRatio + movingRatio {
                pType = .movingHorizontal(amplitude: 1.5, speed: 1.8, startX: posX, phase: rng.nextFloat(in: 0...6.28))
            } else if roll < springRatio + movingRatio + breakingRatio {
                pType = .breaking(isBroken: false, breakProgress: 0.0)
            } else if roll < springRatio + movingRatio + breakingRatio + dispRatio {
                pType = .disappearing(lifetime: 0.8, isTriggered: false)
            } else {
                pType = .wood
            }
            
            platforms.append(PlatformSpawnData(
                position: SIMD3<Float>(posX, currentY, 0.0),
                type: pType,
                width: 1.2,
                height: 0.3
            ))
            
            // Random Golden Acorn
            if rng.nextFloat() < 0.25 {
                collectibles.append(CollectibleSpawnData(
                    position: SIMD3<Float>(posX, currentY + 0.55, 0.0),
                    type: .goldenAcorn
                ))
            }
            // Random Powerup
            else if rng.nextFloat() < 0.08 {
                let pRoll = rng.nextFloat()
                let power: PowerupType = pRoll < 0.4 ? .propeller(duration: 6.0) : (pRoll < 0.7 ? .shield(charges: 1) : .jetpack(duration: 5.0))
                collectibles.append(CollectibleSpawnData(
                    position: SIMD3<Float>(posX, currentY + 0.55, 0.0),
                    type: .powerup(power)
                ))
            }
            // Random Monster
            else if rng.nextFloat() < (0.08 + difficulty * 0.16) {
                let mX = rng.nextFloat(in: -2.0...2.0)
                let mY = currentY + rng.nextFloat(in: 0.8...1.4)
                monsters.append(MonsterSpawnData(
                    position: SIMD3<Float>(mX, mY, 0.0),
                    type: .spider(amplitude: 1.2, speed: 1.5, startX: mX, phase: 0.0)
                ))
            }
        }
        
        let dummyDef = LevelDefinition.definition(for: 1)
        return LevelBlueprint(
            definition: dummyDef,
            platforms: platforms,
            monsters: monsters,
            collectibles: collectibles,
            finishY: toY
        )
    }
}
