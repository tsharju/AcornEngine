import UIKit
import MetalKit
import AcornEngine
import CoreMotion
import simd

/// The gameplay and lifecycle states for Acorn Jump.
public enum GameState: Equatable, Sendable {
    case mainMenu
    case levelSelect
    case playing(isCampaign: Bool, level: Int)
    case paused
    case victory(level: Int, score: Int, stars: Int, acorns: Int)
    case gameOver(height: Float, score: Int, acorns: Int)
}

/// The main View Controller managing Metal rendering, the AcornEngine ECS, motion/touch gesture controls, and UI overlays.
@MainActor
public class GameViewController: UIViewController, MTKViewDelegate {
    
    // MARK: - Engine Properties
    private var engine: Engine!
    private var renderer: MetalRenderer!
    private var commandQueue: MTLCommandQueue!
    private var lastRenderTime: CFTimeInterval = 0
    
    // MARK: - Systems
    private var jumperSystem: JumperSystem!
    private var platformSystem: PlatformSystem!
    private var monsterSystem: MonsterSystem!
    private var projectileSystem: ProjectileSystem!
    private var cameraFollowSystem: CameraFollowSystem!
    
    // MARK: - Motion & Controls
    private let motionManager = CMMotionManager()
    private var filteredTilt: Float = 0.0
    private var touchStartPoint: CGPoint = .zero
    private var touchStartTime: CFTimeInterval = 0
    private var currentTouchSteering: Float? = nil
    
    // MARK: - Assets
    private var spriteSheet: SpriteSheet!
    private var isAssetsLoaded: Bool = false
    
    // MARK: - Entities
    private var playerEntity: Entity?
    private var cameraEntity: Entity?
    
    // MARK: - State & Mode
    private var gameState: GameState = .mainMenu
    private var activeLevelNumber: Int = 1
    private var isCampaignMode: Bool = true
    private var endlessSeed: UInt64 = 42
    
    // MARK: - Scale Constants
    private let playerScale: Float = 0.0032
    private let platformScale: Float = 0.0048
    private let monsterScale: Float = 0.0035
    private let itemScale: Float = 0.0035
    private let bannerScale: Float = 0.0055
    
    // MARK: - UI Overlays
    private var mainMenuOverlay: MainMenuOverlay!
    private var levelSelectOverlay: LevelSelectOverlay!
    private var hudOverlay: GameHUDOverlay!
    private var victoryOverlay: VictoryOverlay!
    private var gameOverOverlay: GameOverOverlay!
    
