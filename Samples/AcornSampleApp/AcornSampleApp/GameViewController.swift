import UIKit
import QuartzCore
import AcornEngine

class GameViewController: UIViewController {
    var engine: Engine!
    var renderer: NoGraphicsRenderer!
    private var surfaceView: RenderSurfaceView!
    var lastRenderTime: CFTimeInterval = 0
    
    private var animationCycleTask: Task<Void, Never>?
    private var modelRotationTask: Task<Void, Never>?
    private var modelAnimationCycleTask: Task<Void, Never>?
    
    deinit {
        animationCycleTask?.cancel()
        modelRotationTask?.cancel()
        modelAnimationCycleTask?.cancel()
    }
    
    override func loadView() {
        let view = RenderSurfaceView()
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view = view
        self.surfaceView = view
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        animationCycleTask?.cancel()
        modelRotationTask?.cancel()
        modelAnimationCycleTask?.cancel()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let surfaceView = view as? RenderSurfaceView else {
            print("View of GameViewController is not a RenderSurfaceView")
            return
        }
        self.surfaceView = surfaceView
        surfaceView.pixelFormat = .bgra8UnormSRGB
        surfaceView.clearColor = SIMD4<Float>(0.1, 0.2, 0.3, 1.0)
        
        do {
            self.renderer = try NoGraphicsRenderer(surface: surfaceView.surfaceDescriptor)
            surfaceView.attachRenderer(self.renderer)
            self.engine = Engine(renderer: self.renderer)
            self.engine.world.registerSystem(CameraSystem())
            self.engine.world.registerSystem(PhysicsSystem())
            self.engine.world.registerSystem(ParticleSystem())
            setupScene()
            
            // Add basic lighting
            let ambientLight = engine.world.createEntity()
            engine.world.addComponent(LightComponent(type: .ambient, intensity: 0.3), to: ambientLight)
            
            let dirLight = engine.world.createEntity()
            engine.world.addComponent(LightComponent(type: .directional, intensity: 0.7), to: dirLight)
            var dirTransform = TransformComponent()
            dirTransform.rotation = SIMD3<Float>(-.pi / 4, -.pi / 4, 0)
            engine.world.addComponent(dirTransform, to: dirLight)
            
            surfaceView.onDrawableSizeChanged = { [weak self] size in
                self?.updateCameraAspectRatio(for: size)
            }
            surfaceView.onRenderFrame = { [weak self] in
                self?.renderFrame()
            }
            updateCameraAspectRatio(for: surfaceView.drawableSize)
            surfaceView.startRendering()
        } catch {
            print("Failed to initialize Renderer: \(error)")
        }
    }
    
