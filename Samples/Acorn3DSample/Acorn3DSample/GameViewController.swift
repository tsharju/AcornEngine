import UIKit
import MetalKit
import AcornEngine

class GameViewController: UIViewController, MTKViewDelegate {
    var engine: Engine!
    var renderer: MetalRenderer!
    var commandQueue: MTLCommandQueue!
    var lastRenderTime: CFTimeInterval = 0
    var avocadoEntity: Entity!
    
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
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 1.0)
        
        guard let queue = defaultDevice.makeCommandQueue() else {
            print("Failed to create command queue")
            return
        }
        self.commandQueue = queue
        
        do {
            self.renderer = try MetalRenderer(device: defaultDevice)
            self.engine = Engine(renderer: self.renderer)
            self.engine.world.registerSystem(CameraSystem())
            mtkView.delegate = self
            setupScene()
            
            self.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        } catch {
            print("Failed to initialize Renderer: \(error)")
        }
    }
    
    private func setupScene() {
        // Create Avocado Entity first so the camera can orbit it
        avocadoEntity = engine.world.createEntity()
        let avocadoTransform = TransformComponent(
            position: SIMD3<Float>(0.0, -0.3, 0.0),
            rotation: SIMD3<Float>(0, 0, 0),
            scale: SIMD3<Float>(15.0, 15.0, 15.0)
        )
        engine.world.addComponent(avocadoTransform, to: avocadoEntity)
        
        // Setup Camera Entity
        let cameraEntity = engine.world.createEntity()
        let cameraTransform = TransformComponent(position: SIMD3<Float>(0, 0.0, -3.5))
        engine.world.addComponent(cameraTransform, to: cameraEntity)
        
        let cameraComponent = CameraComponent(
            projectionType: .perspective,
            fovY: Float.pi / 3.0, // 60 degrees vertical FOV
            nearZ: 0.1,
            farZ: 100.0,
            aspectRatio: 1.0
        )
        engine.world.addComponent(cameraComponent, to: cameraEntity)
        
        // Command camera to float/orbit around the Avocado model
        let orbitComponent = CameraOrbitComponent(
            target: avocadoEntity,
            radius: 3.8,
            speed: 0.5,          // Orbiting rotation speed
            baseHeight: 0.6,      // Height slightly above the model
            bobbingAmplitude: 0.12,
            bobbingSpeed: 0.7,
            swayAmplitude: 0.1,
            swaySpeed: 0.5
        )
        engine.world.addComponent(orbitComponent, to: cameraEntity)
        
        // Add ambient light
        let ambientLight = engine.world.createEntity()
        engine.world.addComponent(LightComponent(type: .ambient, color: SIMD3<Float>(1.0, 1.0, 1.0), intensity: 0.25), to: ambientLight)
        
        // Add directional light (simulating sun light)
        let dirLight = engine.world.createEntity()
        engine.world.addComponent(LightComponent(type: .directional, color: SIMD3<Float>(1.0, 0.95, 0.9), intensity: 0.8), to: dirLight)
        var dirTransform = TransformComponent()
        dirTransform.rotation = SIMD3<Float>(-.pi / 4, -.pi / 4, 0)
        engine.world.addComponent(dirTransform, to: dirLight)
        
        // Add a warm point light to highlight surface contours
        let pointLight = engine.world.createEntity()
        engine.world.addComponent(LightComponent(type: .point, color: SIMD3<Float>(1.0, 0.6, 0.3), intensity: 1.2), to: pointLight)
        let pointTransform = TransformComponent(position: SIMD3<Float>(1.5, 1.0, 1.5))
        engine.world.addComponent(pointTransform, to: pointLight)
        
        // Load the Avocado model
        loadGLTFModel()
    }
    
    private func loadGLTFModel() {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let avocadoUrl = Bundle.main.url(forResource: "Avocado", withExtension: "glb") ?? docsDir.appendingPathComponent("Avocado.glb")
        
        Task {
            do {
                let loader = GLTFModelLoader(device: self.renderer.device)
                let loaded = try loader.load(from: avocadoUrl)
                
                var texture: Texture? = nil
                if let texData = loaded.textureData {
                    let textureLoader = TextureLoader(device: self.renderer.device)
                    texture = try await textureLoader.loadTexture(from: texData)
                }
                
                await MainActor.run {
                    if let firstMesh = loaded.meshes.first {
                        let meshComponent = MeshComponent(mesh: firstMesh, color: SIMD4<Float>(1, 1, 1, 1), texture: texture)
                        self.engine.world.addComponent(meshComponent, to: self.avocadoEntity)
                    }
                }
            } catch {
                print("Failed to load Avocado glTF model: \(error)")
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
