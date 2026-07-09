import Foundation
import simd
import AcornEngine

/// Computes the visual 3D position for a given grid coordinate.
public func cellPosition(x: Int, y: Int) -> SIMD3<Float> {
    let tw: Float = 0.6
    let th: Float = 0.6
    let offsetX: Float = -Float(8) * tw * 0.5 + tw * 0.5
    let offsetY: Float = -Float(8) * th * 0.5 + th * 0.5
    return SIMD3<Float>(offsetX + Float(x) * tw, offsetY + Float(y) * th, 0.0)
}

/// The system that drives the board mechanics, animations, and match resolution.
@MainActor
public class BoardSystem: System {
    /// The sprite sheet used for spawning new acorns.
    private let spriteSheet: SpriteSheet
    
    /// Scale factor to make 256x256 sprites fit in cell sizes of 0.6 units.
    private let acornScale: Float = 0.00215
    
    /// Speed factor for sliding/falling animations.
    private let animationSpeed: Float = 6.0
    
    public init(spriteSheet: SpriteSheet) {
        self.spriteSheet = spriteSheet
    }
    
    public func update(world: World, deltaTime: Double) {
        // Find the board entity
        guard let boardTuple = world.entities(with: BoardComponent.self).first else { return }
        let boardEntity = boardTuple.0
        var board = boardTuple.1
        
        switch board.state {
        case .idle:
            // Check if game constraints are met (moves run out or target score reached)
            if board.movesRemaining <= 0 || board.score >= board.targetScore {
                board.state = .gameOver
                world.addComponent(board, to: boardEntity)
            }
            
        case .swapping(let entityA, let entityB, let revert):
            updateSwapAnimation(world: world, board: &board, entityA: entityA, entityB: entityB, revert: revert, deltaTime: deltaTime, boardEntity: boardEntity)
            
        case .checkingMatches:
            let matches = BoardSystem.findMatches(grid: board.grid, world: world)
            if !matches.isEmpty {
                // Mark matched components
                for entity in matches {
                    if var acorn = world.component(ofType: AcornComponent.self, for: entity) {
                        acorn.isMatched = true
                        acorn.matchScale = 1.0
                        world.addComponent(acorn, to: entity)
                    }
                }
                board.state = .clearingMatches
            } else {
                board.state = .idle
            }
            world.addComponent(board, to: boardEntity)
            
        case .clearingMatches:
            updateClearAnimation(world: world, board: &board, deltaTime: deltaTime, boardEntity: boardEntity)
            
        case .falling:
            updateFallingCascade(world: world, board: &board, deltaTime: deltaTime, boardEntity: boardEntity)
            
        case .gameOver:
            break
        }
    }
    
    // MARK: - Animation Updates
    