    private func setupScene() {
        // Setup Triangle Entity (Dynamic Physics Body)
        let entity = engine.world.createEntity()
        let transform = TransformComponent(position: SIMD3<Float>(0, 3.0, 0))
        engine.world.addComponent(transform, to: entity)
        
        let physicsBody = PhysicsBodyComponent(type: .dynamicBody, angularVelocity: 1.0)
        engine.world.addComponent(physicsBody, to: entity)
        
        let physicsCollider = PhysicsColliderComponent(shapeType: .box(width: 1.0, height: 1.0), restitution: 0.6)
        engine.world.addComponent(physicsCollider, to: entity)
        
        let vertices: [Vertex] = [
            Vertex(position: SIMD3<Float>(0, 0.5, 0), color: SIMD4<Float>(1, 0, 0, 1)),
            Vertex(position: SIMD3<Float>(-0.5, -0.5, 0), color: SIMD4<Float>(0, 1, 0, 1)),
            Vertex(position: SIMD3<Float>(0.5, -0.5, 0), color: SIMD4<Float>(0, 0, 1, 1))
        ]
        
        if let mesh = renderer.createMesh(vertices: vertices) {
            let meshComponent = MeshComponent(mesh: mesh)
            engine.world.addComponent(meshComponent, to: entity)
        }
        
        // Setup Floor Entity (Static Physics Body)
        let floorEntity = engine.world.createEntity()
        let floorTransform = TransformComponent(position: SIMD3<Float>(0, -2.0, 0))
        engine.world.addComponent(floorTransform, to: floorEntity)
        
        let floorBody = PhysicsBodyComponent(type: .staticBody)
        engine.world.addComponent(floorBody, to: floorEntity)
        
        let floorCollider = PhysicsColliderComponent(shapeType: .box(width: 10.0, height: 1.0))
        engine.world.addComponent(floorCollider, to: floorEntity)
        
        let floorVertices: [Vertex] = [
            Vertex(position: SIMD3<Float>(-5.0, 0.5, 0), color: SIMD4<Float>(0.2, 0.5, 0.2, 1)),
            Vertex(position: SIMD3<Float>(5.0, 0.5, 0), color: SIMD4<Float>(0.2, 0.5, 0.2, 1)),
            Vertex(position: SIMD3<Float>(-5.0, -0.5, 0), color: SIMD4<Float>(0.2, 0.5, 0.2, 1)),
            Vertex(position: SIMD3<Float>(5.0, 0.5, 0), color: SIMD4<Float>(0.2, 0.5, 0.2, 1)),
            Vertex(position: SIMD3<Float>(5.0, -0.5, 0), color: SIMD4<Float>(0.2, 0.5, 0.2, 1)),
            Vertex(position: SIMD3<Float>(-5.0, -0.5, 0), color: SIMD4<Float>(0.2, 0.5, 0.2, 1))
        ]
        
        if let floorMesh = renderer.createMesh(vertices: floorVertices) {
            let floorMeshComponent = MeshComponent(mesh: floorMesh)
            engine.world.addComponent(floorMeshComponent, to: floorEntity)
        }
        
        // Setup SDF Text Entity
        let renderer = self.renderer!
        let engine = self.engine!
        Task.detached(priority: .userInitiated) {
            do {
                let fontAtlas = try SDFFontAtlasGenerator.generate(
                    fontName: "Helvetica-Bold",
                    fontSize: 48,
                    renderer: renderer
                )
                
                await MainActor.run {
                    let textEntity = engine.world.createEntity()
                    let textTransform = TransformComponent(position: SIMD3<Float>(-0.5, 0, 0))
                    engine.world.addComponent(textTransform, to: textEntity)
                    
                    let textComponent = TextComponent(
                        text: "Acorn SDF Text!",
                        fontAtlas: fontAtlas,
                        textColor: SIMD4<Float>(1.0, 0.8, 0.2, 1.0),     // Gold body
                        outlineColor: SIMD4<Float>(0.1, 0.1, 0.3, 1.0),  // Dark blue outline
                        outlineWidth: 0.12,                              // outline thickness
                        edgeWidth: 0.03                                  // smooth edge
                    )
                    engine.world.addComponent(textComponent, to: textEntity)
                }
            } catch {
                print("Failed to initialize SDF FontAtlas: \(error)")
            }
        }
        
        // Setup Camera Entity
        let cameraEntity = engine.world.createEntity()
        let cameraTransform = TransformComponent(position: SIMD3<Float>(0, 0.8, -4.5))
        engine.world.addComponent(cameraTransform, to: cameraEntity)
        
        let cameraComponent = CameraComponent(
            projectionType: .perspective,
            fovY: Float.pi / 3.0, // 60 degrees vertical FOV
            nearZ: 0.1,
            farZ: 100.0,
            aspectRatio: 1.0
        )
        engine.world.addComponent(cameraComponent, to: cameraEntity)
        
        // Use a floating orbit component to orbit the floor entity
        let orbitComponent = CameraOrbitComponent(
            target: floorEntity,
            radius: 5.5,
            speed: 0.3,          // Elegant slow rotation (0.3 rad/s)
            baseHeight: 1.5,      // Look from slightly above (1.5 units)
            bobbingAmplitude: 0.25, // Up/down floating (0.25 units)
            bobbingSpeed: 1.0,    // 1.0 rad/s vertical floating speed
            swayAmplitude: 0.15,   // Left/right swaying (0.15 units)
            swaySpeed: 0.8        // 0.8 rad/s horizontal sway speed
        )
        engine.world.addComponent(orbitComponent, to: cameraEntity)
        
        setupTileMap()
        setupCharacters()
        setupConfetti()
        setupGLTF()
        setupAnimatedGLTF()
        setupMapbox3DTile()
    }
    
