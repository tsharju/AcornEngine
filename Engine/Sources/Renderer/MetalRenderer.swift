import Foundation
import Metal

/// A Metal-specific render context.
public struct MetalRenderContext: RenderContext, @unchecked Sendable {
    /// The Metal render pass descriptor.
    public let renderPassDescriptor: MTLRenderPassDescriptor
    
    /// The Metal command buffer.
    public let commandBuffer: any MTLCommandBuffer
    
    /// Initializes a new Metal render context.
    /// - Parameters:
    ///   - renderPassDescriptor: The render pass descriptor.
    ///   - commandBuffer: The command buffer.
    public init(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: any MTLCommandBuffer) {
        self.renderPassDescriptor = renderPassDescriptor
        self.commandBuffer = commandBuffer
    }
}

/// A renderer implementation that uses the Metal API.
@MainActor
public class MetalRenderer: Renderer {
    /// The Metal device.
    public let device: any MTLDevice
    
    /// The command queue for submitting rendering work.
    private let commandQueue: any MTLCommandQueue
    
    /// The render pipeline state.
    private let pipelineState: any MTLRenderPipelineState
    
    /// Initializes a new Metal renderer.
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
    
    /// Creates a Metal mesh from vertices.
    public nonisolated func createMesh(vertices: [Vertex]) -> Mesh? {
        return MetalMesh(device: device, vertices: vertices)
    }
    
    /// Renders a mesh using the given Metal frame context.
    public nonisolated func render(mesh: Mesh, context: RenderContext) {
        guard let metalContext = context as? MetalRenderContext,
              let metalMesh = mesh as? MetalMesh else {
            return
        }
        
        guard let encoder = metalContext.commandBuffer.makeRenderCommandEncoder(descriptor: metalContext.renderPassDescriptor) else {
            return
        }
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(metalMesh.vertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: metalMesh.vertexCount)
        
        encoder.endEncoding()
    }
}
