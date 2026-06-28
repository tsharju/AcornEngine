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
            mtkView.delegate = self
            setupScene()
            self.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        } catch {
            print("Failed to initialize Renderer: \(error)")
        }
    }
    
    private func setupScene() {
        // Setup Triangle Entity
        let entity = engine.world.createEntity()
        let transform = TransformComponent(position: .zero)
        engine.world.addComponent(transform, to: entity)
        
        let vertices: [Vertex] = [
            Vertex(position: SIMD3<Float>(0, 0.5, 0), color: SIMD4<Float>(1, 0, 0, 1)),
            Vertex(position: SIMD3<Float>(-0.5, -0.5, 0), color: SIMD4<Float>(0, 1, 0, 1)),
            Vertex(position: SIMD3<Float>(0.5, -0.5, 0), color: SIMD4<Float>(0, 0, 1, 1))
        ]
        
        if let mesh = renderer.createMesh(vertices: vertices) {
            let meshComponent = MeshComponent(mesh: mesh)
            engine.world.addComponent(meshComponent, to: entity)
        }
        
        // Setup SDF Text Entity
        do {
            let fontAtlas = try SDFFontAtlasGenerator.generate(
                fontName: "Helvetica-Bold",
                fontSize: 48,
                device: renderer.device
            )
            
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
        } catch {
            print("Failed to initialize SDF FontAtlas: \(error)")
        }
        
        // Setup Camera Entity
        let cameraEntity = engine.world.createEntity()
        let cameraTransform = TransformComponent(position: SIMD3<Float>(0, 0, -5))
        engine.world.addComponent(cameraTransform, to: cameraEntity)
        let cameraComponent = CameraComponent(projectionType: .orthographic, orthographicSize: 2.0, nearZ: 0.1, farZ: 100.0, aspectRatio: 1.0)
        // engine.world.addComponent(cameraComponent, to: cameraEntity)
        
        // Let camera track the triangle entity (with smoothing)
        let trackingComponent = CameraTrackingComponent(target: entity, offset: SIMD3<Float>(0, 0, -5), smoothing: 0.05)
        engine.world.addComponent(trackingComponent, to: cameraEntity)
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
        commandBuffer.commit()
    }
}