    private func setupMapbox3DTile() {
        Task {
            let loader = MapTileLoader()
            let cpuMesh = await loader.createDemoBuildingTile(tileWidthMeters: 1.8, tileHeightMeters: 1.8, buildingHeight: 0.8)
            await MainActor.run {
                if let mesh = self.renderer.createMesh(meshData: cpuMesh) {
                    let tileEntity = self.engine.world.createEntity()
                    // Position to the right of the floor so orbit camera views it cleanly
                    let transform = TransformComponent(position: SIMD3<Float>(1.5, -1.5, 0.0))
                    self.engine.world.addComponent(transform, to: tileEntity)
                    self.engine.world.addComponent(MeshComponent(mesh: mesh), to: tileEntity)
                }
            }
        }
    }
    
    private func setupTileMap() {
        // Look in Main Bundle first, fall back to Documents directory
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let pngUrl = Bundle.main.url(forResource: "tileset", withExtension: "png") ?? docsDir.appendingPathComponent("tileset.png")
        let jsonUrl = Bundle.main.url(forResource: "tileset", withExtension: "json") ?? docsDir.appendingPathComponent("tileset.json")
        
        Task {
            do {
                let textureLoader = TextureLoader(renderer: self.renderer)
                let texture = try await textureLoader.loadTexture(from: pngUrl)
                let jsonData = try Data(contentsOf: jsonUrl)
                let decoder = JSONDecoder()
                let metadata = try decoder.decode(SpriteSheetMetadata.self, from: jsonData)
                let spriteSheet = SpriteSheet(texture: texture, metadata: metadata)
                
                let tiles = [
                    "red_tile", "green_tile", "red_tile", "green_tile",
                    "blue_tile", "yellow_tile", "blue_tile", "yellow_tile",
                    "red_tile", "green_tile", "red_tile", "green_tile",
                    "blue_tile", "yellow_tile", "blue_tile", "yellow_tile"
                ]
                
                let tileMap = TileMapComponent(
                    spriteSheet: spriteSheet,
                    columns: 4,
                    rows: 4,
                    tileSize: SIMD2<Float>(0.5, 0.5),
                    tiles: tiles
                )
                
                // Add the tile map to an entity
                await MainActor.run {
                    let mapEntity = self.engine.world.createEntity()
                    // Place it slightly behind and to the left
                    let transform = TransformComponent(position: SIMD3<Float>(-1.0, 0.0, -1.0))
                    self.engine.world.addComponent(transform, to: mapEntity)
                    self.engine.world.addComponent(tileMap, to: mapEntity)
                }
            } catch {
                print("Failed to load tilemap: \(error)")
            }
        }
    }
    
    private func setupConfetti() {
        // Create basic colored quad meshes
        let colors: [SIMD4<Float>] = [
            SIMD4<Float>(1, 0, 0, 1), // Red
            SIMD4<Float>(0, 1, 0, 1), // Green
            SIMD4<Float>(0, 0, 1, 1), // Blue
            SIMD4<Float>(1, 1, 0, 1), // Yellow
            SIMD4<Float>(1, 0, 1, 1)  // Pink
        ]
        
        var meshes: [any Mesh] = []
        for color in colors {
            let vertices: [Vertex] = [
                Vertex(position: SIMD3<Float>(-0.5, 0.5, 0), color: color),
                Vertex(position: SIMD3<Float>(0.5, 0.5, 0), color: color),
                Vertex(position: SIMD3<Float>(-0.5, -0.5, 0), color: color),
                Vertex(position: SIMD3<Float>(0.5, 0.5, 0), color: color),
                Vertex(position: SIMD3<Float>(0.5, -0.5, 0), color: color),
                Vertex(position: SIMD3<Float>(-0.5, -0.5, 0), color: color)
            ]
            if let mesh = renderer.createMesh(vertices: vertices) {
                meshes.append(mesh)
            }
        }
        
        // Setup emitter entity
        let emitterEntity = engine.world.createEntity()
        let transform = TransformComponent(position: SIMD3<Float>(0, 2.5, 0))
        engine.world.addComponent(transform, to: emitterEntity)
        
        let emitter = ParticleEmitterComponent(
            isEmitting: true,
            emitRate: 30.0, // 30 particles per second
            meshes: meshes,
            lifetime: 2.0...4.0,
            linearVelocityX: -2.0...2.0,
            linearVelocityY: 1.0...4.0, // Shoot upwards
            angularVelocity: -5.0...5.0,
            scale: 0.05...0.1
        )
        engine.world.addComponent(emitter, to: emitterEntity)
    }
    
