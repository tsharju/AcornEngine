import Testing
import Foundation
import AcornMath
@testable import AcornEngine
#if canImport(Metal)
import Metal
#endif

// MARK: - Mock Types for Platform-Agnostic Verification

private final class MockMesh: Mesh, @unchecked Sendable {
    let vertexCount: Int
    #if DEBUG
    let vertices: [Vertex]
    #endif
    
    init(vertexCount: Int, vertices: [Vertex] = []) {
        self.vertexCount = vertexCount
        #if DEBUG
        self.vertices = vertices
        #endif
    }
}

private final class MockTexture: Texture, @unchecked Sendable {
    let width: Int
    let height: Int
    let format: TextureFormat
    let data: [UInt8]
    
    init(width: Int, height: Int, format: TextureFormat, data: [UInt8]) {
        self.width = width
        self.height = height
        self.format = format
        self.data = data
    }
}

private final class MockRenderContext: RenderContext, @unchecked Sendable {}

private struct MockImageDecoder: ImageDecoder {
    let width: Int
    let height: Int
    let pixels: [UInt8]
    
    func decode(data: Data) -> (width: Int, height: Int, pixels: [UInt8])? {
        guard !data.isEmpty else { return nil }
        return (width: width, height: height, pixels: pixels)
    }
}

private final class MockPlatformAgnosticRenderer: Renderer, @unchecked Sendable {
    var createdMeshes: [MockMesh] = []
    var createdTextures: [MockTexture] = []
    var renderedMeshesCount = 0
    var unitQuadMesh: (any Mesh)? = MockMesh(vertexCount: 6)
    
    func createMesh(vertices: [Vertex]) -> (any Mesh)? {
        let mesh = MockMesh(vertexCount: vertices.count, vertices: vertices)
        createdMeshes.append(mesh)
        return mesh
    }
    
    func createTexture(width: Int, height: Int, pixelData: [UInt8], format: TextureFormat) -> (any Texture)? {
        let texture = MockTexture(width: width, height: height, format: format, data: pixelData)
        createdTextures.append(texture)
        return texture
    }
    
    func render(mesh: any Mesh, texture: (any Texture)?, uniforms: GlobalUniforms, context: any RenderContext) {
        renderedMeshesCount += 1
    }
    
    func renderText(mesh: any Mesh, texture: any Texture, uniforms: SDFUniforms, context: any RenderContext) {}
    func renderSprite(mesh: any Mesh, texture: any Texture, uniforms: SpriteUniforms, context: any RenderContext) {}
    func renderInstanced(mesh: any Mesh, texture: (any Texture)?, instances: [MeshInstanceData], uniforms: FrameUniforms, context: any RenderContext) {}
    func renderSpritesInstanced(mesh: any Mesh, texture: any Texture, instances: [SpriteInstanceData], uniforms: SpriteFrameUniforms, context: any RenderContext) {}
}

// MARK: - Test Suite

@Suite("Android Rendering Architecture Tests")
struct AndroidRenderingArchitectureTests {
    
    // MARK: 1. CPUMeshData & Renderer Abstraction
    
    @Test("CPUMeshData storage and Renderer.createMesh(meshData:) integration")
    func testCPUMeshDataAndCreation() {
        let vertices = [
            Vertex(position: SIMD3<Float>(0, 1, 0), color: SIMD4<Float>(1, 0, 0, 1)),
            Vertex(position: SIMD3<Float>(-1, -1, 0), color: SIMD4<Float>(0, 1, 0, 1)),
            Vertex(position: SIMD3<Float>(1, -1, 0), color: SIMD4<Float>(0, 0, 1, 1))
        ]
        let indices: [UInt32] = [0, 1, 2]
        
        let meshData = CPUMeshData(vertices: vertices, indices: indices)
        #expect(meshData.vertices.count == 3)
        #expect(meshData.indices == indices)
        
        let renderer = MockPlatformAgnosticRenderer()
        let createdMesh = renderer.createMesh(meshData: meshData)
        let typedMesh = try? #require(createdMesh as? MockMesh)
        #expect(typedMesh?.vertexCount == 3)
        #expect(renderer.createdMeshes.count == 1)
    }
    
    // MARK: 2. VulkanRenderer Stub Architecture
    
