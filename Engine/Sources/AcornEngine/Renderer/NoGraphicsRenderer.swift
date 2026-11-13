import Foundation
import AcornMath
internal import AcornRHI

/// Frame-scoped render context produced by `NoGraphicsRenderer.beginFrame(clearColor:)`.
public final class NoGraphicsRenderContext: RenderContext, @unchecked Sendable {
    internal let frameHandle: OpaquePointer
    internal var isEnded: Bool = false

    internal init(frameHandle: OpaquePointer) {
        self.frameHandle = frameHandle
    }
}

/// Hardware renderer implementation backed by `NoGraphicsAPI` (Metal 4 on macOS 26+ / iOS 26+
/// and structured for Vulkan 1.4 on desktop platforms).
public final class NoGraphicsRenderer: Renderer, @unchecked Sendable {
    private static let skinnedVertexStride = 80

    private let deviceBox: NoGraphicsDeviceBox
    private let meshLock = NSLock()
    private var _unitQuadMesh: (any Mesh)?

    /// Human-readable adapter name reported by the underlying GPU driver.
    public let deviceName: String

    /// Initializes a headless `NoGraphicsRenderer` targeting an offscreen color/depth render target.
    /// - Throws: `RendererError` if shader libraries are missing or device initialization fails.
    public convenience init() throws {
        try self.init(surface: nil)
    }

    /// Initializes a `NoGraphicsRenderer` bound to an optional presentation surface.
    /// - Parameter surface: Native surface descriptor (`CAMetalLayer` on Apple platforms), or `nil` for headless execution.
    /// - Throws: `RendererError` if shader libraries are missing or device initialization fails.
    public init(surface: RenderSurfaceDescriptor?) throws {
        let shaderSet = try Self.loadCompiledShaderSet()
        let pixelFormat = Self.mapSurfacePixelFormat(surface?.pixelFormat ?? .bgra8UnormSRGB)
        let rhiSurface = AcornRHISurfaceDesc(
            nativeLayer: surface?.nativeLayer,
            width: UInt32(max(1, surface?.width ?? 1280)),
            height: UInt32(max(1, surface?.height ?? 720)),
            pixelFormat: pixelFormat
        )

        #if DEBUG
        let enableValidation = true
        #else
        let enableValidation = false
        #endif

        let handle: OpaquePointer? = shaderSet.withRhiBundle { bundle in
            var surf = rhiSurface
            var shaderBundle = bundle
            return withUnsafePointer(to: &surf) { surfPtr in
                withUnsafePointer(to: &shaderBundle) { bundlePtr in
                    acorn_rhi_create_device(surfPtr, bundlePtr, enableValidation)
                }
            }
        }

        guard let handle else {
            throw RendererError.initializationFailed
        }

        self.deviceBox = NoGraphicsDeviceBox(handle: handle)
        if let namePtr = acorn_rhi_get_device_name(handle) {
            self.deviceName = String(cString: namePtr)
        } else {
            self.deviceName = "NoGraphicsAPI Device"
        }
    }

    /// Lazily-created unit quad mesh shared across batched 2D sprite draw calls.
    public var unitQuadMesh: (any Mesh)? {
        meshLock.lock()
        defer { meshLock.unlock() }
        if let existing = _unitQuadMesh {
            return existing
        }
        let quadVertices = SpriteMeshGenerator.generateUnitQuad()
        let created = createMesh(vertices: quadVertices)
        _unitQuadMesh = created
        return created
    }

    /// Creates a GPU-resident mesh from an array of `Vertex` values.
    public func createMesh(vertices: [Vertex]) -> (any Mesh)? {
        return createMesh(meshData: CPUMeshData(vertices: vertices, indices: []))
    }