    private func setupCharacters() {
        // Look in Main Bundle first, fall back to Documents directory
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let pngUrl = Bundle.main.url(forResource: "characters0", withExtension: "png") ?? docsDir.appendingPathComponent("characters0.png")
        let jsonUrl = Bundle.main.url(forResource: "characters", withExtension: "json") ?? docsDir.appendingPathComponent("characters.json")
        
        Task {
            do {
                let textureLoader = TextureLoader(renderer: self.renderer)
                let texture = try await textureLoader.loadTexture(from: pngUrl)
                let jsonData = try Data(contentsOf: jsonUrl)
                let decoder = JSONDecoder()
                let metadata = try decoder.decode(SpriteSheetMetadata.self, from: jsonData)
                let spriteSheet = SpriteSheet(texture: texture, metadata: metadata)
                
                // We will create three entities: Knight, Archer, Mage
                await MainActor.run {
                    let knightEntity = self.engine.world.createEntity()
                    // Place knight on the far left, slightly in front
                    let knightTransform = TransformComponent(
                        position: SIMD3<Float>(-0.8, -0.4, -0.3),
                        scale: SIMD3<Float>(repeating: 0.015)
                    )
                    let knightSprite = SpriteComponent(spriteSheet: spriteSheet, frameName: "knight_walk_0")
                    self.engine.world.addComponent(knightTransform, to: knightEntity)
                    self.engine.world.addComponent(knightSprite, to: knightEntity)
                    
                    let archerEntity = self.engine.world.createEntity()
                    // Place archer on the far right, slightly in front
                    let archerTransform = TransformComponent(
                        position: SIMD3<Float>(0.8, -0.4, -0.3),
                        scale: SIMD3<Float>(repeating: 0.015)
                    )
                    let archerSprite = SpriteComponent(spriteSheet: spriteSheet, frameName: "archer_walk_0")
                    self.engine.world.addComponent(archerTransform, to: archerEntity)
                    self.engine.world.addComponent(archerSprite, to: archerEntity)
                    
                    let mageEntity = self.engine.world.createEntity()
                    // Place mage in the center, floating higher up
                    let mageTransform = TransformComponent(
                        position: SIMD3<Float>(0.0, 0.4, -0.3),
                        scale: SIMD3<Float>(repeating: 0.015)
                    )
                    let mageSprite = SpriteComponent(spriteSheet: spriteSheet, frameName: "mage_walk_0")
                    self.engine.world.addComponent(mageTransform, to: mageEntity)
                    self.engine.world.addComponent(mageSprite, to: mageEntity)
                    
                    let allClips = spriteSheet.makeAnimationClips(fps: 4.0, playbackMode: .loop)
                    
                    let knightClips = allClips.filter { $0.key.hasPrefix("knight_") }
                    let knightAnim = SpriteAnimationComponent(clips: knightClips, initialClip: "knight_walk")
                    self.engine.world.addComponent(knightAnim, to: knightEntity)
                    
                    let archerClips = allClips.filter { $0.key.hasPrefix("archer_") }
                    let archerAnim = SpriteAnimationComponent(clips: archerClips, initialClip: "archer_walk")
                    self.engine.world.addComponent(archerAnim, to: archerEntity)
                    
                    let mageClips = allClips.filter { $0.key.hasPrefix("mage_") }
                    let mageAnim = SpriteAnimationComponent(clips: mageClips, initialClip: "mage_walk")
                    self.engine.world.addComponent(mageAnim, to: mageEntity)
                    
                    // Periodically cycle clips (walk -> jump -> attack -> die) to showcase flipbook transitions
                    self.animationCycleTask = Task { @MainActor [weak self] in
                        let actions = ["walk", "jump", "attack", "die"]
                        var actionIdx = 0
                        while !Task.isCancelled {
                            do {
                                try await Task.sleep(nanoseconds: 1_500_000_000) // Switch action every 1.5s
                            } catch {
                                break
                            }
                            guard let self, !Task.isCancelled else { break }
                            actionIdx = (actionIdx + 1) % actions.count
                            let action = actions[actionIdx]
                            
                            if var ka = self.engine.world.component(ofType: SpriteAnimationComponent.self, for: knightEntity) {
                                ka.play(clipNamed: "knight_\(action)")
                                self.engine.world.addComponent(ka, to: knightEntity)
                            }
                            if var aa = self.engine.world.component(ofType: SpriteAnimationComponent.self, for: archerEntity) {
                                aa.play(clipNamed: "archer_\(action)")
                                self.engine.world.addComponent(aa, to: archerEntity)
                            }
                            if var ma = self.engine.world.component(ofType: SpriteAnimationComponent.self, for: mageEntity) {
                                ma.play(clipNamed: "mage_\(action)")
                                self.engine.world.addComponent(ma, to: mageEntity)
                            }
                        }
                    }
                }
            } catch {
                print("Failed to load characters sprite sheet: \(error)")
            }
        }
    }