    @Test("VulkanRenderer conformance and stub behaviors")
    func testVulkanRendererArchitecture() {
        let vulkanRenderer = VulkanRenderer()
        #expect(vulkanRenderer.unitQuadMesh == nil)
        
        let vertices = [Vertex(position: .zero, color: .one)]
        #expect(vulkanRenderer.createMesh(vertices: vertices) == nil)
        #expect(vulkanRenderer.createMesh(meshData: CPUMeshData(vertices: vertices)) == nil)
        #expect(vulkanRenderer.createTexture(width: 4, height: 4, pixelData: [], format: .rgba8Unorm) == nil)
        
        // Ensure calling render functions on stub doesn't crash
        let context = VulkanRenderContext()
        let mesh = VulkanMesh(vertexCount: 0)
        let texture = VulkanTexture(width: 0, height: 0)
        
        vulkanRenderer.render(mesh: mesh, texture: texture, uniforms: GlobalUniforms(), context: context)
        vulkanRenderer.renderText(mesh: mesh, texture: texture, uniforms: SDFUniforms(), context: context)
        vulkanRenderer.renderSprite(mesh: mesh, texture: texture, uniforms: SpriteUniforms(), context: context)
        vulkanRenderer.renderInstanced(mesh: mesh, texture: texture, instances: [], uniforms: FrameUniforms(), context: context)
        vulkanRenderer.renderSpritesInstanced(mesh: mesh, texture: texture, instances: [], uniforms: SpriteFrameUniforms(), context: context)
        
        #expect(context.commandBuffer == nil)
        #expect(context.framebuffer == nil)
        #expect(mesh.vertexCount == 0)
        #expect(texture.width == 0)
        #expect(texture.height == 0)
    }
    
    // MARK: 3. FontRasterizer Protocol & CoreText Implementation
    
    #if canImport(CoreText) && canImport(CoreGraphics)
    @Test("CoreTextFontRasterizer metrics and character rasterization")
    func testCoreTextFontRasterizer() throws {
        let rasterizer = CoreTextFontRasterizer()
        let metrics = try rasterizer.metrics(fontName: "Helvetica", fontSize: 24.0)
        
        #expect(metrics.ascent > 0)
        #expect(metrics.lineHeight > metrics.ascent)
        
        let chars: Set<Character> = ["A", " "]
        let result = try rasterizer.rasterize(fontName: "Helvetica", fontSize: 24.0, characters: chars, cellSize: 64)
        
        #expect(result.glyphs.count >= 2)
        let glyphA = try #require(result.glyphs["A"])
        #expect(glyphA.char == "A")
        #expect(glyphA.xAdvance > 0)
        #expect(glyphA.grayscalePixels != nil)
        #expect(glyphA.grayscalePixels?.count == 64 * 64)
        
        let glyphSpace = try #require(result.glyphs[" "])
        #expect(glyphSpace.char == " ")
        #expect(glyphSpace.xAdvance > 0)
        #expect(glyphSpace.grayscalePixels == nil)
    }
    #endif
    
    // MARK: 4. SDFFontAtlasGenerator Decoupled from Metal
    
    @Test("SDFFontAtlasGenerator using abstract Renderer")
    func testSDFFontAtlasGeneratorWithAbstractRenderer() throws {
        let renderer = MockPlatformAgnosticRenderer()
        let chars: Set<Character> = ["A", "B", "C"]
        
        let atlas = try SDFFontAtlasGenerator.generate(
            fontName: "Helvetica",
            fontSize: 20.0,
            characters: chars,
            renderer: renderer,
            cellSize: 32,
            searchRadius: 4.0
        )
        
        #expect(atlas.fontSize == 20.0)
        #expect(atlas.lineHeight > 0)
        #expect(atlas.glyphs.count == 3)
        #expect(atlas.glyphs["A"] != nil)
        #expect(atlas.glyphs["B"] != nil)
        #expect(atlas.glyphs["C"] != nil)
        
        // Assert that the texture was created via renderer.createTexture
        #expect(renderer.createdTextures.count == 1)
        let createdTexture = renderer.createdTextures[0]
        #expect(createdTexture.format == .r8Unorm)
        #expect(createdTexture.width >= 32)
        #expect(createdTexture.height >= 32)
    }
    
