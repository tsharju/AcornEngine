import UIKit
import MetalKit
import AcornEngine

class GameViewController: UIViewController, MTKViewDelegate {
    var engine: Engine!
    var renderer: MetalRenderer!
    var commandQueue: MTLCommandQueue!
    var lastRenderTime: CFTimeInterval = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
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
        mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1.0)
        
        guard let queue = defaultDevice.makeCommandQueue() else {
            print("Failed to create command queue")
            return
        }
        self.commandQueue = queue
        
        do {
            self.renderer = try MetalRenderer(device: defaultDevice)
            self.engine = Engine(renderer: self.renderer)
            self.engine.world.registerSystem(CameraSystem())
            self.engine.world.registerSystem(PhysicsSystem())
            mtkView.delegate = self
            setupScene()
            self.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
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
        let device = self.renderer.device
        let engine = self.engine!
        Task.detached(priority: .userInitiated) {
            do {
                let fontAtlas = try SDFFontAtlasGenerator.generate(
                    fontName: "Helvetica-Bold",
                    fontSize: 48,
                    device: device
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
    }
    
    private func setupTileMap() {
        // Look in Main Bundle first, fall back to Documents directory
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let pngUrl = Bundle.main.url(forResource: "tileset", withExtension: "png") ?? docsDir.appendingPathComponent("tileset.png")
        let jsonUrl = Bundle.main.url(forResource: "tileset", withExtension: "json") ?? docsDir.appendingPathComponent("tileset.json")
        
        Task {
            do {
                let textureLoader = TextureLoader(device: self.renderer.device)
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
    
    private func setupCharacters() {
        // Look in Main Bundle first, fall back to Documents directory
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let pngUrl = Bundle.main.url(forResource: "characters0", withExtension: "png") ?? docsDir.appendingPathComponent("characters0.png")
        let jsonUrl = Bundle.main.url(forResource: "characters", withExtension: "json") ?? docsDir.appendingPathComponent("characters.json")
        
        Task {
            do {
                let textureLoader = TextureLoader(device: self.renderer.device)
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
                    
                    // Start animation loop task
                    Task {
                        let animations = ["walk", "jump", "attack", "die"]
                        var currentAnimIndex = 0
                        var currentFrame = 0
                        
                        while true {
                            try? await Task.sleep(nanoseconds: 250_000_000) // 250ms per frame
                            
                            let anim = animations[currentAnimIndex]
                            
                            // Update Knight frame
                            if var ks = self.engine.world.component(ofType: SpriteComponent.self, for: knightEntity) {
                                ks.frameName = "knight_\(anim)_\(currentFrame)"
                                ks.isDirty = true
                                self.engine.world.addComponent(ks, to: knightEntity)
                            }
                            
                            // Update Archer frame
                            if var asComp = self.engine.world.component(ofType: SpriteComponent.self, for: archerEntity) {
                                asComp.frameName = "archer_\(anim)_\(currentFrame)"
                                asComp.isDirty = true
                                self.engine.world.addComponent(asComp, to: archerEntity)
                            }
                            
                            // Update Mage frame
                            if var ms = self.engine.world.component(ofType: SpriteComponent.self, for: mageEntity) {
                                ms.frameName = "mage_\(anim)_\(currentFrame)"
                                ms.isDirty = true
                                self.engine.world.addComponent(ms, to: mageEntity)
                            }
                            
                            currentFrame += 1
                            if currentFrame >= 4 {
                                currentFrame = 0
                                currentAnimIndex = (currentAnimIndex + 1) % animations.count
                            }
                        }
                    }
                }
            } catch {
                print("Failed to load characters sprite sheet: \(error)")
            }
        }
    }
    
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
        
        engine.tick(deltaTime: deltaTime)
        
        let context = MetalRenderContext(renderPassDescriptor: descriptor, commandBuffer: commandBuffer)
        
        // Force encoder creation so clear color is always applied
        _ = context.getOrCreateEncoder()
        
        engine.render(context: context)
        context.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { cb in
            if let error = cb.error {
                print("Command buffer error: \(error.localizedDescription) (domain: \((error as NSError).domain), code: \((error as NSError).code))")
            }
        }
        commandBuffer.commit()
    }
}