    public override func loadView() {
        let mtkView = MTKView()
        self.view = mtkView
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor(red: 0.08, green: 0.16, blue: 0.12, alpha: 1.0)
        
        setupMetal()
        setupMotion()
        setupOverlays()
        loadAssets()
        
        // Handle test flags for simulator verification
        if CommandLine.arguments.contains("--test-level-select") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.openLevelSelect()
            }
        } else if CommandLine.arguments.contains("--test-gameplay") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startCampaignLevel(1)
            }
        } else if CommandLine.arguments.contains("--test-victory") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startCampaignLevel(1)
                self?.victoryOverlay.configure(level: 1, score: 850, stars: 3, acorns: 8, isNewBest: true)
                self?.victoryOverlay.isHidden = false
                self?.hudOverlay.isHidden = true
            }
        } else if CommandLine.arguments.contains("--test-gameover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startCampaignLevel(1)
                self?.gameOverOverlay.configure(height: 38.0, score: 420, acorns: 3, isNewBest: true, isCampaign: true)
                self?.gameOverOverlay.isHidden = false
                self?.hudOverlay.isHidden = true
            }
        }
    }
    
    // MARK: - Setup
    
    private func setupMotion() {
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 1.0 / 60.0
            motionManager.startAccelerometerUpdates()
        }
    }
    
    private func setupMetal() {
        guard let mtkView = view as? MTKView else {
            print("Error: View is not an MTKView")
            return
        }
        
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Error: Metal is not supported on this device")
            return
        }
        
        mtkView.device = defaultDevice
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0.08, green: 0.16, blue: 0.12, alpha: 1.0)
        
        guard let queue = defaultDevice.makeCommandQueue() else {
            print("Error: Failed to create command queue")
            return
        }
        self.commandQueue = queue
        
        do {
            self.renderer = try MetalRenderer(device: defaultDevice)
            self.engine = Engine(renderer: self.renderer)
            
            // Register Gameplay Systems
            self.jumperSystem = JumperSystem()
            self.platformSystem = PlatformSystem()
            self.monsterSystem = MonsterSystem()
            self.projectileSystem = ProjectileSystem()
            self.cameraFollowSystem = CameraFollowSystem()
            
            engine.world.registerSystem(self.jumperSystem)
            engine.world.registerSystem(self.platformSystem)
            engine.world.registerSystem(self.monsterSystem)
            engine.world.registerSystem(self.projectileSystem)
            engine.world.registerSystem(self.cameraFollowSystem)
            
            // Setup Camera Entity
            let camEntity = engine.world.createEntity()
            let camTransform = TransformComponent(position: SIMD3<Float>(0, 0, -10.0))
            let camComp = CameraComponent(
                projectionType: .orthographic,
                orthographicSize: 5.5,
                nearZ: 0.1,
                farZ: 100.0,
                aspectRatio: Float(view.bounds.width / max(view.bounds.height, 1))
            )
            engine.world.addComponent(camTransform, to: camEntity)
            engine.world.addComponent(camComp, to: camEntity)
            self.cameraEntity = camEntity
            
            // Connect Endless chunk generator callback
            cameraFollowSystem.onEndlessNeedChunk = { [weak self] fromY, toY in
                self?.spawnEndlessChunk(fromY: fromY, toY: toY)
            }
            
            mtkView.delegate = self
            self.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        } catch {
            print("Failed to initialize MetalRenderer: \(error)")
        }
    }
    
    private func setupOverlays() {
        // 1. HUD Overlay
        hudOverlay = GameHUDOverlay(frame: view.bounds)
        hudOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hudOverlay.isHidden = true
        hudOverlay.onPauseTapped = { [weak self] in
            self?.pauseGame()
        }
        view.addSubview(hudOverlay)
        
        // 2. Main Menu Overlay
        mainMenuOverlay = MainMenuOverlay(frame: view.bounds)
        mainMenuOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mainMenuOverlay.onPlayCampaign = { [weak self] in
            let lvl = GameProgressManager.shared.highestUnlockedLevel
            self?.startCampaignLevel(lvl)
        }
        mainMenuOverlay.onOpenLevelSelect = { [weak self] in
            self?.openLevelSelect()
        }
        mainMenuOverlay.onPlayEndless = { [weak self] in
            self?.startEndlessMode()
        }
        view.addSubview(mainMenuOverlay)
        
        // 3. Level Select Overlay
        levelSelectOverlay = LevelSelectOverlay(frame: view.bounds)
        levelSelectOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        levelSelectOverlay.isHidden = true
        levelSelectOverlay.onSelectLevel = { [weak self] level in
            self?.startCampaignLevel(level)
        }
        levelSelectOverlay.onBackToMenu = { [weak self] in
            self?.returnToMainMenu()
        }
        view.addSubview(levelSelectOverlay)
        
        // 4. Victory Overlay
        victoryOverlay = VictoryOverlay(frame: view.bounds)
        victoryOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        victoryOverlay.isHidden = true
        victoryOverlay.onNextLevel = { [weak self] in
            guard let self = self else { return }
            self.startCampaignLevel(self.activeLevelNumber + 1)
        }
        victoryOverlay.onReplay = { [weak self] in
            guard let self = self else { return }
            self.startCampaignLevel(self.activeLevelNumber)
        }
        victoryOverlay.onLevelSelect = { [weak self] in
            self?.openLevelSelect()
        }
        view.addSubview(victoryOverlay)
        
        // 5. Game Over Overlay
        gameOverOverlay = GameOverOverlay(frame: view.bounds)
        gameOverOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        gameOverOverlay.isHidden = true
        gameOverOverlay.onRetry = { [weak self] in
            guard let self = self else { return }
            if self.isCampaignMode {
                self.startCampaignLevel(self.activeLevelNumber)
            } else {
                self.startEndlessMode()
            }
        }
        gameOverOverlay.onLevelSelect = { [weak self] in
            self?.openLevelSelect()
        }
        gameOverOverlay.onMainMenu = { [weak self] in
            self?.returnToMainMenu()
        }
        view.addSubview(gameOverOverlay)
    }
    
    private func loadAssets() {
        guard let jsonUrl = Bundle.main.url(forResource: "acornjump", withExtension: "json") ?? Bundle.main.url(forResource: "Resources/acornjump", withExtension: "json"),
              let pngUrl = Bundle.main.url(forResource: "acornjump0", withExtension: "png") ?? Bundle.main.url(forResource: "Resources/acornjump0", withExtension: "png") else {
            print("Error: Could not locate acornjump sprite sheet in bundle")
            return
        }
        
        let loader = TextureLoader(device: renderer.device)
        Task {
            do {
                let texture = try await loader.loadTexture(from: pngUrl)
                let jsonData = try Data(contentsOf: jsonUrl)
                let metadata = try JSONDecoder().decode(SpriteSheetMetadata.self, from: jsonData)
                
                self.spriteSheet = SpriteSheet(texture: texture, metadata: metadata)
                self.isAssetsLoaded = true
                print("Acorn Jump SpriteSheet loaded with \(metadata.frames.count) frames.")
            } catch {
                print("Error loading SpriteSheet: \(error)")
            }
        }
    }
    
    // MARK: - Level & Game Flow
    
    public func startCampaignLevel(_ level: Int) {
        guard isAssetsLoaded else { return }
        
        self.isCampaignMode = true
        self.activeLevelNumber = max(1, min(100, level))
        self.gameState = .playing(isCampaign: true, level: activeLevelNumber)
        self.currentTouchSteering = nil
        
        clearGameplayEntities()
        
        let blueprint = LevelGenerator.generateCampaignLevel(level: activeLevelNumber)
        instantiateBlueprint(blueprint)
        
        cameraFollowSystem.reset(initialY: 0.0)
        
        // Update background color based on Zone Theme
        if let mtkView = view as? MTKView {
            let bg = blueprint.definition.zone.backgroundColor
            mtkView.clearColor = MTLClearColor(red: Double(bg.x), green: Double(bg.y), blue: Double(bg.z), alpha: 1.0)
        }
        
        mainMenuOverlay.isHidden = true
        levelSelectOverlay.isHidden = true
        victoryOverlay.isHidden = true
        gameOverOverlay.isHidden = true
        hudOverlay.isHidden = false
    }
    
    public func startEndlessMode() {
        guard isAssetsLoaded else { return }
        
        self.isCampaignMode = false
        self.endlessSeed = UInt64.random(in: 1...1_000_000)
        self.gameState = .playing(isCampaign: false, level: 1)
        self.currentTouchSteering = nil
        
        clearGameplayEntities()
        
        let blueprint = LevelGenerator.generateEndlessChunk(fromY: 0.0, toY: 60.0, currentScore: 0, seed: endlessSeed)
        instantiateBlueprint(blueprint)
        
        cameraFollowSystem.reset(initialY: 0.0)
        
        if let mtkView = view as? MTKView {
            mtkView.clearColor = MTLClearColor(red: 0.06, green: 0.12, blue: 0.22, alpha: 1.0)
        }
        
        mainMenuOverlay.isHidden = true
        levelSelectOverlay.isHidden = true
        victoryOverlay.isHidden = true
        gameOverOverlay.isHidden = true
        hudOverlay.isHidden = false
    }
    
    private func instantiateBlueprint(_ blueprint: LevelBlueprint) {
        // 1. Spawn Player Entity at bottom center
        let pEntity = engine.world.createEntity()
        let pTransform = TransformComponent(
            position: SIMD3<Float>(0.0, 0.6, 0.0),
            scale: SIMD3<Float>(repeating: playerScale)
        )
        let pSprite = SpriteComponent(spriteSheet: spriteSheet, frameName: "acorn_idle")
        let pJumper = JumperComponent(
            isCampaign: isCampaignMode,
            levelNumber: activeLevelNumber,
            targetLevelHeight: blueprint.finishY
        )
        
        engine.world.addComponent(pTransform, to: pEntity)
        engine.world.addComponent(pSprite, to: pEntity)
        engine.world.addComponent(pJumper, to: pEntity)
        self.playerEntity = pEntity
        
        // 2. Spawn Platforms
        for platData in blueprint.platforms {
            let platEntity = engine.world.createEntity()
            let transform = TransformComponent(
                position: platData.position,
                scale: SIMD3<Float>(repeating: platformScale)
            )
            let sprite = SpriteComponent(spriteSheet: spriteSheet, frameName: platData.type.frameName)
            let platComp = PlatformComponent(type: platData.type, width: platData.width, height: platData.height)
            
            engine.world.addComponent(transform, to: platEntity)
            engine.world.addComponent(sprite, to: platEntity)
            engine.world.addComponent(platComp, to: platEntity)
        }
        
        // 3. Spawn Monsters
        for monsterData in blueprint.monsters {
            let monsterEntity = engine.world.createEntity()
            let transform = TransformComponent(
                position: monsterData.position,
                scale: SIMD3<Float>(repeating: monsterScale)
            )
            let sprite = SpriteComponent(spriteSheet: spriteSheet, frameName: monsterData.type.frameName)
            let monsterComp = MonsterComponent(type: monsterData.type)
            
            engine.world.addComponent(transform, to: monsterEntity)
            engine.world.addComponent(sprite, to: monsterEntity)
            engine.world.addComponent(monsterComp, to: monsterEntity)
        }
        
        // 4. Spawn Collectibles
        for itemData in blueprint.collectibles {
            let itemEntity = engine.world.createEntity()
            let transform = TransformComponent(
                position: itemData.position,
                scale: SIMD3<Float>(repeating: itemScale)
            )
            let sprite = SpriteComponent(spriteSheet: spriteSheet, frameName: itemData.type.frameName)
            let itemComp = CollectibleComponent(type: itemData.type)
            
            engine.world.addComponent(transform, to: itemEntity)
            engine.world.addComponent(sprite, to: itemEntity)
            engine.world.addComponent(itemComp, to: itemEntity)
        }
        
        // 5. Spawn Finish Banner (Campaign Mode)
        if isCampaignMode {
            let bannerEntity = engine.world.createEntity()
            let transform = TransformComponent(
                position: SIMD3<Float>(0.0, blueprint.finishY + 0.8, 0.0),
                scale: SIMD3<Float>(repeating: bannerScale)
            )
            let sprite = SpriteComponent(spriteSheet: spriteSheet, frameName: "finish_banner")
            let bannerComp = FinishBannerComponent(targetHeight: blueprint.finishY)
            
            engine.world.addComponent(transform, to: bannerEntity)
            engine.world.addComponent(sprite, to: bannerEntity)
            engine.world.addComponent(bannerComp, to: bannerEntity)
        }
    }
    
    private func spawnEndlessChunk(fromY: Float, toY: Float) {
        guard let player = playerEntity,
              let jumper = engine.world.component(ofType: JumperComponent.self, for: player) else { return }
        
        let chunk = LevelGenerator.generateEndlessChunk(fromY: fromY, toY: toY, currentScore: jumper.score, seed: endlessSeed)
        
        for platData in chunk.platforms {
            let platEntity = engine.world.createEntity()
            let transform = TransformComponent(position: platData.position, scale: SIMD3<Float>(repeating: platformScale))
            let sprite = SpriteComponent(spriteSheet: spriteSheet, frameName: platData.type.frameName)
            let platComp = PlatformComponent(type: platData.type, width: platData.width, height: platData.height)
            engine.world.addComponent(transform, to: platEntity)
            engine.world.addComponent(sprite, to: platEntity)
            engine.world.addComponent(platComp, to: platEntity)
        }
        
        for monsterData in chunk.monsters {
            let monsterEntity = engine.world.createEntity()
            let transform = TransformComponent(position: monsterData.position, scale: SIMD3<Float>(repeating: monsterScale))
            let sprite = SpriteComponent(spriteSheet: spriteSheet, frameName: monsterData.type.frameName)
            let monsterComp = MonsterComponent(type: monsterData.type)
            engine.world.addComponent(transform, to: monsterEntity)
            engine.world.addComponent(sprite, to: monsterEntity)
            engine.world.addComponent(monsterComp, to: monsterEntity)
        }
        
        for itemData in chunk.collectibles {
            let itemEntity = engine.world.createEntity()
            let transform = TransformComponent(position: itemData.position, scale: SIMD3<Float>(repeating: itemScale))
            let sprite = SpriteComponent(spriteSheet: spriteSheet, frameName: itemData.type.frameName)
            let itemComp = CollectibleComponent(type: itemData.type)
            engine.world.addComponent(transform, to: itemEntity)
            engine.world.addComponent(sprite, to: itemEntity)
            engine.world.addComponent(itemComp, to: itemEntity)
        }
    }
    
    private func clearGameplayEntities() {
        for (entity, _) in engine.world.entities(with: JumperComponent.self) {
            engine.world.destroyEntity(entity)
        }
        for (entity, _) in engine.world.entities(with: PlatformComponent.self) {
            engine.world.destroyEntity(entity)
        }
        for (entity, _) in engine.world.entities(with: MonsterComponent.self) {
            engine.world.destroyEntity(entity)
        }
        for (entity, _) in engine.world.entities(with: CollectibleComponent.self) {
            engine.world.destroyEntity(entity)
        }
        for (entity, _) in engine.world.entities(with: ProjectileComponent.self) {
            engine.world.destroyEntity(entity)
        }
        for (entity, _) in engine.world.entities(with: FinishBannerComponent.self) {
            engine.world.destroyEntity(entity)
        }
        playerEntity = nil
    }
    
    private func openLevelSelect() {
        levelSelectOverlay.refreshZone()
        levelSelectOverlay.isHidden = false
        mainMenuOverlay.isHidden = true
        victoryOverlay.isHidden = true
        gameOverOverlay.isHidden = true
        hudOverlay.isHidden = true
        gameState = .levelSelect
    }
    
    private func returnToMainMenu() {
        mainMenuOverlay.refreshStats()
        mainMenuOverlay.isHidden = false
        levelSelectOverlay.isHidden = true
        victoryOverlay.isHidden = true
        gameOverOverlay.isHidden = true
        hudOverlay.isHidden = true
        gameState = .mainMenu
    }
    
    private func pauseGame() {
        if case .playing = gameState {
            gameState = .paused
            let alert = UIAlertController(title: "⏸️ Game Paused", message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Resume", style: .default) { [weak self] _ in
                if case .paused = self?.gameState {
                    self?.gameState = .playing(isCampaign: self?.isCampaignMode ?? true, level: self?.activeLevelNumber ?? 1)
                }
            })
            alert.addAction(UIAlertAction(title: "Level Select", style: .default) { [weak self] _ in
                self?.openLevelSelect()
            })
            alert.addAction(UIAlertAction(title: "Main Menu", style: .cancel) { [weak self] _ in
                self?.returnToMainMenu()
            })
            present(alert, animated: true)
        }
    }
    
    // MARK: - Input, Motion & Touch Handling
    
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: view)
        touchStartPoint = loc
        touchStartTime = CACurrentMediaTime()
        
        let screenW = view.bounds.width
        let normalizedOffset = Float((loc.x - screenW * 0.5) / (screenW * 0.45))
        currentTouchSteering = max(-1.0, min(1.0, normalizedOffset))
        
        let touchPos = SIMD2<Float>(Float(loc.x), Float(loc.y))
        engine.inputSystem.processTouchBegan(id: touch.hashValue, position: touchPos, tapCount: touch.tapCount, eventBus: engine.world.eventBus)
    }
    
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: view)
        let screenW = view.bounds.width
        
        let normalizedOffset = Float((loc.x - screenW * 0.5) / (screenW * 0.45))
        currentTouchSteering = max(-1.0, min(1.0, normalizedOffset))
        
        let prev = touch.previousLocation(in: view)
        let delta = SIMD2<Float>(Float(loc.x - prev.x), Float(loc.y - prev.y))
        let touchPos = SIMD2<Float>(Float(loc.x), Float(loc.y))
        engine.inputSystem.processTouchMoved(id: touch.hashValue, position: touchPos, delta: delta, eventBus: engine.world.eventBus)
    }
    
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: view)
        let elapsed = CACurrentMediaTime() - touchStartTime
        let dx = loc.x - touchStartPoint.x
        let dy = loc.y - touchStartPoint.y
        let dragDistSq = dx * dx + dy * dy
        
        // Tap gesture: short duration and small drag -> Shoot seed projectile!
        if elapsed < 0.28 && dragDistSq < (25.0 * 25.0) {
            shootProjectile()
        }
        
        currentTouchSteering = nil
        
        let touchPos = SIMD2<Float>(Float(loc.x), Float(loc.y))
        engine.inputSystem.processTouchEnded(id: touch.hashValue, position: touchPos, eventBus: engine.world.eventBus)
    }
    
    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentTouchSteering = nil
    }
    
    private func updateControlsInput() {
        guard let pEntity = playerEntity,
              var jumper = engine.world.component(ofType: JumperComponent.self, for: pEntity),
              jumper.isAlive else { return }
        
        var steering: Float = 0.0
        
        // 1. Device Tilt / Accelerometer (CoreMotion) with butter-smooth exponential curve
        if let accel = motionManager.accelerometerData {
            let rawX = Float(accel.acceleration.x)
            // Heavy low-pass filter to eliminate micro-jitters
            filteredTilt = filteredTilt * 0.86 + rawX * 0.14
            
            let deadzone: Float = 0.06
            let maxTilt: Float = 0.50
            let absTilt = abs(filteredTilt)
            
            if absTilt > deadzone {
                let normalized = min(1.0, (absTilt - deadzone) / (maxTilt - deadzone))
                let curved = pow(normalized, 1.35) // Fine micro-adjustments on gentle tilt, full speed on deliberate tilt
                let sign: Float = filteredTilt > 0 ? 1.0 : -1.0
                steering = sign * curved
            }
        }
        
        // 2. Direct Touch / Drag Steering
        if let touchSteer = currentTouchSteering {
            steering = touchSteer
        }
        
        // 3. Keyboard input from InputSystem (Arrow keys / A & D)
        if engine.inputSystem.state.isKeyDown(.leftArrow) || engine.inputSystem.state.isKeyDown(.a) {
            steering = -1.0
        } else if engine.inputSystem.state.isKeyDown(.rightArrow) || engine.inputSystem.state.isKeyDown(.d) {
            steering = 1.0
        }
        
        if engine.inputSystem.state.isKeyPressed(.space) || engine.inputSystem.state.isKeyPressed(.upArrow) || engine.inputSystem.state.isKeyPressed(.w) {
            shootProjectile()
        }
        
        jumper.horizontalSteering = steering
        engine.world.addComponent(jumper, to: pEntity)
    }
    
    private func shootProjectile() {
        guard let pEntity = playerEntity,
              var jumper = engine.world.component(ofType: JumperComponent.self, for: pEntity),
              let pTransform = engine.world.component(ofType: TransformComponent.self, for: pEntity),
              jumper.isAlive,
              jumper.shootCooldown <= 0 else { return }
        
        jumper.shootCooldown = 0.22
        jumper.state = .shooting
        engine.world.addComponent(jumper, to: pEntity)
        
        SoundManager.shared.playShoot()
        
        // Spawn Seed Bullet Entity
        let bulletEntity = engine.world.createEntity()
        let transform = TransformComponent(
            position: SIMD3<Float>(pTransform.position.x, pTransform.position.y + 0.6, 0.0),
            scale: SIMD3<Float>(repeating: itemScale * 0.8)
        )
        let sprite = SpriteComponent(spriteSheet: spriteSheet, frameName: "bullet_seed")
        let proj = ProjectileComponent(velocity: SIMD2<Float>(0.0, 20.0), lifetime: 2.0)
        
        engine.world.addComponent(transform, to: bulletEntity)
        engine.world.addComponent(sprite, to: bulletEntity)
        engine.world.addComponent(proj, to: bulletEntity)
    }
    
    // MARK: - MTKViewDelegate
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard let engine = engine else { return }
        let aspect = Float(max(size.width, 1.0) / max(size.height, 1.0))
        
        if let camEntity = cameraEntity,
           var camera = engine.world.component(ofType: CameraComponent.self, for: camEntity) {
            camera.aspectRatio = aspect
            engine.world.addComponent(camera, to: camEntity)
        }
    }
    
    public func draw(in view: MTKView) {
        guard let engine = engine,
              let queue = commandQueue,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = queue.makeCommandBuffer() else {
            return
        }
        
        let currentTime = CACurrentMediaTime()
        let dt = lastRenderTime == 0 ? 0.016 : currentTime - lastRenderTime
        lastRenderTime = currentTime
        
        // 1. Tick engine loop during gameplay
        if case .playing = gameState {
            updateControlsInput()
            engine.tick(deltaTime: dt)
            checkGameStateTransitions()
        }
        
        // 2. Render 2D Sprites
        let context = MetalRenderContext(renderPassDescriptor: descriptor, commandBuffer: commandBuffer)
        _ = context.getOrCreateEncoder()
        engine.render(context: context)
        context.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private func checkGameStateTransitions() {
        guard let pEntity = playerEntity,
              let jumper = engine.world.component(ofType: JumperComponent.self, for: pEntity) else { return }
        
        // Update live HUD
        hudOverlay.update(
            height: jumper.currentHeight,
            targetHeight: jumper.targetLevelHeight,
            score: jumper.score,
            acorns: jumper.goldenAcornsCollected,
            isCampaign: isCampaignMode,
            levelNumber: activeLevelNumber,
            activePowerup: jumper.activePowerup,
            powerupTimeRemaining: jumper.powerupTimeRemaining,
            shieldCharges: jumper.shieldCharges
        )
        
        // Check Victory
        if jumper.hasReachedFinish {
            if case .playing = gameState {
                let stars = max(1, min(3, jumper.starsCollected + 1))
                let result = GameProgressManager.shared.recordCampaignResult(
                    level: activeLevelNumber,
                    score: jumper.score,
                    stars: stars,
                    acornsCollected: jumper.goldenAcornsCollected
                )
                
                victoryOverlay.configure(
                    level: activeLevelNumber,
                    score: jumper.score,
                    stars: stars,
                    acorns: jumper.goldenAcornsCollected,
                    isNewBest: result.isNewBestScore
                )
                victoryOverlay.isHidden = false
                hudOverlay.isHidden = true
                gameState = .victory(level: activeLevelNumber, score: jumper.score, stars: stars, acorns: jumper.goldenAcornsCollected)
            }
        }
        // Check Game Over
        else if !jumper.isAlive {
            if case .playing = gameState {
                let isNewBest: Bool
                if isCampaignMode {
                    let res = GameProgressManager.shared.recordCampaignResult(
                        level: activeLevelNumber,
                        score: jumper.score,
                        stars: 0,
                        acornsCollected: jumper.goldenAcornsCollected
                    )
                    isNewBest = res.isNewBestScore
                } else {
                    isNewBest = GameProgressManager.shared.recordEndlessResult(
                        score: jumper.score,
                        acornsCollected: jumper.goldenAcornsCollected
                    )
                }
                
                gameOverOverlay.configure(
                    height: jumper.maxHeightReached,
                    score: jumper.score,
                    acorns: jumper.goldenAcornsCollected,
                    isNewBest: isNewBest,
                    isCampaign: isCampaignMode
                )
                gameOverOverlay.isHidden = false
                hudOverlay.isHidden = true
                gameState = .gameOver(height: jumper.maxHeightReached, score: jumper.score, acorns: jumper.goldenAcornsCollected)
            }
        }
    }
}