    private func updateSwapAnimation(world: World, board: inout BoardComponent, entityA: Entity, entityB: Entity, revert: Bool, deltaTime: Double, boardEntity: Entity) {
        guard var acornA = world.component(ofType: AcornComponent.self, for: entityA),
              var acornB = world.component(ofType: AcornComponent.self, for: entityB),
              var transformA = world.component(ofType: TransformComponent.self, for: entityA),
              var transformB = world.component(ofType: TransformComponent.self, for: entityB) else {
            // Revert state to idle if entities are missing
            board.state = .idle
            world.addComponent(board, to: boardEntity)
            return
        }
        
        // Progress animation
        let progress = min(1.0, acornA.moveProgress + Float(deltaTime) * animationSpeed)
        acornA.moveProgress = progress
        acornB.moveProgress = progress
        
        let startPosA = cellPosition(x: acornA.gridX, y: acornA.gridY)
        let endPosA = cellPosition(x: acornA.targetGridX, y: acornA.targetGridY)
        transformA.position = startPosA + (endPosA - startPosA) * progress
        
        let startPosB = cellPosition(x: acornB.gridX, y: acornB.gridY)
        let endPosB = cellPosition(x: acornB.targetGridX, y: acornB.targetGridY)
        transformB.position = startPosB + (endPosB - startPosB) * progress
        
        world.addComponent(acornA, to: entityA)
        world.addComponent(acornB, to: entityB)
        world.addComponent(transformA, to: entityA)
        world.addComponent(transformB, to: entityB)
        
        if progress >= 1.0 {
            // Animation finished!
            if revert {
                // Reverted swap finished, set to idle
                acornA.gridX = acornA.targetGridX
                acornA.gridY = acornA.targetGridY
                acornB.gridX = acornB.targetGridX
                acornB.gridY = acornB.targetGridY
                
                acornA.moveProgress = 1.0
                acornB.moveProgress = 1.0
                
                board.grid[acornA.gridX][acornA.gridY] = entityA
                board.grid[acornB.gridX][acornB.gridY] = entityB
                
                world.addComponent(acornA, to: entityA)
                world.addComponent(acornB, to: entityB)
                
                board.state = .idle
                world.addComponent(board, to: boardEntity)
            } else {
                // Normal swap finished, check matches
                acornA.gridX = acornA.targetGridX
                acornA.gridY = acornA.targetGridY
                acornB.gridX = acornB.targetGridX
                acornB.gridY = acornB.targetGridY
                
                acornA.moveProgress = 1.0
                acornB.moveProgress = 1.0
                
                board.grid[acornA.gridX][acornA.gridY] = entityA
                board.grid[acornB.gridX][acornB.gridY] = entityB
                
                world.addComponent(acornA, to: entityA)
                world.addComponent(acornB, to: entityB)
                
                let matches = BoardSystem.findMatches(grid: board.grid, world: world)
                if !matches.isEmpty {
                    board.state = .checkingMatches
                } else {
                    // Revert swap back
                    acornA.targetGridX = acornB.gridX
                    acornA.targetGridY = acornB.gridY
                    acornB.targetGridX = acornA.gridX
                    acornB.targetGridY = acornA.gridY
                    acornA.moveProgress = 0.0
                    acornB.moveProgress = 0.0
                    
                    world.addComponent(acornA, to: entityA)
                    world.addComponent(acornB, to: entityB)
                    
                    board.state = .swapping(entityA: entityA, entityB: entityB, revert: true)
                }
                world.addComponent(board, to: boardEntity)
            }
        }
    }
    
    private func updateClearAnimation(world: World, board: inout BoardComponent, deltaTime: Double, boardEntity: Entity) {
        var stillClearing = false
        
        let acorns = world.entities(with: AcornComponent.self)
        for (entity, var acorn) in acorns {
            if acorn.isMatched {
                let newScale = max(0.0, acorn.matchScale - Float(deltaTime) * 5.0)
                acorn.matchScale = newScale
                world.addComponent(acorn, to: entity)
                
                if var transform = world.component(ofType: TransformComponent.self, for: entity) {
                    transform.scale = SIMD3<Float>(repeating: acornScale * newScale)
                    world.addComponent(transform, to: entity)
                }
                
                if newScale > 0.0 {
                    stillClearing = true
                }
            }
        }
        
        if !stillClearing {
            // Remove matched entities and trigger cascade
            var matchedCount = 0
            for (entity, acorn) in acorns {
                if acorn.isMatched {
                    board.grid[acorn.gridX][acorn.gridY] = nil
                    world.destroyEntity(entity)
                    matchedCount += 1
                }
            }
            
            // Add score
            board.score += matchedCount * 100
            
            // Setup falling cascade
            setupCascade(world: world, board: &board)
            board.state = .falling
            world.addComponent(board, to: boardEntity)
        }
    }
    
    private func updateFallingCascade(world: World, board: inout BoardComponent, deltaTime: Double, boardEntity: Entity) {
        var stillFalling = false
        let acorns = world.entities(with: AcornComponent.self)
        
        for (entity, var acorn) in acorns {
            guard var transform = world.component(ofType: TransformComponent.self, for: entity) else { continue }
            
            if acorn.moveProgress < 1.0 {
                let progress = min(1.0, acorn.moveProgress + Float(deltaTime) * animationSpeed)
                acorn.moveProgress = progress
                
                let startPos = cellPosition(x: acorn.gridX, y: acorn.gridY)
                let endPos = cellPosition(x: acorn.targetGridX, y: acorn.targetGridY)
                transform.position = startPos + (endPos - startPos) * progress
                
                world.addComponent(acorn, to: entity)
                world.addComponent(transform, to: entity)
                
                if progress < 1.0 {
                    stillFalling = true
                }
            }
        }
        
        if !stillFalling {
            // Apply logical coordinates when cascade finishes
            for (entity, var acorn) in acorns {
                if acorn.gridX != acorn.targetGridX || acorn.gridY != acorn.targetGridY {
                    acorn.gridX = acorn.targetGridX
                    acorn.gridY = acorn.targetGridY
                    acorn.moveProgress = 1.0
                    board.grid[acorn.gridX][acorn.gridY] = entity
                    world.addComponent(acorn, to: entity)
                }
            }
            
            // Recheck matches
            board.state = .checkingMatches
            world.addComponent(board, to: boardEntity)
        }
    }
    