    private func setupGLTF() {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let avocadoUrl = Bundle.main.url(forResource: "Avocado", withExtension: "glb") ?? docsDir.appendingPathComponent("Avocado.glb")
        
        Task {
            do {
                let loader = GLTFModelLoader(renderer: self.renderer)
                let loaded = try loader.load(from: avocadoUrl)
                
                var texture: Texture? = nil
                if let texData = loaded.textureData {
                    let textureLoader = TextureLoader(renderer: self.renderer)
                    texture = try await textureLoader.loadTexture(from: texData)
                }
                
                await MainActor.run {
                    var modelEntities: [Entity] = []
                    
                    for node in loaded.nodes {
                        let entity = self.engine.world.createEntity()
                        self.engine.world.setName(node.name, for: entity)
                        
                        let localTransform = TransformComponent(
                            position: node.translation,
                            rotation: quaternionToEuler(node.rotation),
                            scale: node.scale
                        )
                        self.engine.world.addComponent(localTransform, to: entity)
                        
                        if let meshIdx = node.meshIndex, meshIdx < loaded.meshes.count {
                            let meshComponent = MeshComponent(mesh: loaded.meshes[meshIdx], texture: texture)
                            self.engine.world.addComponent(meshComponent, to: entity)
                        }
                        modelEntities.append(entity)
                    }
                    
                    var rootEntities: [Entity] = []
                    for (index, node) in loaded.nodes.enumerated() {
                        if let parentIdx = node.parentIndex, parentIdx < modelEntities.count {
                            let childEntity = modelEntities[index]
                            let parentEntity = modelEntities[parentIdx]
                            self.engine.world.addComponent(ParentComponent(parent: parentEntity), to: childEntity)
                        } else {
                            rootEntities.append(modelEntities[index])
                        }
                    }
                    
                    let avocadoEntity = self.engine.world.createEntity()
                    self.engine.world.setName("Avocado", for: avocadoEntity)
                    let baseTransform = TransformComponent(
                        position: SIMD3<Float>(0.0, -0.5, 0.0),
                        rotation: SIMD3<Float>(0, 0, 0),
                        scale: SIMD3<Float>(15.0, 15.0, 15.0)
                    )
                    self.engine.world.addComponent(baseTransform, to: avocadoEntity)
                    
                    for rootEntity in rootEntities {
                        self.engine.world.addComponent(ParentComponent(parent: avocadoEntity), to: rootEntity)
                    }
                    
                    self.modelRotationTask = Task { @MainActor [weak self] in
                        var angle: Float = 0
                        while !Task.isCancelled {
                            do {
                                try await Task.sleep(nanoseconds: 16_000_000) // ~60fps
                            } catch {
                                break
                            }
                            guard let self, !Task.isCancelled else { break }
                            angle += 0.02
                            if var t = self.engine.world.component(ofType: TransformComponent.self, for: avocadoEntity) {
                                t.rotation = SIMD3<Float>(0, angle, 0)
                                self.engine.world.addComponent(t, to: avocadoEntity)
                            }
                        }
                    }
                }
            } catch {
                print("Failed to load glTF model: \(error)")
            }
        }
    }
    
