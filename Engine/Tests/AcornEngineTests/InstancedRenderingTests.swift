import Testing
import Metal
import simd
import Foundation
@testable import AcornEngine

// MARK: - Mocks

private final class MockMesh: Mesh, @unchecked Sendable {
    var vertexCount: Int
    #if DEBUG
    var vertices: [Vertex]
    #endif
    
    init(vertexCount: Int = 3, vertices: [Vertex] = []) {
        self.vertexCount = vertexCount
        #if DEBUG
        self.vertices = vertices
        #endif
    }
}

private final class MockTexture: Texture, @unchecked Sendable {
    var width: Int
    var height: Int
    
    init(width: Int = 100, height: Int = 100) {
        self.width = width
        self.height = height
    }
}

private final class MockRenderContext: RenderContext, @unchecked Sendable {}

private final class MockRenderer: Renderer, @unchecked Sendable {
    var renderCallCount = 0
    var renderInstancedCallCount = 0
    var renderedInstanceBatches: [[MeshInstanceData]] = []
    
    var renderSpriteCallCount = 0
    var renderSpritesInstancedCallCount = 0
    var renderedSpriteBatches: [[SpriteInstanceData]] = []
    
    var lastFrameUniforms: FrameUniforms?
    var lastSpriteFrameUniforms: SpriteFrameUniforms?
    
    var unitQuadMesh: (any Mesh)? = MockMesh(vertexCount: 6)
    
    func createMesh(vertices: [Vertex]) -> (any Mesh)? {
        return MockMesh(vertexCount: vertices.count, vertices: vertices)
    }
    
    func render(mesh: any Mesh, texture: (any Texture)?, uniforms: GlobalUniforms, context: any RenderContext) {
        renderCallCount += 1
    }
    
    func renderText(mesh: any Mesh, texture: any Texture, uniforms: SDFUniforms, context: any RenderContext) {}
    
    func renderSprite(mesh: any Mesh, texture: any Texture, uniforms: SpriteUniforms, context: any RenderContext) {
        renderSpriteCallCount += 1
    }
    
    func renderInstanced(
        mesh: any Mesh,
        texture: (any Texture)?,
        instances: [MeshInstanceData],
        uniforms: FrameUniforms,
        context: any RenderContext
    ) {
        renderInstancedCallCount += 1
        renderedInstanceBatches.append(instances)
        lastFrameUniforms = uniforms
    }
    
    func renderSpritesInstanced(
        mesh: any Mesh,
        texture: any Texture,
        instances: [SpriteInstanceData],
        uniforms: SpriteFrameUniforms,
        context: any RenderContext
    ) {
        renderSpritesInstancedCallCount += 1
        renderedSpriteBatches.append(instances)
        lastSpriteFrameUniforms = uniforms
    }
}

// MARK: - Test Suite

@MainActor
struct InstancedRenderingTests {
    
    @Test("Memory Layout and 16-byte Alignment")
    func testMemoryLayoutAndAlignment() {
        #expect(MemoryLayout<FrameUniforms>.alignment == 16)
        #expect(MemoryLayout<FrameUniforms>.size == 144)
        #expect(MemoryLayout<FrameUniforms>.stride == 144)
        
        #expect(MemoryLayout<MeshInstanceData>.alignment == 16)
        #expect(MemoryLayout<MeshInstanceData>.size == 144)
        #expect(MemoryLayout<MeshInstanceData>.stride == 144)
        
        #expect(MemoryLayout<SpriteFrameUniforms>.alignment == 16)
        #expect(MemoryLayout<SpriteFrameUniforms>.size == 64)
        #expect(MemoryLayout<SpriteFrameUniforms>.stride == 64)
        
        #expect(MemoryLayout<SpriteInstanceData>.alignment == 16)
        #expect(MemoryLayout<SpriteInstanceData>.size == 96)
        #expect(MemoryLayout<SpriteInstanceData>.stride == 96)
        
        // Initializer default checks
        let frameUniforms = FrameUniforms()
        #expect(frameUniforms.viewProjectionMatrix == .identity)
        #expect(frameUniforms.ambientLightColor == .zero)
        #expect(frameUniforms.directionalLightColor == .zero)
        #expect(frameUniforms.directionalLightDirection == SIMD4<Float>(0, -1, 0, 0))
        #expect(frameUniforms.pointLightColor == .zero)
        #expect(frameUniforms.pointLightPosition == .zero)
        
        let meshInstance = MeshInstanceData()
        #expect(meshInstance.modelMatrix == .identity)
        #expect(meshInstance.normalMatrix == .identity)
        #expect(meshInstance.color == SIMD4<Float>(1, 1, 1, 1))
        
        let spriteFrameUniforms = SpriteFrameUniforms()
        #expect(spriteFrameUniforms.viewProjectionMatrix == .identity)
        
        let spriteInstance = SpriteInstanceData()
        #expect(spriteInstance.modelMatrix == .identity)
        #expect(spriteInstance.colorTint == SIMD4<Float>(1, 1, 1, 1))
        #expect(spriteInstance.uvRect == SIMD4<Float>(0, 0, 1, 1))
    }
    