    /// Creates a GPU-resident mesh from host CPU vertex and optional index buffers.
    public func createMesh(meshData: CPUMeshData) -> (any Mesh)? {
        guard !meshData.vertices.isEmpty else { return nil }
        precondition(MemoryLayout<Vertex>.stride == 64, "AcornEngine Vertex stride must equal 64 bytes")

        let vertexCount = UInt32(meshData.vertices.count)
        let indexCount = UInt32(meshData.indices.count)
        let rhiHandle: OpaquePointer? = meshData.vertices.withUnsafeBytes { vBytes in
            guard let vBase = vBytes.baseAddress else { return nil }
            if meshData.indices.isEmpty {
                return acorn_rhi_create_mesh(deviceBox.handle, vBase, vertexCount, nil, 0)
            }
            return meshData.indices.withUnsafeBufferPointer { iBuf in
                acorn_rhi_create_mesh(deviceBox.handle, vBase, vertexCount, iBuf.baseAddress, indexCount)
            }
        }

        guard let rhiHandle else { return nil }
        return NoGraphicsMesh(deviceBox: deviceBox, rhiHandle: rhiHandle, vertices: meshData.vertices)
    }

    /// Creates a GPU-resident skinned mesh from packed 80-byte skinned vertex data.
    public func createSkinnedMesh(
        skinnedVertexData: Data,
        vertexCount: Int,
        indices: [UInt32] = []
    ) -> (any Mesh)? {
        guard vertexCount > 0,
              skinnedVertexData.count >= vertexCount * Self.skinnedVertexStride else {
            return nil
        }

        let vCount = UInt32(vertexCount)
        let iCount = UInt32(indices.count)
        let rhiHandle: OpaquePointer? = skinnedVertexData.withUnsafeBytes { vBytes in
            guard let vBase = vBytes.baseAddress else { return nil }
            if indices.isEmpty {
                return acorn_rhi_create_skinned_mesh(deviceBox.handle, vBase, vCount, nil, 0)
            }
            return indices.withUnsafeBufferPointer { iBuf in
                acorn_rhi_create_skinned_mesh(deviceBox.handle, vBase, vCount, iBuf.baseAddress, iCount)
            }
        }

        guard let rhiHandle else { return nil }
        return NoGraphicsMesh(deviceBox: deviceBox, rhiHandle: rhiHandle)
    }

