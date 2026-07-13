import UIKit
import MetalKit
import AcornEngine
import simd

func writeLog(_ message: String) {
    let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let logUrl = docsDir.appendingPathComponent("game.log")
    if let data = (message + "\n").data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logUrl.path) {
            if let fileHandle = try? FileHandle(forWritingTo: logUrl) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            try? data.write(to: logUrl, options: .atomic)
        }
    }
}

class GameViewController: UIViewController, MTKViewDelegate {
    
    // MARK: - Engine Variables
    var engine: Engine!
    var renderer: MetalRenderer!
    var commandQueue: MTLCommandQueue!
    var lastRenderTime: CFTimeInterval = 0
    var boardEntity: Entity!
    
    // MARK: - HUD UI Elements
    var scoreLabel: UILabel!
    var movesLabel: UILabel!
    var targetLabel: UILabel!
    var gameOverLabel: UILabel!
    
    // MARK: - Sprite Sheets
    var spriteSheet: SpriteSheet!
    
    // MARK: - Layout Constants
    let cellWidth: Float = 0.6
    let cellHeight: Float = 0.6
    let acornScale: Float = 0.00215
    let tileScale: Float = 0.00234
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Clear previous log
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let logUrl = docsDir.appendingPathComponent("game.log")
        try? FileManager.default.removeItem(at: logUrl)
        
        writeLog("--- GAME STARTED LOGGING ---")
        
        setupHUD()
        