    @Test("SpriteMeshGenerator generateUnitQuad")
    func testGenerateUnitQuad() {
        let vertices = SpriteMeshGenerator.generateUnitQuad()
        #expect(vertices.count == 6)
        
        for vertex in vertices {
            #expect(vertex.position.x >= -0.5 && vertex.position.x <= 0.5)
            #expect(vertex.position.y >= -0.5 && vertex.position.y <= 0.5)
            #expect(vertex.position.z == 0.0)
            #expect(vertex.texCoord.x >= 0.0 && vertex.texCoord.x <= 1.0)
            #expect(vertex.texCoord.y >= 0.0 && vertex.texCoord.y <= 1.0)
            #expect(vertex.color == SIMD4<Float>(1, 1, 1, 1))
        }
    }
    
    @Test("SpriteMeshGenerator uvRect")
    func testUVRectCalculation() {
        let texture = MockTexture(width: 256, height: 512)
        let meta = SpriteSheetMeta(
            app: "TexturePacker",
            version: "1.0",
            image: "sprites.png",
            format: "RGBA8888",
            size: SpriteSize(w: 256, h: 512),
            scale: "1"
        )
        let frame1 = SpriteFrame(
            filename: "player_idle.png",
            frame: SpriteRect(x: 32, y: 64, w: 64, h: 128),
            rotated: false,
            trimmed: false,
            spriteSourceSize: SpriteRect(x: 0, y: 0, w: 64, h: 128),
            sourceSize: SpriteSize(w: 64, h: 128)
        )
        let metadata = SpriteSheetMetadata(frames: [frame1], meta: meta)
        let sheet = SpriteSheet(texture: texture, metadata: metadata)
        
        let uv = SpriteMeshGenerator.uvRect(for: "player_idle.png", in: sheet)
        // uMin = 32 / 256 = 0.125
        // vMin = 64 / 512 = 0.125
        // uMax = (32 + 64) / 256 = 96 / 256 = 0.375
        // vMax = (64 + 128) / 512 = 192 / 512 = 0.375
        #expect(abs(uv.x - 0.125) < 0.0001)
        #expect(abs(uv.y - 0.125) < 0.0001)
        #expect(abs(uv.z - 0.375) < 0.0001)
        #expect(abs(uv.w - 0.375) < 0.0001)
        
        // Missing frame fallback
        let fallbackUV = SpriteMeshGenerator.uvRect(for: "missing_frame.png", in: sheet)
        #expect(fallbackUV == SIMD4<Float>(0, 0, 1, 1))
    }
    
    @Test("RenderSystem batches 100 mesh entities into a single instanced draw call")
    func testRenderSystemBatches100MeshEntities() {
        let mockRenderer = MockRenderer()
        let renderSystem = RenderSystem(renderer: mockRenderer)
        let world = World()
        
        let mesh = MockMesh(vertexCount: 36)
        let texture = MockTexture(width: 128, height: 128)
        
        // Create 100 entities with same mesh and texture
        for i in 0..<100 {
            let entity = world.createEntity()
            world.addComponent(
                TransformComponent(
                    position: SIMD3<Float>(Float(i), 0, 0),
                    rotation: SIMD3<Float>(0, 0, 0),
                    scale: SIMD3<Float>(1, 1, 1)
                ),
                to: entity
            )
            world.addComponent(
                MeshComponent(
                    mesh: mesh,
                    color: SIMD4<Float>(1, 0, 0, 1),
                    texture: texture
                ),
                to: entity
            )
        }
        
        let context = MockRenderContext()
        renderSystem.render(world: world, context: context)
        
        #expect(mockRenderer.renderInstancedCallCount == 1)
        #expect(mockRenderer.renderedInstanceBatches.count == 1)
        #expect(mockRenderer.renderedInstanceBatches[0].count == 100)
        #expect(mockRenderer.renderCallCount == 0)
    }
    
    @Test("RenderSystem batches distinct mesh/texture pairs into separate instanced draw calls")
    func testRenderSystemBatchesMultipleMeshGroups() {
        let mockRenderer = MockRenderer()
        let renderSystem = RenderSystem(renderer: mockRenderer)
        let world = World()
        
        let meshA = MockMesh(vertexCount: 12)
        let meshB = MockMesh(vertexCount: 24)
        let textureA = MockTexture(width: 64, height: 64)
        let textureB = MockTexture(width: 128, height: 128)
        
        // 50 of meshA + textureA
        for _ in 0..<50 {
            let e = world.createEntity()
            world.addComponent(TransformComponent(position: .zero), to: e)
            world.addComponent(MeshComponent(mesh: meshA, texture: textureA), to: e)
        }
        // 30 of meshB + textureB
        for _ in 0..<30 {
            let e = world.createEntity()
            world.addComponent(TransformComponent(position: .zero), to: e)
            world.addComponent(MeshComponent(mesh: meshB, texture: textureB), to: e)
        }
        // 20 of meshA + textureB
        for _ in 0..<20 {
            let e = world.createEntity()
            world.addComponent(TransformComponent(position: .zero), to: e)
            world.addComponent(MeshComponent(mesh: meshA, texture: textureB), to: e)
        }
        
        let context = MockRenderContext()
        renderSystem.render(world: world, context: context)
        
        #expect(mockRenderer.renderInstancedCallCount == 3)
        let counts = mockRenderer.renderedInstanceBatches.map { $0.count }
        #expect(counts.sorted() == [20, 30, 50])
    }
    