    // MARK: 5. TextureLoader Decoupled with Abstract Renderer
    
    @Test("TextureLoader loading raw pixels using Renderer")
    func testTextureLoaderWithAbstractRenderer() async throws {
        let renderer = MockPlatformAgnosticRenderer()
        let loader = TextureLoader(renderer: renderer)
        
        let width = 4
        let height = 4
        
        // 1. R8Unorm
        let r8Pixels = [UInt8](repeating: 255, count: width * height)
        let r8Texture = try await loader.loadTexture(width: width, height: height, pixels: r8Pixels, format: .r8Unorm)
        #expect(r8Texture.width == width)
        #expect(r8Texture.height == height)
        #expect(renderer.createdTextures.count == 1)
        #expect(renderer.createdTextures.last?.format == .r8Unorm)
        
        // 2. RGBA8Unorm
        let rgbaPixels = [UInt8](repeating: 128, count: width * height * 4)
        let rgbaTexture = try await loader.loadTexture(width: width, height: height, pixels: rgbaPixels, format: .rgba8Unorm)
        #expect(rgbaTexture.width == width)
        #expect(rgbaTexture.height == height)
        #expect(renderer.createdTextures.count == 2)
        #expect(renderer.createdTextures.last?.format == .rgba8Unorm)
        
        // 3. BGRA8Unorm
        let bgraPixels = [UInt8](repeating: 64, count: width * height * 4)
        let bgraTexture = try await loader.loadTexture(width: width, height: height, pixels: bgraPixels, format: .bgra8Unorm)
        #expect(bgraTexture.width == width)
        #expect(bgraTexture.height == height)
        #expect(renderer.createdTextures.count == 3)
        #expect(renderer.createdTextures.last?.format == .bgra8Unorm)
    }
    
    // MARK: 6. Engine Lifecycle Events & Delta-time Clamping
    
    @MainActor
    @Test("Engine lifecycle events, pause/resume, delta-time clamping, and surface gating")
    func testEngineLifecycle() {
        let renderer = MockPlatformAgnosticRenderer()
        let engine = Engine(renderer: renderer)
        
        var pauseEventsReceived = 0
        var resumeEventsReceived = 0
        var surfaceCreatedEventsReceived = 0
        var surfaceDestroyedEventsReceived = 0
        
        _ = engine.world.eventBus.subscribe(to: AppPauseEvent.self) { _ in
            pauseEventsReceived += 1
        }
        _ = engine.world.eventBus.subscribe(to: AppResumeEvent.self) { _ in
            resumeEventsReceived += 1
        }
        _ = engine.world.eventBus.subscribe(to: SurfaceCreatedEvent.self) { _ in
            surfaceCreatedEventsReceived += 1
        }
        _ = engine.world.eventBus.subscribe(to: SurfaceDestroyedEvent.self) { _ in
            surfaceDestroyedEventsReceived += 1
        }
        
        // Initial state
        #expect(!engine.isPaused)
        #expect(engine.isSurfaceAvailable)
        
        // Pause lifecycle
        engine.pause()
        #expect(engine.isPaused)
        #expect(pauseEventsReceived == 1)
        
        // Ticking while paused should not advance tick event
        var ticksReceived = 0
        _ = engine.world.eventBus.subscribe(to: EngineTickEvent.self) { _ in
            ticksReceived += 1
        }
        engine.tick(deltaTime: 0.016)
        #expect(ticksReceived == 0)
        
        // Resume lifecycle
        engine.resume()
        #expect(!engine.isPaused)
        #expect(resumeEventsReceived == 1)
        
        // Ticking while unpaused with large deltaTime clamps to maxDeltaTime
        var lastDelta: Double = 0.0
        _ = engine.world.eventBus.subscribe(to: EngineTickEvent.self) { event in
            lastDelta = event.deltaTime
        }
        engine.tick(deltaTime: 5.0) // Huge spike, e.g. resuming after long background
        #expect(lastDelta == engine.maxDeltaTime)
        #expect(lastDelta == 0.1)
        
        // Surface lifecycle: surface destruction halts rendering
        let context = MockRenderContext()
        engine.render(context: context)
        #expect(renderer.renderedMeshesCount == 0) // No entities in world, but render executed
        
        engine.surfaceDestroyed()
        #expect(!engine.isSurfaceAvailable)
        #expect(surfaceDestroyedEventsReceived == 1)
        
        // Attempting to render while surface is destroyed must immediately exit
        engine.render(context: context)
        
        // Restoring surface allows rendering again
        engine.surfaceCreated()
        #expect(engine.isSurfaceAvailable)
        #expect(surfaceCreatedEventsReceived == 1)
    }
    
