import UIKit
import MetalKit
import AcornEngine

class GameViewController: UIViewController, MTKViewDelegate {
    var engine: Engine!
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
            self.engine = try Engine(device: defaultDevice)
            mtkView.delegate = self
            setupScene(device: defaultDevice)
        } catch {
            print("Failed to initialize Engine: \(error)")
        }
    }
    
    private func setupScene(device: MTLDevice) {
        let entity = engine.world.createEntity()
        let transform = TransformComponent(position: .zero)
        engine.world.addComponent(transform, to: entity)
        
        if let mesh = Mesh.makeTriangle(device: device) {
            let meshComponent = MeshComponent(mesh: mesh)
            engine.world.addComponent(meshComponent, to: entity)
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
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
        engine.render(renderPassDescriptor: descriptor, commandBuffer: commandBuffer)
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