    private func setupAnimatedGLTF() {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelUrl = Bundle.main.url(forResource: "AnimatedTestModel", withExtension: "glb") ?? docsDir.appendingPathComponent("AnimatedTestModel.glb")
        
        Task {
            do {
                let loader = GLTFModelLoader(renderer: self.renderer)
                let model = try loader.loadModel(from: modelUrl)
                
                await MainActor.run {
                    let rootEntity = model.instantiate(in: self.engine.world, color: SIMD4<Float>(0.1, 0.85, 1.0, 1.0))
                    self.engine.world.setName("AnimatedModel", for: rootEntity)
                    print("Instantiated animated glTF model with \(model.animations.count) animations: \(model.animations.map(\.name))")
                    
                    // Position model prominently to the left of the Avocado
                    let transform = TransformComponent(
                        position: SIMD3<Float>(-1.4, -0.7, 0.3),
                        rotation: SIMD3<Float>(0, Float.pi / 4.0, 0),
                        scale: SIMD3<Float>(0.6, 0.6, 0.6)
                    )
                    self.engine.world.addComponent(transform, to: rootEntity)
                    
                    // Cycle animation clips ("Idle" <-> "Walk") with smooth cross-fade transition
                    self.modelAnimationCycleTask = Task { @MainActor [weak self] in
                        var currentClip = "Idle"
                        while !Task.isCancelled {
                            do {
                                try await Task.sleep(nanoseconds: 2_500_000_000) // Switch every 2.5s
                            } catch {
                                break
                            }
                            guard let self, !Task.isCancelled else { break }
                            
                            currentClip = (currentClip == "Idle") ? "Walk" : "Idle"
                            
                            if var anim = self.engine.world.component(ofType: ModelAnimationComponent.self, for: rootEntity) {
                                anim.transition(to: currentClip, duration: 0.8)
                                self.engine.world.addComponent(anim, to: rootEntity)
                            }
                        }
                    }
                }
            } catch {
                print("Failed to load animated glTF model: \(error)")
            }
        }
    }
    
    private func updateCameraAspectRatio(for size: CGSize) {
        guard let engine = engine, size.width > 0, size.height > 0 else { return }
        let aspect = Float(size.width / size.height)
        
        if let cameraTuple = engine.world.entities(with: CameraComponent.self).first {
            let entityId = cameraTuple.0
            var camera = cameraTuple.1
            camera.aspectRatio = aspect
            engine.world.addComponent(camera, to: entityId)
        }
    }
    
    private func renderFrame() {
        guard let engine = engine, let renderer = renderer else {
            return
        }
        
        let currentTime = CACurrentMediaTime()
        let deltaTime = lastRenderTime == 0 ? 0.016 : currentTime - lastRenderTime
        lastRenderTime = currentTime
        
        engine.tick(deltaTime: deltaTime)
        
        guard let context = renderer.beginFrame(clearColor: surfaceView.clearColor) else {
            return
        }
        engine.render(context: context)
        renderer.endFrame(context: context)
    }
}