    /// Creates and uploads a 2D GPU texture from raw CPU pixel bytes.
    public func createTexture(
        width: Int,
        height: Int,
        pixelData: [UInt8],
        format: TextureFormat
    ) -> (any Texture)? {
        guard width > 0, height > 0 else { return nil }
        let (rhiFormat, bytesPerPixel) = Self.mapTextureFormat(format)
        let expectedBytes = width * height * bytesPerPixel
        guard pixelData.count >= expectedBytes else { return nil }

        let rhiHandle: OpaquePointer? = pixelData.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return nil }
            return acorn_rhi_create_texture(
                deviceBox.handle,
                UInt32(width),
                UInt32(height),
                rhiFormat,
                base,
                expectedBytes
            )
        }

        guard let rhiHandle else { return nil }
        return NoGraphicsTexture(deviceBox: deviceBox, rhiHandle: rhiHandle, format: format)
    }

    /// Begins recording a frame cleared to `clearColor`.
    public func beginFrame(clearColor: SIMD4<Float>) -> (any RenderContext)? {
        guard let frameHandle = acorn_rhi_begin_frame(
            deviceBox.handle,
            clearColor.x,
            clearColor.y,
            clearColor.z,
            clearColor.w
        ) else {
            return nil
        }
        return NoGraphicsRenderContext(frameHandle: frameHandle)
    }

    /// Ends the active render pass, submits recorded commands, and presents if windowed.
    public func endFrame(context: any RenderContext) {
        guard let rhiContext = context as? NoGraphicsRenderContext, !rhiContext.isEnded else {
            return
        }
        rhiContext.isEnded = true
        acorn_rhi_end_frame(deviceBox.handle, rhiContext.frameHandle)
    }

    /// Updates cached drawable dimensions in pixels.
    @discardableResult
    public func resizeSurface(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0 else { return false }
        return acorn_rhi_resize_surface(deviceBox.handle, UInt32(width), UInt32(height))
    }

    /// Attaches or replaces a presentation surface target.
    @discardableResult
    public func attachSurface(_ surface: RenderSurfaceDescriptor) -> Bool {
        var rhiSurface = AcornRHISurfaceDesc(
            nativeLayer: surface.nativeLayer,
            width: UInt32(max(1, surface.width)),
            height: UInt32(max(1, surface.height)),
            pixelFormat: Self.mapSurfacePixelFormat(surface.pixelFormat)
        )
        return withUnsafePointer(to: &rhiSurface) { ptr in
            acorn_rhi_attach_surface(deviceBox.handle, ptr)
        }
    }

    /// Blocks until all submitted GPU work has completed.
    public func waitIdle() {
        acorn_rhi_wait_idle(deviceBox.handle)
    }

    /// Creates a resizable offscreen color and sampled-depth render target pair.
    public func createOffscreenTarget(width: Int, height: Int) -> (any OffscreenRenderTarget)? {
        guard width > 0, height > 0 else { return nil }
        guard let rhiHandle = acorn_rhi_create_offscreen_target(
            deviceBox.handle,
            UInt32(width),
            UInt32(height)
        ) else {
            return nil
        }
        return NoGraphicsOffscreenTarget(deviceBox: deviceBox, rhiHandle: rhiHandle)
    }

    /// Resizes an existing offscreen render target when viewport dimensions change.
    @discardableResult
    public func resizeOffscreenTarget(_ target: any OffscreenRenderTarget, width: Int, height: Int) -> Bool {
        guard width > 0, height > 0, let ngTarget = target as? NoGraphicsOffscreenTarget else {
            return false
        }
        return acorn_rhi_resize_offscreen_target(deviceBox.handle, ngTarget.rhiHandle, UInt32(width), UInt32(height))
    }

    /// Creates a fullscreen post-processing pipeline from compiled platform shader binaries.
    public func createPostProcessPipeline(
        vertexShaderData: Data,
        fragmentShaderData: Data,
        vertexEntry: String = "vertexMain",
        fragmentEntry: String = "fragmentMain"
    ) -> (any PostProcessPipeline)? {
        guard !vertexShaderData.isEmpty, !fragmentShaderData.isEmpty else {
            return nil
        }
        let vNSData = vertexShaderData as NSData
        let fNSData = fragmentShaderData as NSData
        let rhiHandle: OpaquePointer? = vertexEntry.withCString { vEntryPtr in
            fragmentEntry.withCString { fEntryPtr in
                var binary = AcornRHIShaderBinary(
                    vertexCode: vNSData.bytes.assumingMemoryBound(to: UInt8.self),
                    vertexSize: vertexShaderData.count,
                    vertexEntry: vEntryPtr,
                    fragmentCode: fNSData.bytes.assumingMemoryBound(to: UInt8.self),
                    fragmentSize: fragmentShaderData.count,
                    fragmentEntry: fEntryPtr
                )
                return withExtendedLifetime((vNSData, fNSData)) {
                    withUnsafePointer(to: &binary) { ptr in
                        acorn_rhi_create_post_process_pipeline(deviceBox.handle, ptr)
                    }
                }
            }
        }
        guard let rhiHandle else { return nil }
        return NoGraphicsPostProcessPipeline(deviceBox: deviceBox, rhiHandle: rhiHandle)
    }

    /// Begins recording a two-pass frame cleared to `clearColor` targeting `target`.
    public func beginOffscreenFrame(
        target: any OffscreenRenderTarget,
        clearColor: SIMD4<Float>
    ) -> (any RenderContext)? {
        guard let ngTarget = target as? NoGraphicsOffscreenTarget else {
            return nil
        }
        guard let frameHandle = acorn_rhi_begin_offscreen_frame(
            deviceBox.handle,
            ngTarget.rhiHandle,
            clearColor.x,
            clearColor.y,
            clearColor.z,
            clearColor.w
        ) else {
            return nil
        }
        return NoGraphicsRenderContext(frameHandle: frameHandle)
    }

    /// Ends the offscreen scene pass, issues fragment-read barriers, and begins the final pass.
    public func beginPostProcessPass(context: any RenderContext) {
        guard let rhiContext = context as? NoGraphicsRenderContext, !rhiContext.isEnded else {
            return
        }
        acorn_rhi_begin_post_process_pass(deviceBox.handle, rhiContext.frameHandle)
    }

    /// Executes a fullscreen triangle post-process draw reading the offscreen target and binding uniform bytes.
    public func renderPostProcess(
        pipeline: any PostProcessPipeline,
        target: any OffscreenRenderTarget,
        uniformData: Data,
        context: any RenderContext
    ) {
        guard let rhiContext = context as? NoGraphicsRenderContext, !rhiContext.isEnded,
              let ngPipeline = pipeline as? NoGraphicsPostProcessPipeline,
              let ngTarget = target as? NoGraphicsOffscreenTarget else {
            return
        }
        if uniformData.isEmpty {
            acorn_rhi_draw_post_process(
                deviceBox.handle,
                rhiContext.frameHandle,
                ngPipeline.rhiHandle,
                ngTarget.rhiHandle,
                nil,
                0
            )
            return
        }
        uniformData.withUnsafeBytes { bytes in
            acorn_rhi_draw_post_process(
                deviceBox.handle,
                rhiContext.frameHandle,
                ngPipeline.rhiHandle,
                ngTarget.rhiHandle,
                bytes.baseAddress,
                bytes.count
            )
        }
    }

    /// Renders a single unskinned 3D mesh.
    public func render(
        mesh: any Mesh,
        texture: (any Texture)?,
        uniforms: GlobalUniforms,
        context: any RenderContext
    ) {
        guard let rhiContext = context as? NoGraphicsRenderContext, !rhiContext.isEnded,
              let ngMesh = mesh as? NoGraphicsMesh, !ngMesh.isSkinned else {
            return
        }
        let rhiTexture: OpaquePointer?
        if let texture {
            guard let ngTex = texture as? NoGraphicsTexture else { return }
            rhiTexture = ngTex.rhiHandle
        } else {
            rhiTexture = nil
        }

        var rhiUniforms = Self.makeGlobalUniforms(uniforms)
        withUnsafePointer(to: &rhiUniforms) { ptr in
            acorn_rhi_draw_mesh(deviceBox.handle, rhiContext.frameHandle, ngMesh.rhiHandle, rhiTexture, ptr)
        }
    }

    /// Renders signed distance field text quads.
    public func renderText(
        mesh: any Mesh,
        texture: any Texture,
        uniforms: SDFUniforms,
        context: any RenderContext
    ) {
        guard let rhiContext = context as? NoGraphicsRenderContext, !rhiContext.isEnded,
              let ngMesh = mesh as? NoGraphicsMesh, !ngMesh.isSkinned,
              let ngTexture = texture as? NoGraphicsTexture else {
            return
        }

        var rhiUniforms = AcornRHISdfUniforms(
            textColor: Self.packFloat4(uniforms.textColor),
            outlineColor: Self.packFloat4(uniforms.outlineColor),
            outlineWidth: uniforms.outlineWidth,
            edgeWidth: uniforms.edgeWidth,
            _padding: (uniforms.padding.x, uniforms.padding.y),
            modelViewProjectionMatrix: Self.packRowMajor(uniforms.modelViewProjectionMatrix, flipClipY: true)
        )
        withUnsafePointer(to: &rhiUniforms) { ptr in
            acorn_rhi_draw_sdf_text(deviceBox.handle, rhiContext.frameHandle, ngMesh.rhiHandle, ngTexture.rhiHandle, ptr)
        }
    }

    /// Renders a 2D sprite or tilemap mesh.
    public func renderSprite(
        mesh: any Mesh,
        texture: any Texture,
        uniforms: SpriteUniforms,
        context: any RenderContext
    ) {
        guard let rhiContext = context as? NoGraphicsRenderContext, !rhiContext.isEnded,
              let ngMesh = mesh as? NoGraphicsMesh, !ngMesh.isSkinned,
              let ngTexture = texture as? NoGraphicsTexture else {
            return
        }

        var rhiUniforms = AcornRHISpriteUniforms(
            modelViewProjectionMatrix: Self.packRowMajor(uniforms.modelViewProjectionMatrix, flipClipY: true),
            colorTint: Self.packFloat4(uniforms.colorTint)
        )
        withUnsafePointer(to: &rhiUniforms) { ptr in
            acorn_rhi_draw_sprite(deviceBox.handle, rhiContext.frameHandle, ngMesh.rhiHandle, ngTexture.rhiHandle, ptr)
        }
    }

    /// Renders multiple instances of a 3D mesh in a single draw call.
    public func renderInstanced(
        mesh: any Mesh,
        texture: (any Texture)?,
        instances: [MeshInstanceData],
        uniforms: FrameUniforms,
        context: any RenderContext
    ) {
        guard !instances.isEmpty,
              let rhiContext = context as? NoGraphicsRenderContext, !rhiContext.isEnded,
              let ngMesh = mesh as? NoGraphicsMesh, !ngMesh.isSkinned else {
            return
        }
        let rhiTexture: OpaquePointer?
        if let texture {
            guard let ngTex = texture as? NoGraphicsTexture else { return }
            rhiTexture = ngTex.rhiHandle
        } else {
            rhiTexture = nil
        }

        var rhiUniforms = AcornRHIFrameUniforms(
            viewProjectionMatrix: Self.packRowMajor(uniforms.viewProjectionMatrix, flipClipY: true),
            ambientLightColor: Self.packFloat4(uniforms.ambientLightColor),
            directionalLightColor: Self.packFloat4(uniforms.directionalLightColor),
            directionalLightDirection: Self.packFloat4(uniforms.directionalLightDirection),
            pointLightColor: Self.packFloat4(uniforms.pointLightColor),
            pointLightPosition: Self.packFloat4(uniforms.pointLightPosition)
        )
        let rhiInstances = instances.map { inst in
            AcornRHIMeshInstanceData(
                modelMatrix: Self.packRowMajor(inst.modelMatrix),
                normalMatrix: Self.packRowMajor(inst.normalMatrix),
                color: Self.packFloat4(inst.color)
            )
        }

        rhiInstances.withUnsafeBufferPointer { instBuf in
            guard let instBase = instBuf.baseAddress else { return }
            withUnsafePointer(to: &rhiUniforms) { uniPtr in
                acorn_rhi_draw_instanced(
                    deviceBox.handle,
                    rhiContext.frameHandle,
                    ngMesh.rhiHandle,
                    rhiTexture,
                    instBase,
                    UInt32(rhiInstances.count),
                    uniPtr
                )
            }
        }
    }

    /// Renders multiple 2D sprite instances in a single instanced draw call.
    public func renderSpritesInstanced(
        mesh: any Mesh,
        texture: any Texture,
        instances: [SpriteInstanceData],
        uniforms: SpriteFrameUniforms,
        context: any RenderContext
    ) {
        guard !instances.isEmpty,
              let rhiContext = context as? NoGraphicsRenderContext, !rhiContext.isEnded,
              let ngMesh = mesh as? NoGraphicsMesh, !ngMesh.isSkinned,
              let ngTexture = texture as? NoGraphicsTexture else {
            return
        }

        var rhiUniforms = AcornRHISpriteFrameUniforms(
            viewProjectionMatrix: Self.packRowMajor(uniforms.viewProjectionMatrix, flipClipY: true)
        )
        let rhiInstances = instances.map { inst in
            AcornRHISpriteInstanceData(
                modelMatrix: Self.packRowMajor(inst.modelMatrix),
                colorTint: Self.packFloat4(inst.colorTint),
                uvRect: Self.packFloat4(inst.uvRect)
            )
        }

        rhiInstances.withUnsafeBufferPointer { instBuf in
            guard let instBase = instBuf.baseAddress else { return }
            withUnsafePointer(to: &rhiUniforms) { uniPtr in
                acorn_rhi_draw_sprites_instanced(
                    deviceBox.handle,
                    rhiContext.frameHandle,
                    ngMesh.rhiHandle,
                    ngTexture.rhiHandle,
                    instBase,
                    UInt32(rhiInstances.count),
                    uniPtr
                )
            }
        }
    }

    /// Renders a textured or untextured road mesh using anti-aliased edge smoothing.
    public func renderRoads(
        mesh: any Mesh,
        texture: (any Texture)?,
        uniforms: RoadUniforms,
        context: any RenderContext
    ) {
        guard let rhiContext = context as? NoGraphicsRenderContext, !rhiContext.isEnded,
              let ngMesh = mesh as? NoGraphicsMesh, !ngMesh.isSkinned else {
            return
        }
        let rhiTexture: OpaquePointer?
        if let texture {
            guard let ngTex = texture as? NoGraphicsTexture else { return }
            rhiTexture = ngTex.rhiHandle
        } else {
            rhiTexture = nil
        }

        var rhiUniforms = AcornRHIRoadUniforms(
            modelViewProjectionMatrix: Self.packRowMajor(uniforms.modelViewProjectionMatrix, flipClipY: true),
            outlineColor: Self.packFloat4(uniforms.outlineColor),
            outlineWidth: uniforms.outlineWidth,
            edgeWidth: uniforms.edgeWidth,
            widthScale: uniforms.widthScale,
            renderMode: uniforms.renderMode
        )
        withUnsafePointer(to: &rhiUniforms) { ptr in
            acorn_rhi_draw_roads(deviceBox.handle, rhiContext.frameHandle, ngMesh.rhiHandle, rhiTexture, ptr)
        }
    }

    /// Renders an untextured vector road mesh.
    public func renderRoads(
        mesh: any Mesh,
        uniforms: RoadUniforms,
        context: any RenderContext
    ) {
        renderRoads(mesh: mesh, texture: nil, uniforms: uniforms, context: context)
    }

    /// Renders a skinned mesh using joint transformation matrices.
    public func renderSkinned(
        mesh: any Mesh,
        texture: (any Texture)?,
        uniforms: GlobalUniforms,
        jointMatrices: [Matrix4x4],
        context: any RenderContext
    ) {
        guard let rhiContext = context as? NoGraphicsRenderContext, !rhiContext.isEnded,
              let ngMesh = mesh as? NoGraphicsMesh else {
            return
        }
        if !ngMesh.isSkinned {
            render(mesh: mesh, texture: texture, uniforms: uniforms, context: context)
            return
        }

        let rhiTexture: OpaquePointer?
        if let texture {
            guard let ngTex = texture as? NoGraphicsTexture else { return }
            rhiTexture = ngTex.rhiHandle
        } else {
            rhiTexture = nil
        }

        var rhiUniforms = Self.makeGlobalUniforms(uniforms)
        var packedJoints: [Float] = []
        packedJoints.reserveCapacity(jointMatrices.count * 16)
        for matrix in jointMatrices {
            let row = Self.packRowMajor(matrix)
            packedJoints.append(contentsOf: [
                row.0, row.1, row.2, row.3,
                row.4, row.5, row.6, row.7,
                row.8, row.9, row.10, row.11,
                row.12, row.13, row.14, row.15
            ])
        }

        withUnsafePointer(to: &rhiUniforms) { uniPtr in
            if packedJoints.isEmpty {
                acorn_rhi_draw_skinned_mesh(
                    deviceBox.handle,
                    rhiContext.frameHandle,
                    ngMesh.rhiHandle,
                    rhiTexture,
                    uniPtr,
                    nil,
                    0
                )
            } else {
                packedJoints.withUnsafeBufferPointer { jointBuf in
                    acorn_rhi_draw_skinned_mesh(
                        deviceBox.handle,
                        rhiContext.frameHandle,
                        ngMesh.rhiHandle,
                        rhiTexture,
                        uniPtr,
                        jointBuf.baseAddress,
                        UInt32(jointMatrices.count)
                    )
                }
            }
        }
    }

    // MARK: - Matrix & Uniform Marshaling

    /// 16-float row-major storage tuple matching Slang/NoGraphicsAPI `float4x4` GPU uniform layout.
    public typealias RowMajorFloat4x4 = (
        Float, Float, Float, Float,
        Float, Float, Float, Float,
        Float, Float, Float, Float,
        Float, Float, Float, Float
    )

    /// Packs a column-major `Matrix4x4` into row-major GPU layout, optionally negating clip-space Y
    /// for top-down Metal 4 / Vulkan render targets.
    public static func packRowMajor(_ matrix: Matrix4x4, flipClipY: Bool = false) -> RowMajorFloat4x4 {
        let c0 = matrix.columns.0
        let c1 = matrix.columns.1
        let c2 = matrix.columns.2
        let c3 = matrix.columns.3
        let ySign: Float = flipClipY ? -1.0 : 1.0
        return (
            c0.x, c1.x, c2.x, c3.x,
            c0.y * ySign, c1.y * ySign, c2.y * ySign, c3.y * ySign,
            c0.z, c1.z, c2.z, c3.z,
            c0.w, c1.w, c2.w, c3.w
        )
    }

    private static func packFloat4(_ v: SIMD4<Float>) -> (Float, Float, Float, Float) {
        return (v.x, v.y, v.z, v.w)
    }

    private static func makeGlobalUniforms(_ uniforms: GlobalUniforms) -> AcornRHIGlobalUniforms {
        return AcornRHIGlobalUniforms(
            modelViewProjectionMatrix: packRowMajor(uniforms.modelViewProjectionMatrix, flipClipY: true),
            modelMatrix: packRowMajor(uniforms.modelMatrix),
            normalMatrix: packRowMajor(uniforms.normalMatrix),
            ambientLightColor: packFloat4(uniforms.ambientLightColor),
            directionalLightColor: packFloat4(uniforms.directionalLightColor),
            directionalLightDirection: packFloat4(uniforms.directionalLightDirection),
            pointLightColor: packFloat4(uniforms.pointLightColor),
            pointLightPosition: packFloat4(uniforms.pointLightPosition),
            meshColor: packFloat4(uniforms.meshColor)
        )
    }

    private static func mapSurfacePixelFormat(_ format: SurfacePixelFormat) -> AcornRHIPixelFormat {
        switch format {
        case .bgra8Unorm: return ACORN_RHI_PIXEL_FORMAT_BGRA8_UNORM
        case .bgra8UnormSRGB: return ACORN_RHI_PIXEL_FORMAT_BGRA8_SRGB
        case .rgba8Unorm: return ACORN_RHI_PIXEL_FORMAT_RGBA8_UNORM
        }
    }

    private static func mapTextureFormat(_ format: TextureFormat) -> (AcornRHIPixelFormat, Int) {
        switch format {
        case .r8Unorm: return (ACORN_RHI_PIXEL_FORMAT_R8_UNORM, 1)
        case .rgba8Unorm: return (ACORN_RHI_PIXEL_FORMAT_RGBA8_UNORM, 4)
        case .bgra8Unorm: return (ACORN_RHI_PIXEL_FORMAT_BGRA8_UNORM, 4)
        }
    }

    // MARK: - Compiled Shader Loading

    private struct ShaderBinaryPair {
        let vertex: Data
        let fragment: Data
    }

    private struct CompiledShaderSet {
        let mesh: ShaderBinaryPair
        let skinnedMesh: ShaderBinaryPair
        let instancedMesh: ShaderBinaryPair
        let sdfText: ShaderBinaryPair
        let sprite: ShaderBinaryPair
        let instancedSprite: ShaderBinaryPair
        let road: ShaderBinaryPair

        func withRhiBundle<R>(_ body: (AcornRHIShaderBundle) -> R) -> R {
            let pairs = [mesh, skinnedMesh, instancedMesh, sdfText, sprite, instancedSprite, road]
            let retainedData: [NSData] = pairs.flatMap { [$0.vertex as NSData, $0.fragment as NSData] }

            return "vertexMain".withCString { vertEntry in
                "fragmentMain".withCString { fragEntry in
                    func makeBinary(_ pair: ShaderBinaryPair) -> AcornRHIShaderBinary {
                        let vPtr = (pair.vertex as NSData).bytes.assumingMemoryBound(to: UInt8.self)
                        let fPtr = (pair.fragment as NSData).bytes.assumingMemoryBound(to: UInt8.self)
                        return AcornRHIShaderBinary(
                            vertexCode: vPtr,
                            vertexSize: pair.vertex.count,
                            vertexEntry: vertEntry,
                            fragmentCode: fPtr,
                            fragmentSize: pair.fragment.count,
                            fragmentEntry: fragEntry
                        )
                    }

                    let bundle = AcornRHIShaderBundle(
                        mesh: makeBinary(mesh),
                        skinnedMesh: makeBinary(skinnedMesh),
                        instancedMesh: makeBinary(instancedMesh),
                        sdfText: makeBinary(sdfText),
                        sprite: makeBinary(sprite),
                        instancedSprite: makeBinary(instancedSprite),
                        road: makeBinary(road)
                    )
                    return withExtendedLifetime(retainedData) {
                        body(bundle)
                    }
                }
            }
        }
    }

    private static func platformShaderSubdirectory() throws -> String {
        #if os(iOS)
        return "CompiledShaders/ios"
        #elseif os(macOS)
        return "CompiledShaders/macos"
        #else
        throw RendererError.libraryNotFound
        #endif
    }

    /// Loads a compiled vertex/fragment shader binary pair from `Bundle.module` for the active platform.
    package static func loadCompiledShaderPair(prefix: String) throws -> (vertex: Data, fragment: Data) {
        let subdir = try platformShaderSubdirectory()
        let pair = try loadPair(prefix: prefix, subdirectory: subdir)
        return (pair.vertex, pair.fragment)
    }

    private static func loadCompiledShaderSet() throws -> CompiledShaderSet {
        let subdir = try platformShaderSubdirectory()

        return try CompiledShaderSet(
            mesh: loadPair(prefix: "mesh", subdirectory: subdir),
            skinnedMesh: loadPair(prefix: "skinned_mesh", subdirectory: subdir),
            instancedMesh: loadPair(prefix: "instanced_mesh", subdirectory: subdir),
            sdfText: loadPair(prefix: "sdf_text", subdirectory: subdir),
            sprite: loadPair(prefix: "sprite", subdirectory: subdir),
            instancedSprite: loadPair(prefix: "sprite_instanced", subdirectory: subdir),
            road: loadPair(prefix: "road", subdirectory: subdir)
        )
    }

    private static func loadPair(prefix: String, subdirectory: String) throws -> ShaderBinaryPair {
        let vertexURL = shaderURL(name: "\(prefix)_vertex", subdirectory: subdirectory)
        let fragmentURL = shaderURL(name: "\(prefix)_fragment", subdirectory: subdirectory)
        guard let vURL = vertexURL, let fURL = fragmentURL,
              let vData = try? Data(contentsOf: vURL),
              let fData = try? Data(contentsOf: fURL),
              !vData.isEmpty, !fData.isEmpty else {
            throw RendererError.libraryNotFound
        }
        return ShaderBinaryPair(vertex: vData, fragment: fData)
    }

    private static func shaderURL(name: String, subdirectory: String) -> URL? {
        if let url = Bundle.module.url(forResource: name, withExtension: "metallib", subdirectory: subdirectory) {
            return url
        }
        if let resURL = Bundle.module.resourceURL {
            let direct = resURL.appendingPathComponent(subdirectory).appendingPathComponent("\(name).metallib")
            if FileManager.default.fileExists(atPath: direct.path) {
                return direct
            }
        }
        return nil
    }
}