    // MARK: - Match Detection & Cascade Logic
    
    /// Checks for horizontal/vertical match chains.
    public static func findMatches(grid: [[Entity?]], world: World) -> Set<Entity> {
        var matchedEntities = Set<Entity>()
        
        // Horizontal matches
        for y in 0..<8 {
            var matchRun = [Entity]()
            var runColor: AcornColor? = nil
            
            for x in 0..<8 {
                if let entity = grid[x][y],
                   let acorn = world.component(ofType: AcornComponent.self, for: entity) {
                    if runColor == nil {
                        runColor = acorn.color
                        matchRun = [entity]
                    } else if acorn.color == runColor {
                        matchRun.append(entity)
                    } else {
                        if matchRun.count >= 3 {
                            matchedEntities.formUnion(matchRun)
                        }
                        runColor = acorn.color
                        matchRun = [entity]
                    }
                } else {
                    if matchRun.count >= 3 {
                        matchedEntities.formUnion(matchRun)
                    }
                    runColor = nil
                    matchRun = []
                }
            }
            if matchRun.count >= 3 {
                matchedEntities.formUnion(matchRun)
            }
        }
        
        // Vertical matches
        for x in 0..<8 {
            var matchRun = [Entity]()
            var runColor: AcornColor? = nil
            
            for y in 0..<8 {
                if let entity = grid[x][y],
                   let acorn = world.component(ofType: AcornComponent.self, for: entity) {
                    if runColor == nil {
                        runColor = acorn.color
                        matchRun = [entity]
                    } else if acorn.color == runColor {
                        matchRun.append(entity)
                    } else {
                        if matchRun.count >= 3 {
                            matchedEntities.formUnion(matchRun)
                        }
                        runColor = acorn.color
                        matchRun = [entity]
                    }
                } else {
                    if matchRun.count >= 3 {
                        matchedEntities.formUnion(matchRun)
                    }
                    runColor = nil
                    matchRun = []
                }
            }
            if matchRun.count >= 3 {
                matchedEntities.formUnion(matchRun)
            }
        }
        
        return matchedEntities
    }
    
    /// Prepares cascade falling coordinates for existing acorns and spawns new acorns.
    private func setupCascade(world: World, board: inout BoardComponent) {
        // 1. Shift existing acorns down
        for x in 0..<8 {
            var writeIndex = 0
            for y in 0..<8 {
                if let entity = board.grid[x][y] {
                    if writeIndex != y {
                        if var acorn = world.component(ofType: AcornComponent.self, for: entity) {
                            acorn.targetGridX = x
                            acorn.targetGridY = writeIndex
                            acorn.moveProgress = 0.0
                            world.addComponent(acorn, to: entity)
                        }
                        board.grid[x][writeIndex] = entity
                        board.grid[x][y] = nil
                    }
                    writeIndex += 1
                }
            }
            
            // 2. Spawn new acorns at the top of the column
            let emptyCount = 8 - writeIndex
            for i in 0..<emptyCount {
                let gridY = writeIndex + i
                let color = AcornColor.allCases.randomElement()!
                
                let entity = world.createEntity()
                var acorn = AcornComponent(color: color, gridX: x, gridY: 8 + i) // start above board
                acorn.targetGridX = x
                acorn.targetGridY = gridY
                acorn.moveProgress = 0.0
                
                // Spawn above the screen for a smooth fall
                let startPos = cellPosition(x: x, y: 8 + i)
                let transform = TransformComponent(
                    position: startPos,
                    scale: SIMD3<Float>(repeating: acornScale)
                )
                let sprite = SpriteComponent(spriteSheet: spriteSheet, frameName: color.frameName)
                
                world.addComponent(acorn, to: entity)
                world.addComponent(transform, to: entity)
                world.addComponent(sprite, to: entity)
                
                // Set target Y logically in grid (falling cascade will set grid reference)
                // Note: we don't set board.grid[x][gridY] = entity yet; the cascade update will do it.
            }
        }
    }
}
