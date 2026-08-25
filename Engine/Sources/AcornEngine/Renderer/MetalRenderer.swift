import Foundation
import Metal
import AcornMetal

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
public final class MetalRenderer: Renderer, @unchecked Sendable {
    /// The Metal device.
    public let device: any MTLDevice
    
    private let cxxRenderer: UnsafeMutablePointer<Acorn.AcornMetalRenderer>
    private let defaultWhiteTexture: MetalTexture
    
    /// Initializes a new Metal renderer.
    /// - Parameters:
    ///   - device: The Metal device to use.
    ///   - pixelFormat: The pixel format of the render target. Defaults to `.bgra8Unorm_srgb`.
    /// - Throws: `RendererError` if initialization fails.
    public init(device: any MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb) throws {
        self.device = device
        
        var metalLibrary: (any MTLLibrary)? = nil
        if let lib = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            metalLibrary = lib
        } else if let shaderURL = Bundle.module.url(forResource: "Shaders", withExtension: "metal"),
                  let shaderSource = try? String(contentsOf: shaderURL, encoding: .utf8) {
            do {
                metalLibrary = try device.makeLibrary(source: shaderSource, options: nil)
            } catch {
                print("Failed to compile Shaders.metal at runtime: \(error)")
            }
        }
        
        if metalLibrary == nil {
            metalLibrary = device.makeDefaultLibrary()
        }
        
        guard let library = metalLibrary else {
            throw RendererError.libraryNotFound
        }
        
        let devicePtr = Unmanaged.passUnretained(device).toOpaque()
        let libraryPtr = Unmanaged.passUnretained(library).toOpaque()
        
