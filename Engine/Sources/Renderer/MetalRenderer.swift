import Foundation
import Metal

/// A Metal-specific render context.
public final class MetalRenderContext: RenderContext, @unchecked Sendable {
    /// The Metal render pass descriptor.
    public let renderPassDescriptor: MTLRenderPassDescriptor
    
    /// The Metal command buffer.
    public let commandBuffer: any MTLCommandBuffer
    
    private let lock = NSLock()
    private var _encoder: (any MTLRenderCommandEncoder)?
    
    /// Initializes a new Metal render context.
    /// - Parameters:
    ///   - renderPassDescriptor: The render pass descriptor.
    ///   - commandBuffer: The command buffer.
    public init(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: any MTLCommandBuffer) {
        self.renderPassDescriptor = renderPassDescriptor
        self.commandBuffer = commandBuffer
    }
    
    /// Returns the active render command encoder, creating it if necessary.
    public func getOrCreateEncoder() -> (any MTLRenderCommandEncoder)? {
        lock.lock()
        defer { lock.unlock() }
        if let encoder = _encoder {
            return encoder
        }
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        _encoder = encoder
        return encoder
    }
    
    /// Ends encoding on the active render command encoder.
    public func endEncoding() {
        lock.lock()
        defer { lock.unlock() }
        _encoder?.endEncoding()
        _encoder = nil
    }
    
    deinit {
        _encoder?.endEncoding()
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
    
    /// The SDF text render pipeline state.
    private let sdfTextPipelineState: any MTLRenderPipelineState
    
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
        
        // Initialize the SDF Text Pipeline
        guard let sdfVertexFunction = library.makeFunction(name: "sdf_vertex"),
              let sdfFragmentFunction = library.makeFunction(name: "sdf_fragment") else {
            throw RendererError.functionNotFound
        }
        
        let sdfPipelineDescriptor = MTLRenderPipelineDescriptor()
        sdfPipelineDescriptor.label = "SDF Text Pipeline"
        sdfPipelineDescriptor.vertexFunction = sdfVertexFunction
        sdfPipelineDescriptor.fragmentFunction = sdfFragmentFunction
        sdfPipelineDescriptor.colorAttachments[0].pixelFormat = pixelFormat
        
        // Enable alpha blending for text rendering
        let colorAttachment = sdfPipelineDescriptor.colorAttachments[0]
        colorAttachment?.isBlendingEnabled = true
        colorAttachment?.sourceRGBBlendFactor = .sourceAlpha
        colorAttachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachment?.rgbBlendOperation = .add
        colorAttachment?.sourceAlphaBlendFactor = .sourceAlpha
        colorAttachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        colorAttachment?.alphaBlendOperation = .add
        
        self.sdfTextPipelineState = try device.makeRenderPipelineState(descriptor: sdfPipelineDescriptor)
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
        
        guard let encoder = metalContext.getOrCreateEncoder() else {
            return
        }
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(metalMesh.vertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: metalMesh.vertexCount)
    }
    
    /// Renders text using signed distance field shaders.
    public nonisolated func renderText(
        mesh: Mesh,
        texture: any Texture,
        uniforms: SDFUniforms,
        context: RenderContext
    ) {
        guard let metalContext = context as? MetalRenderContext,
              let metalMesh = mesh as? MetalMesh,
              let metalTexture = texture as? MetalTexture else {
            return
        }
        
        guard let encoder = metalContext.getOrCreateEncoder() else {
            return
        }
        
        encoder.setRenderPipelineState(sdfTextPipelineState)
        encoder.setVertexBuffer(metalMesh.vertexBuffer, offset: 0, index: 0)
        
        // Bind the SDF Font texture atlas
        encoder.setFragmentTexture(metalTexture.texture, index: 0)
        
        // Bind the SDF parameters in uniform buffer to fragment and vertex shaders
        var mutUniforms = uniforms
        encoder.setFragmentBytes(&mutUniforms, length: MemoryLayout<SDFUniforms>.stride, index: 0)
        encoder.setVertexBytes(&mutUniforms, length: MemoryLayout<SDFUniforms>.stride, index: 1)
        
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: metalMesh.vertexCount)
    }
}
