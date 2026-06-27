import Foundation
import Metal

/// An error that can occur during renderer initialization.
public enum RendererError: Error {
    /// Failed to create a command queue.
    case initializationFailed
    /// Failed to load the default Metal library.
    case libraryNotFound
    /// Failed to find the required shader functions.
    case functionNotFound
}

/// A renderer responsible for drawing meshes using a forward rendering pipeline.
@MainActor
public class ForwardRenderer {
    /// The Metal device.
    public let device: any MTLDevice
    
    /// The command queue for submitting rendering work.
    private let commandQueue: any MTLCommandQueue
    
    /// The render pipeline state.
    private let pipelineState: any MTLRenderPipelineState
    
    /// Initializes a new forward renderer.
    /// - Parameters:
    ///   - device: The Metal device to use.
    ///   - pixelFormat: The pixel format of the render target. Defaults to `.bgra8Unorm`.
    /// - Throws: `RendererError` if initialization fails.
    public init(device: any MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) throws {
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            throw RendererError.initializationFailed
        }
        self.commandQueue = queue
        
        guard let shaderURL = Bundle.module.url(forResource: "Shaders.metal", withExtension: "txt"),
              let shaderSource = try? String(contentsOf: shaderURL),
              let library = try? device.makeLibrary(source: shaderSource, options: nil) else {
            throw RendererError.libraryNotFound
        }
        
        guard let vertexFunction = library.makeFunction(name: "vertex_main"),
              let fragmentFunction = library.makeFunction(name: "fragment_main") else {
            throw RendererError.functionNotFound
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Forward Pipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = pixelFormat
        
        self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    /// Renders a mesh into a render pass using the provided command buffer.
    /// - Parameters:
    ///   - mesh: The mesh to render.
    ///   - renderPassDescriptor: The render pass descriptor specifying the render target.
    ///   - commandBuffer: The command buffer to encode commands into.
    public func render(mesh: Mesh, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: any MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.vertexCount)
        
        encoder.endEncoding()
    }
}