        guard let renderer = Acorn.AcornMetalRenderer.create(devicePtr, libraryPtr, UInt(pixelFormat.rawValue)) else {
            throw RendererError.initializationFailed
        }
        self.cxxRenderer = renderer
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let defaultTex = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.initializationFailed
        }
        let whitePixel: [UInt8] = [255, 255, 255, 255]
        defaultTex.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: whitePixel,
            bytesPerRow: 4
        )
        self.defaultWhiteTexture = MetalTexture(texture: defaultTex)
    }
    
    deinit {
        cxxRenderer.pointee.destroy()
    }
    
    /// Creates a Metal mesh from vertices.
    public func createMesh(vertices: [Vertex]) -> Mesh? {
        return MetalMesh(device: device, vertices: vertices)
    }
    
    /// Renders a mesh using the given Metal frame context.
    public func render(mesh: Mesh, texture: (any Texture)?, uniforms: GlobalUniforms, context: RenderContext) {
        guard let metalContext = context as? MetalRenderContext,
              let metalMesh = mesh as? MetalMesh else {
            return
        }
        
        guard let encoder = metalContext.getOrCreateEncoder() else {
            return
        }
        
        let encoderPtr = Unmanaged.passUnretained(encoder).toOpaque()
        
        var cxxUniforms = Acorn.GlobalUniforms()
        cxxUniforms.modelViewProjectionMatrix = uniforms.modelViewProjectionMatrix
        cxxUniforms.modelMatrix = uniforms.modelMatrix
        cxxUniforms.normalMatrix = uniforms.normalMatrix
        cxxUniforms.ambientLightColor = uniforms.ambientLightColor
        cxxUniforms.directionalLightColor = uniforms.directionalLightColor
        cxxUniforms.directionalLightDirection = uniforms.directionalLightDirection
        cxxUniforms.pointLightColor = uniforms.pointLightColor
        cxxUniforms.pointLightPosition = uniforms.pointLightPosition
        cxxUniforms.meshColor = uniforms.meshColor
        
        let targetTexture = texture ?? defaultWhiteTexture
        let cxxTexture = (targetTexture as? MetalTexture)?.cxxTexture
        
        cxxRenderer.pointee.render(metalMesh.cxxMesh, cxxTexture, cxxUniforms, encoderPtr)
    }
    
    /// Renders text using signed distance field shaders.
    public func renderText(
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
        
        let encoderPtr = Unmanaged.passUnretained(encoder).toOpaque()
        
        var cxxUniforms = Acorn.SDFUniforms()
        cxxUniforms.textColor = uniforms.textColor
        cxxUniforms.outlineColor = uniforms.outlineColor
        cxxUniforms.outlineWidth = uniforms.outlineWidth
        cxxUniforms.edgeWidth = uniforms.edgeWidth
        cxxUniforms.padding = uniforms.padding
        cxxUniforms.modelViewProjectionMatrix = uniforms.modelViewProjectionMatrix
        
        cxxRenderer.pointee.renderText(metalMesh.cxxMesh, metalTexture.cxxTexture, cxxUniforms, encoderPtr)
    }
    
    /// Renders a sprite or tile map using a sprite sheet texture.
    public func renderSprite(
        mesh: Mesh,
        texture: any Texture,
        uniforms: SpriteUniforms,
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
        
        let encoderPtr = Unmanaged.passUnretained(encoder).toOpaque()
        
        var cxxUniforms = Acorn.SpriteUniforms()
        cxxUniforms.modelViewProjectionMatrix = uniforms.modelViewProjectionMatrix
        cxxUniforms.colorTint = uniforms.colorTint
        
        cxxRenderer.pointee.renderSprite(metalMesh.cxxMesh, metalTexture.cxxTexture, cxxUniforms, encoderPtr)
    }
    
    private let meshLock = NSLock()
    private var _unitQuadMesh: (any Mesh)?
    
    /// A shared lazily-initialized unit quad mesh for sprite batch rendering.
    public var unitQuadMesh: (any Mesh)? {
        meshLock.lock()
        defer { meshLock.unlock() }
        if let mesh = _unitQuadMesh {
            return mesh
        }
        let quadVertices = SpriteMeshGenerator.generateUnitQuad()
        let mesh = createMesh(vertices: quadVertices)
        _unitQuadMesh = mesh
        return mesh
    }
    
    /// Renders multiple instances of a 3D mesh in a single instanced draw call.
    public func renderInstanced(
        mesh: any Mesh,
        texture: (any Texture)?,
        instances: [MeshInstanceData],
        uniforms: FrameUniforms,
        context: any RenderContext
    ) {
        guard !instances.isEmpty else { return }
        guard let metalContext = context as? MetalRenderContext,
              let metalMesh = mesh as? MetalMesh else {
            return
        }
        
        guard let encoder = metalContext.getOrCreateEncoder() else {
            return
        }
        
        let encoderPtr = Unmanaged.passUnretained(encoder).toOpaque()
        
        var cxxUniforms = Acorn.FrameUniforms()
        cxxUniforms.viewProjectionMatrix = uniforms.viewProjectionMatrix
        cxxUniforms.ambientLightColor = uniforms.ambientLightColor
        cxxUniforms.directionalLightColor = uniforms.directionalLightColor
        cxxUniforms.directionalLightDirection = uniforms.directionalLightDirection
        cxxUniforms.pointLightColor = uniforms.pointLightColor
        cxxUniforms.pointLightPosition = uniforms.pointLightPosition
        
        let targetTexture = texture ?? defaultWhiteTexture
        let cxxTexture = (targetTexture as? MetalTexture)?.cxxTexture
        
        let cxxInstances = instances.map { inst -> Acorn.MeshInstanceData in
            var d = Acorn.MeshInstanceData()
            d.modelMatrix = inst.modelMatrix
            d.normalMatrix = inst.normalMatrix
            d.color = inst.color
            return d
        }
        
        cxxInstances.withUnsafeBufferPointer { bufferPtr in
            guard let baseAddress = bufferPtr.baseAddress else { return }
            cxxRenderer.pointee.renderInstanced(
                metalMesh.cxxMesh,
                cxxTexture,
                baseAddress,
                instances.count,
                cxxUniforms,
                encoderPtr
            )
        }
    }
    
    /// Renders multiple sprite instances in a single instanced draw call.
    public func renderSpritesInstanced(
        mesh: any Mesh,
        texture: any Texture,
        instances: [SpriteInstanceData],
        uniforms: SpriteFrameUniforms,
        context: any RenderContext
    ) {
        guard !instances.isEmpty else { return }
        guard let metalContext = context as? MetalRenderContext,
              let metalMesh = mesh as? MetalMesh,
              let metalTexture = texture as? MetalTexture else {
            return
        }
        
        guard let encoder = metalContext.getOrCreateEncoder() else {
            return
        }
        
        let encoderPtr = Unmanaged.passUnretained(encoder).toOpaque()
        
        var cxxUniforms = Acorn.SpriteFrameUniforms()
        cxxUniforms.viewProjectionMatrix = uniforms.viewProjectionMatrix
        
        let cxxInstances = instances.map { inst -> Acorn.SpriteInstanceData in
            var d = Acorn.SpriteInstanceData()
            d.modelMatrix = inst.modelMatrix
            d.colorTint = inst.colorTint
            d.uvRect = inst.uvRect
            return d
        }
        
        cxxInstances.withUnsafeBufferPointer { bufferPtr in
            guard let baseAddress = bufferPtr.baseAddress else { return }
            cxxRenderer.pointee.renderSpritesInstanced(
                metalMesh.cxxMesh,
                metalTexture.cxxTexture,
                baseAddress,
                instances.count,
                cxxUniforms,
                encoderPtr
            )
        }
    }
}