    // MARK: 7. MetalRenderer Indexed Mesh Creation from CPUMeshData
    
    #if canImport(Metal)
    @MainActor
    @Test("MetalRenderer creates indexed mesh from CPUMeshData with valid indexBuffer and indexCount")
    func testMetalRendererIndexedMesh() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let renderer = try MetalRenderer(device: device)
        
        let vertices = [
            Vertex(position: SIMD3<Float>(0, 0, 0), color: SIMD4<Float>(1, 1, 1, 1)),
            Vertex(position: SIMD3<Float>(1, 0, 0), color: SIMD4<Float>(1, 1, 1, 1)),
            Vertex(position: SIMD3<Float>(0, 1, 0), color: SIMD4<Float>(1, 1, 1, 1))
        ]
        let indices: [UInt32] = [0, 1, 2]
        
        let indexedData = CPUMeshData(vertices: vertices, indices: indices)
        let indexedMesh = renderer.createMesh(meshData: indexedData)
        let metalMesh = try #require(indexedMesh as? MetalMesh)
        #expect(metalMesh.vertexCount == 3)
        #expect(metalMesh.indexCount == 3)
        #expect(metalMesh.indexBuffer != nil)
        
        let nonIndexedData = CPUMeshData(vertices: vertices, indices: [])
        let nonIndexedMesh = renderer.createMesh(meshData: nonIndexedData)
        let metalNonIndexedMesh = try #require(nonIndexedMesh as? MetalMesh)
        #expect(metalNonIndexedMesh.vertexCount == 3)
        #expect(metalNonIndexedMesh.indexCount == 0)
        #expect(metalNonIndexedMesh.indexBuffer == nil)
    }
    #endif
    
    // MARK: 8. SDFFontAtlasGenerator Division-by-Zero & Validation
    
    @Test("SDFFontAtlasGenerator avoids division by zero and rejects invalid cell/font sizes")
    func testSDFFontAtlasEdgeCases() throws {
        let renderer = MockPlatformAgnosticRenderer()
        
        // 1. Cell size larger than 512 (previously caused cellsPerRow = 0 and fatal division by zero)
        let largeCellAtlas = try SDFFontAtlasGenerator.generate(
            fontName: "Helvetica",
            fontSize: 24.0,
            characters: ["A"],
            renderer: renderer,
            cellSize: 1024,
            searchRadius: 4.0
        )
        #expect(largeCellAtlas.glyphs["A"] != nil)
        #expect(renderer.createdTextures.last?.width ?? 0 >= 1024)
        
        // 2. Cell size <= 0 must throw invalidCellSize rather than crashing
        #expect(throws: SDFFontAtlasGeneratorError.invalidCellSize) {
            _ = try SDFFontAtlasGenerator.generate(
                fontName: "Helvetica",
                fontSize: 24.0,
                characters: ["A"],
                renderer: renderer,
                cellSize: 0
            )
        }
        
        // 3. Font size <= 0 must throw invalidFontSize
        #expect(throws: SDFFontAtlasGeneratorError.invalidFontSize) {
            _ = try SDFFontAtlasGenerator.generate(
                fontName: "Helvetica",
                fontSize: 0.0,
                characters: ["A"],
                renderer: renderer,
                cellSize: 64
            )
        }
    }
    
    // MARK: 9. ImageDecoder & TextureLoader Dimensions Validation
    
    @Test("TextureLoader with custom ImageDecoder and dimension validation")
    func testCustomImageDecoderAndValidation() async throws {
        let renderer = MockPlatformAgnosticRenderer()
        let fakePixels = [UInt8](repeating: 200, count: 2 * 2 * 4)
        let mockDecoder = MockImageDecoder(width: 2, height: 2, pixels: fakePixels)
        
        let loader = TextureLoader(renderer: renderer, imageDecoder: mockDecoder)
        let loadedTexture = try await loader.loadTexture(from: Data([0xDE, 0xAD, 0xBE, 0xEF]))
        
        #expect(loadedTexture.width == 2)
        #expect(loadedTexture.height == 2)
        #expect(renderer.createdTextures.count == 1)
        #expect(renderer.createdTextures.first?.format == .rgba8Unorm)
        
        // Zero dimensions must throw invalidDimensions
        do {
            _ = try await loader.loadTexture(width: 0, height: 4, pixels: [], format: .rgba8Unorm)
            #expect(Bool(false), "Expected invalidDimensions error")
        } catch let error as TextureError {
            #expect(error == .invalidDimensions)
        }
        
        // Byte size mismatch must throw invalidDimensions
        do {
            _ = try await loader.loadTexture(width: 4, height: 4, pixels: [1, 2, 3], format: .rgba8Unorm)
            #expect(Bool(false), "Expected invalidDimensions error")
        } catch let error as TextureError {
            #expect(error == .invalidDimensions)
        }
    }
    
    // MARK: 10. Engine.pause() Resets Input State
    
    @MainActor
    @Test("Engine.pause() resets active inputs per Android lifecycle specification")
    func testEnginePauseResetsInputState() {
        let renderer = MockPlatformAgnosticRenderer()
        let engine = Engine(renderer: renderer)
        
        engine.inputSystem.state.recordKeyDown(.space, modifiers: [])
        engine.inputSystem.state.recordTouchBegan(Touch(id: 1, position: .zero, phase: .began))
        #expect(engine.inputSystem.state.isKeyDown(.space))
        #expect(engine.inputSystem.state.hasActiveTouches)
        
        engine.pause()
        #expect(engine.isPaused)
        #expect(!engine.inputSystem.state.isKeyDown(.space))
        #expect(engine.inputSystem.state.currentHeldKeys.isEmpty)
        #expect(!engine.inputSystem.state.hasActiveTouches)
    }
    
    // MARK: 11. VulkanMesh & VulkanTexture Properties
    
    @Test("VulkanMesh and VulkanTexture property completeness")
    func testVulkanMeshAndTextureProperties() {
        let mesh = VulkanMesh(vertexCount: 4, indexCount: 6)
        #expect(mesh.vertexCount == 4)
        #expect(mesh.indexCount == 6)
        #expect(mesh.buffer == nil)
        #expect(mesh.indexBuffer == nil)
        
        let texture = VulkanTexture(width: 128, height: 128, format: .bgra8Unorm)
        #expect(texture.width == 128)
        #expect(texture.height == 128)
        #expect(texture.format == .bgra8Unorm)
        #expect(texture.image == nil)
        #expect(texture.imageView == nil)
    }
    
    // MARK: 12. GLTFModelLoader with Abstract Renderer
    
    @Test("GLTFModelLoader with abstract Renderer")
    func testGLTFModelLoaderWithRenderer() throws {
        let mockRenderer = MockPlatformAgnosticRenderer()
        let loader = GLTFModelLoader(renderer: mockRenderer)
        let dummyUrl = URL(fileURLWithPath: "/nonexistent/model.glb")
        
        #expect(throws: Error.self) {
            _ = try loader.loadMeshes(from: dummyUrl)
        }
        
        #if canImport(Metal)
        if let device = MTLCreateSystemDefaultDevice() {
            let metalRenderer = try MetalRenderer(device: device)
            let metalLoader = GLTFModelLoader(renderer: metalRenderer)
            
            let fm = FileManager.default
            let currentDir = fm.currentDirectoryPath
            let candidatePaths = [
                "../Samples/Acorn3DSample/Acorn3DSample/Resources/Avocado.glb",
                "../Samples/AcornSampleApp/AcornSampleApp/Resources/Avocado.glb"
            ]
            for path in candidatePaths {
                let fullPath = (currentDir as NSString).appendingPathComponent(path)
                if fm.fileExists(atPath: fullPath) {
                    let result = try metalLoader.loadMeshes(from: URL(fileURLWithPath: fullPath))
                    #expect(!result.meshes.isEmpty)
                    #expect(!result.nodes.isEmpty)
                    break
                }
            }
        }
        #endif
    }
}