    @Test("RenderSystem batches contiguous sprite entities into single instanced sprite draw calls")
    func testRenderSystemBatchesContiguousSprites() {
        let mockRenderer = MockRenderer()
        let renderSystem = RenderSystem(renderer: mockRenderer)
        let world = World()
        
        let textureA = MockTexture(width: 100, height: 100)
        let textureB = MockTexture(width: 200, height: 200)
        
        let metaA = SpriteSheetMeta(app: "tp", version: "1.0", image: "a.png", format: "RGBA", size: SpriteSize(w: 100, h: 100), scale: "1")
        let frameA = SpriteFrame(filename: "fA", frame: SpriteRect(x: 0, y: 0, w: 50, h: 50), rotated: false, trimmed: false, spriteSourceSize: SpriteRect(x: 0, y: 0, w: 50, h: 50), sourceSize: SpriteSize(w: 50, h: 50))
        let sheetA = SpriteSheet(texture: textureA, metadata: SpriteSheetMetadata(frames: [frameA], meta: metaA))
        
        let metaB = SpriteSheetMeta(app: "tp", version: "1.0", image: "b.png", format: "RGBA", size: SpriteSize(w: 200, h: 200), scale: "1")
        let frameB = SpriteFrame(filename: "fB", frame: SpriteRect(x: 0, y: 0, w: 100, h: 100), rotated: false, trimmed: false, spriteSourceSize: SpriteRect(x: 0, y: 0, w: 100, h: 100), sourceSize: SpriteSize(w: 100, h: 100))
        let sheetB = SpriteSheet(texture: textureB, metadata: SpriteSheetMetadata(frames: [frameB], meta: metaB))
        
        // 30 sprites of sheetA at Z = 0
        for _ in 0..<30 {
            let e = world.createEntity()
            world.addComponent(TransformComponent(position: SIMD3<Float>(0, 0, 0)), to: e)
            world.addComponent(SpriteComponent(spriteSheet: sheetA, frameName: "fA"), to: e)
        }
        
        // 20 sprites of sheetB at Z = 1
        for _ in 0..<20 {
            let e = world.createEntity()
            world.addComponent(TransformComponent(position: SIMD3<Float>(0, 0, 1)), to: e)
            world.addComponent(SpriteComponent(spriteSheet: sheetB, frameName: "fB"), to: e)
        }
        
        // 50 sprites of sheetA at Z = 2
        for _ in 0..<50 {
            let e = world.createEntity()
            world.addComponent(TransformComponent(position: SIMD3<Float>(0, 0, 2)), to: e)
            world.addComponent(SpriteComponent(spriteSheet: sheetA, frameName: "fA"), to: e)
        }
        
        let context = MockRenderContext()
        renderSystem.render(world: world, context: context)
        
        #expect(mockRenderer.renderSpritesInstancedCallCount == 3)
        let counts = mockRenderer.renderedSpriteBatches.map { $0.count }
        #expect(counts == [30, 20, 50])
        #expect(mockRenderer.renderSpriteCallCount == 0)
    }
    
    @Test("MetalRenderer Instanced Execution with Real GPU")
    func testMetalRendererInstancedExecution() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return
        }
        
        let renderer = try MetalRenderer(device: device)
        let world = World()
        let renderSystem = RenderSystem(renderer: renderer)
        
        let vertices = [
            Vertex(position: SIMD3<Float>(0, 0.5, 0), color: SIMD4<Float>(1, 0, 0, 1)),
            Vertex(position: SIMD3<Float>(-0.5, -0.5, 0), color: SIMD4<Float>(0, 1, 0, 1)),
            Vertex(position: SIMD3<Float>(0.5, -0.5, 0), color: SIMD4<Float>(0, 0, 1, 1))
        ]
        let mesh = try #require(renderer.createMesh(vertices: vertices))
        
        for i in 0..<50 {
            let e = world.createEntity()
            world.addComponent(TransformComponent(position: SIMD3<Float>(Float(i), 0, 0)), to: e)
            world.addComponent(MeshComponent(mesh: mesh), to: e)
        }
        
        let commandQueue = try #require(device.makeCommandQueue())
        let commandBuffer = try #require(commandQueue.makeCommandBuffer())
        let rpDescriptor = MTLRenderPassDescriptor()
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 64, height: 64, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        let dummyTarget = try #require(device.makeTexture(descriptor: texDesc))
        rpDescriptor.colorAttachments[0].texture = dummyTarget
        
        let context = MetalRenderContext(renderPassDescriptor: rpDescriptor, commandBuffer: commandBuffer)
        
        renderSystem.render(world: world, context: context)
        context.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}