        guard let mtkView = view as? MTKView else {
            print("View of GameViewController is not an MTKView")
            return
        }
        
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported")
            return
        }
        
        mtkView.device = defaultDevice
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0.05, green: 0.1, blue: 0.15, alpha: 1.0)
        
        guard let queue = defaultDevice.makeCommandQueue() else {
            print("Failed to create command queue")
            return
        }
        self.commandQueue = queue
        
        do {
            self.renderer = try MetalRenderer(device: defaultDevice)
            self.engine = Engine(renderer: self.renderer)
            
            loadAssetsAndSetupGame()
            
            mtkView.delegate = self
            self.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        } catch {
            print("Failed to initialize Renderer: \(error)")
        }
    }
    
    private func setupHUD() {
        // Create HUD container stack view
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .equalSpacing
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stackView.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        scoreLabel = UILabel()
        scoreLabel.text = "Score: 0"
        scoreLabel.textColor = .white
        scoreLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        stackView.addArrangedSubview(scoreLabel)
        
        movesLabel = UILabel()
        movesLabel.text = "Moves: 20"
        movesLabel.textColor = .orange
        movesLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        stackView.addArrangedSubview(movesLabel)
        
        targetLabel = UILabel()
        targetLabel.text = "Target: 1000"
        targetLabel.textColor = .green
        targetLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        stackView.addArrangedSubview(targetLabel)
        
        gameOverLabel = UILabel()
        gameOverLabel.textColor = .red
        gameOverLabel.font = UIFont.systemFont(ofSize: 32, weight: .black)
        gameOverLabel.textAlignment = .center
        gameOverLabel.translatesAutoresizingMaskIntoConstraints = false
        gameOverLabel.isHidden = true
        view.addSubview(gameOverLabel)
        
        NSLayoutConstraint.activate([
            gameOverLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            gameOverLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func loadAssetsAndSetupGame() {
        guard let jsonUrl = Bundle.main.url(forResource: "acorns", withExtension: "json") else {
            print("Error: Could not find acorns.json in Bundle.")
            return
        }
        guard let pngUrl = Bundle.main.url(forResource: "acorns0", withExtension: "png") else {
            print("Error: Could not find acorns0.png in Bundle.")
            return
        }
        
        do {
            let textureLoader = TextureLoader(device: self.renderer.device)
            // Load asynchronously using a Task
            Task {
                do {
                    let texture = try await textureLoader.loadTexture(from: pngUrl)
                    let jsonData = try Data(contentsOf: jsonUrl)
                    let decoder = JSONDecoder()
                    let metadata = try decoder.decode(SpriteSheetMetadata.self, from: jsonData)
                    
                    self.spriteSheet = SpriteSheet(texture: texture, metadata: metadata)
                    
                    await MainActor.run {
                        setupGameScene()
                    }
                } catch {
                    print("Error loading sprite sheet assets: \(error)")
                }
            }
        }
    }
    
    private func setupGameScene() {
        writeLog("Successfully loaded assets. Starting setupGameScene.")
        // Register our BoardSystem
        let boardSystem = BoardSystem(spriteSheet: spriteSheet)
        engine.world.registerSystem(boardSystem)
        
        // Setup Camera Entity (Orthographic, size 2.5)
        let cameraEntity = engine.world.createEntity()
        let cameraTransform = TransformComponent(position: SIMD3<Float>(0, 0, -5.0))
        engine.world.addComponent(cameraTransform, to: cameraEntity)
        
        let cameraComponent = CameraComponent(
            projectionType: .orthographic,
            orthographicSize: 2.7,
            nearZ: 0.1,
            farZ: 100.0,
            aspectRatio: 1.0
        )
        engine.world.addComponent(cameraComponent, to: cameraEntity)
        
        // Setup Board Component
        boardEntity = engine.world.createEntity()
        var board = BoardComponent()
        board.score = 0
        board.movesRemaining = 20
        board.targetScore = 1000
        
        // Spawn Background Grid Tiles
        for x in 0..<8 {
            for y in 0..<8 {
                let tileEntity = engine.world.createEntity()
                var pos = cellPosition(x: x, y: y)
                pos.z = -0.5 // Place behind acorns
                let transform = TransformComponent(
                    position: pos,
                    scale: SIMD3<Float>(repeating: tileScale)
                )
                let sprite = SpriteComponent(spriteSheet: spriteSheet, frameName: "tile_bg")
                engine.world.addComponent(transform, to: tileEntity)
                engine.world.addComponent(sprite, to: tileEntity)
            }
        }
        
        // Spawn Initial Acorns ensuring NO immediate matches
        var colors = Array(repeating: Array(repeating: AcornColor.red, count: 8), count: 8)
        for x in 0..<8 {
            for y in 0..<8 {
                var color: AcornColor
                repeat {
                    color = AcornColor.allCases.randomElement()!
                } while (x >= 2 && colors[x - 1][y] == color && colors[x - 2][y] == color) ||
                        (y >= 2 && colors[x][y - 1] == color && colors[x][y - 2] == color)
                
                colors[x][y] = color
                
                let acornEntity = engine.world.createEntity()
                let pos = cellPosition(x: x, y: y)
                let transform = TransformComponent(
                    position: pos,
                    scale: SIMD3<Float>(repeating: acornScale)
                )
                let sprite = SpriteComponent(spriteSheet: spriteSheet, frameName: color.frameName)
                let acorn = AcornComponent(color: color, gridX: x, gridY: y)
                
                engine.world.addComponent(transform, to: acornEntity)
                engine.world.addComponent(sprite, to: acornEntity)
                engine.world.addComponent(acorn, to: acornEntity)
                
                board.grid[x][y] = acornEntity
                writeLog("Spawned acorn at (\(x), \(y)) - Entity ID: \(acornEntity.id) - Color: \(color)")
            }
        }
        
        engine.world.addComponent(board, to: boardEntity)
        writeLog("Successfully set up board component on Board Entity ID: \(boardEntity.id)")
        
        // Setup Tap Gesture Recognizer for touch inputs
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tapGesture)
    }
    
    // MARK: - Input Handling
    
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let boardTuple = engine.world.entities(with: BoardComponent.self).first else { return }
        let boardEntity = boardTuple.0
        var board = boardTuple.1
        
        // Ignore inputs if board is locked or game is over
        if board.isLocked || board.state == .gameOver { return }
        
        let touchPoint = gesture.location(in: view)
        let bounds = view.bounds
        
        // Normalize screen coordinates to [-1, 1]
        let px = Float((touchPoint.x / bounds.width) * 2.0 - 1.0)
        let py = Float((1.0 - touchPoint.y / bounds.height) * 2.0 - 1.0)
        
        // Get camera details for projection mapping
        guard let cameraTuple = engine.world.entities(with: CameraComponent.self).first else { return }
        let camera = cameraTuple.1
        let aspect = camera.aspectRatio
        let orthoSize = camera.orthographicSize
        
        // Convert screen coordinates to world coordinates
        let worldX = px * orthoSize * aspect
        let worldY = py * orthoSize
        
        // Find which column & row was tapped
        let tw: Float = 0.6
        let th: Float = 0.6
        let offsetX: Float = -Float(8) * tw * 0.5 + tw * 0.5
        let offsetY: Float = -Float(8) * th * 0.5 + th * 0.5
        
        let col = Int(round((worldX - offsetX) / tw))
        let row = Int(round((worldY - offsetY) / th))
        
        // Check if tap was within grid bounds
        if col >= 0 && col < 8 && row >= 0 && row < 8 {
            if let tappedEntity = board.grid[col][row] {
                if let selected = board.selectedAcorn {
                    if selected == tappedEntity {
                        // De-select if tapped again
                        deselectAcorn(selected)
                        board.selectedAcorn = nil
                    } else {
                        // Check if adjacent
                        if let selectedAcornComp = engine.world.component(ofType: AcornComponent.self, for: selected),
                           let tappedAcornComp = engine.world.component(ofType: AcornComponent.self, for: tappedEntity) {
                            
                            let dx = abs(selectedAcornComp.gridX - tappedAcornComp.gridX)
                            let dy = abs(selectedAcornComp.gridY - tappedAcornComp.gridY)
                            
                            if (dx == 1 && dy == 0) || (dx == 0 && dy == 1) {
                                // Swap acorns!
                                deselectAcorn(selected)
                                initiateSwap(world: engine.world, board: &board, entityA: selected, entityB: tappedEntity, boardEntity: boardEntity)
                                board.selectedAcorn = nil
                            } else {
                                // Swap selection to the new acorn
                                deselectAcorn(selected)
                                selectAcorn(tappedEntity)
                                board.selectedAcorn = tappedEntity
                            }
                        }
                    }
                } else {
                    // First selection
                    selectAcorn(tappedEntity)
                    board.selectedAcorn = tappedEntity
                }
                engine.world.addComponent(board, to: boardEntity)
            }
        }
    }
    
    private func selectAcorn(_ entity: Entity) {
        if var sprite = engine.world.component(ofType: SpriteComponent.self, for: entity) {
            sprite.color = SIMD4<Float>(0.6, 0.6, 0.6, 1.0) // Darken when selected
            sprite.isDirty = true
            engine.world.addComponent(sprite, to: entity)
        }
    }
    
    private func deselectAcorn(_ entity: Entity) {
        if var sprite = engine.world.component(ofType: SpriteComponent.self, for: entity) {
            sprite.color = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
            sprite.isDirty = true
            engine.world.addComponent(sprite, to: entity)
        }
    }
    
    private func initiateSwap(world: World, board: inout BoardComponent, entityA: Entity, entityB: Entity, boardEntity: Entity) {
        guard var acornA = world.component(ofType: AcornComponent.self, for: entityA),
              var acornB = world.component(ofType: AcornComponent.self, for: entityB) else { return }
        
        // Decrement moves remaining
        board.movesRemaining -= 1
        
        // Setup movement targets
        acornA.targetGridX = acornB.gridX
        acornA.targetGridY = acornB.gridY
        acornA.moveProgress = 0.0
        
        acornB.targetGridX = acornA.gridX
        acornB.targetGridY = acornA.gridY
        acornB.moveProgress = 0.0
        
        world.addComponent(acornA, to: entityA)
        world.addComponent(acornB, to: entityB)
        
        board.state = .swapping(entityA: entityA, entityB: entityB, revert: false)
    }
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard let engine = engine else { return }
        let aspect = Float(max(size.width, 1.0) / max(size.height, 1.0))
        
        if let cameraTuple = engine.world.entities(with: CameraComponent.self).first {
            let entityId = cameraTuple.0
            var camera = cameraTuple.1
            camera.aspectRatio = aspect
            engine.world.addComponent(camera, to: entityId)
        }
    }
    
    func draw(in view: MTKView) {
        guard let engine = engine,
              let commandQueue = commandQueue,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        let currentTime = CACurrentMediaTime()
        let deltaTime = lastRenderTime == 0 ? 0.016 : currentTime - lastRenderTime
        lastRenderTime = currentTime
        
        // Tick ECS World & Update Systems
        engine.tick(deltaTime: deltaTime)
        
        // Update UI HUD Text overlays
        updateHUDLabels()
        
        // Render Frame
        let context = MetalRenderContext(renderPassDescriptor: descriptor, commandBuffer: commandBuffer)
        _ = context.getOrCreateEncoder()
        
        engine.render(context: context)
        context.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private func updateHUDLabels() {
        guard let boardTuple = engine.world.entities(with: BoardComponent.self).first else { return }
        let board = boardTuple.1
        
        scoreLabel.text = "Score: \(board.score)"
        movesLabel.text = "Moves: \(board.movesRemaining)"
        targetLabel.text = "Target: \(board.targetScore)"
        
        if board.state == .gameOver {
            gameOverLabel.isHidden = false
            if board.score >= board.targetScore {
                gameOverLabel.text = "VICTORY!\nLevel Cleared"
                gameOverLabel.textColor = .green
            } else {
                gameOverLabel.text = "GAME OVER\nOut of moves"
                gameOverLabel.textColor = .red
            }
        } else {
            gameOverLabel.isHidden = true
        }
    }
}
