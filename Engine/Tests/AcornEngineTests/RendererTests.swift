import Testing
import Foundation
import AcornMath
@testable import AcornEngine

@MainActor
struct RendererTests {
    @Test("NoGraphicsRenderer Headless Initialization")
    func initialization() throws {
        let renderer = try NoGraphicsRenderer()
        #expect(!renderer.deviceName.isEmpty)
        #expect(renderer.resizeSurface(width: 640, height: 480))
        #expect(!renderer.resizeSurface(width: 0, height: 480))
    }

    @Test("Mesh Creation and Indexed Mesh Bounds")
    func meshCreation() throws {
        let renderer = try NoGraphicsRenderer()
        let vertices: [Vertex] = [
            Vertex(position: SIMD3<Float>(0, 0.5, 0), color: SIMD4<Float>(1, 0, 0, 1)),
            Vertex(position: SIMD3<Float>(-0.5, -0.5, 0), color: SIMD4<Float>(0, 1, 0, 1)),
            Vertex(position: SIMD3<Float>(0.5, -0.5, 0), color: SIMD4<Float>(0, 0, 1, 1))
        ]
        let mesh = try #require(renderer.createMesh(vertices: vertices) as? NoGraphicsMesh)
        #expect(mesh.vertexCount == 3)
        #expect(mesh.indexCount == 0)
        #expect(!mesh.isSkinned)

        let indexed = try #require(
            renderer.createMesh(meshData: CPUMeshData(vertices: vertices, indices: [0, 1, 2])) as? NoGraphicsMesh
        )
        #expect(indexed.vertexCount == 3)
        #expect(indexed.indexCount == 3)
        #expect(renderer.createMesh(vertices: []) == nil)
    }

    @Test("Texture Loader Raw Pixel Loading")
    func textureRawPixels() async throws {
        let renderer = try NoGraphicsRenderer()
        let loader = TextureLoader(renderer: renderer)

        // Test 1-channel (R8Unorm) texture
        let width1 = 16
        let height1 = 16
        let pixels1 = [UInt8](repeating: 128, count: width1 * height1)
        let texture1 = try await loader.loadTexture(width: width1, height: height1, pixels: pixels1)

        #expect(texture1.width == width1)
        #expect(texture1.height == height1)
        let ngR8 = try #require(texture1 as? NoGraphicsTexture)
        #expect(ngR8.format == .r8Unorm)

        // Test 4-channel (RGBA8Unorm) texture
        let width4 = 8
        let height4 = 8
        let pixels4 = [UInt8](repeating: 255, count: width4 * height4 * 4)
        let texture4 = try await loader.loadTexture(width: width4, height: height4, pixels: pixels4)

        #expect(texture4.width == width4)
        #expect(texture4.height == height4)
        let ngRGBA = try #require(texture4 as? NoGraphicsTexture)
        #expect(ngRGBA.format == .rgba8Unorm)

        // Test invalid dimensions
        let invalidPixels = [UInt8](repeating: 0, count: 10)
        await #expect(throws: TextureError.self) {
            _ = try await loader.loadTexture(width: 8, height: 8, pixels: invalidPixels)
        }
    }

    @Test("Renderer Protocol createTexture & TextureLoader(renderer:)")
    func rendererCreateTexture() async throws {
        let renderer = try NoGraphicsRenderer()

        // 1. Direct renderer createTexture with r8Unorm
        let r8Pixels = [UInt8](repeating: 200, count: 4 * 4)
        let r8Texture = renderer.createTexture(width: 4, height: 4, pixelData: r8Pixels, format: .r8Unorm)
        let ngR8 = try #require(r8Texture as? NoGraphicsTexture)
        #expect(ngR8.width == 4)
        #expect(ngR8.height == 4)
        #expect(ngR8.format == .r8Unorm)

        // 2. Direct renderer createTexture with rgba8Unorm
        let rgbaPixels = [UInt8](repeating: 100, count: 4 * 4 * 4)
        let rgbaTexture = renderer.createTexture(width: 4, height: 4, pixelData: rgbaPixels, format: .rgba8Unorm)
        let ngRGBA = try #require(rgbaTexture as? NoGraphicsTexture)
        #expect(ngRGBA.width == 4)
        #expect(ngRGBA.height == 4)
        #expect(ngRGBA.format == .rgba8Unorm)

        // 3. TextureLoader using any Renderer
        let loader = TextureLoader(renderer: renderer)
        let loadedTexture = try await loader.loadTexture(width: 4, height: 4, pixels: rgbaPixels)
        #expect(loadedTexture.width == 4)
        #expect(loadedTexture.height == 4)
    }

    @Test("Matrix Row-Major Packing and Clip-Space Y-Flip")
    func matrixPackingAndClipYFlip() {
        #expect(MemoryLayout<Vertex>.stride == 64)

        let matrix = Matrix4x4(
            SIMD4<Float>(1, 2, 3, 4),
            SIMD4<Float>(5, 6, 7, 8),
            SIMD4<Float>(9, 10, 11, 12),
            SIMD4<Float>(13, 14, 15, 16)
        )

        let worldPacked = NoGraphicsRenderer.packRowMajor(matrix, flipClipY: false)
        #expect(worldPacked.0 == 1 && worldPacked.1 == 5 && worldPacked.2 == 9 && worldPacked.3 == 13)
        #expect(worldPacked.4 == 2 && worldPacked.5 == 6 && worldPacked.6 == 10 && worldPacked.7 == 14)
        #expect(worldPacked.8 == 3 && worldPacked.9 == 7 && worldPacked.10 == 11 && worldPacked.11 == 15)
        #expect(worldPacked.12 == 4 && worldPacked.13 == 8 && worldPacked.14 == 12 && worldPacked.15 == 16)

        let clipPacked = NoGraphicsRenderer.packRowMajor(matrix, flipClipY: true)
        #expect(clipPacked.0 == 1 && clipPacked.1 == 5 && clipPacked.2 == 9 && clipPacked.3 == 13)
        #expect(clipPacked.4 == -2 && clipPacked.5 == -6 && clipPacked.6 == -10 && clipPacked.7 == -14)
        #expect(clipPacked.8 == 3 && clipPacked.9 == 7 && clipPacked.10 == 11 && clipPacked.11 == 15)
        #expect(clipPacked.12 == 4 && clipPacked.13 == 8 && clipPacked.14 == 12 && clipPacked.15 == 16)
    }

    @Test("Headless GPU Frame Execution Across All 7 Pipelines")
    func headlessAllPipelinesExecution() throws {
        let renderer = try NoGraphicsRenderer()
        let context = try #require(renderer.beginFrame(clearColor: SIMD4<Float>(0.1, 0.2, 0.3, 1.0)))

        let quad = [
            Vertex(position: SIMD3<Float>(-0.5, -0.5, 0), color: SIMD4<Float>(1, 1, 1, 1), texCoord: SIMD2<Float>(0, 1)),
            Vertex(position: SIMD3<Float>(0.5, -0.5, 0), color: SIMD4<Float>(1, 1, 1, 1), texCoord: SIMD2<Float>(1, 1)),
            Vertex(position: SIMD3<Float>(0.5, 0.5, 0), color: SIMD4<Float>(1, 1, 1, 1), texCoord: SIMD2<Float>(1, 0)),
            Vertex(position: SIMD3<Float>(-0.5, 0.5, 0), color: SIMD4<Float>(1, 1, 1, 1), texCoord: SIMD2<Float>(0, 0))
        ]
        let mesh = try #require(renderer.createMesh(meshData: CPUMeshData(vertices: quad, indices: [0, 1, 2, 0, 2, 3])))
        let tex = try #require(renderer.createTexture(width: 2, height: 2, pixelData: [UInt8](repeating: 255, count: 16), format: .rgba8Unorm))
        let r8Tex = try #require(renderer.createTexture(width: 2, height: 2, pixelData: [UInt8](repeating: 200, count: 4), format: .r8Unorm))

        renderer.render(mesh: mesh, texture: nil, uniforms: GlobalUniforms(), context: context)
        renderer.render(mesh: mesh, texture: tex, uniforms: GlobalUniforms(), context: context)
        renderer.renderInstanced(mesh: mesh, texture: tex, instances: [MeshInstanceData()], uniforms: FrameUniforms(), context: context)
        renderer.renderText(mesh: mesh, texture: r8Tex, uniforms: SDFUniforms(), context: context)
        renderer.renderSprite(mesh: mesh, texture: tex, uniforms: SpriteUniforms(), context: context)
        let unitQuad = try #require(renderer.unitQuadMesh)
        renderer.renderSpritesInstanced(mesh: unitQuad, texture: tex, instances: [SpriteInstanceData()], uniforms: SpriteFrameUniforms(), context: context)
        renderer.renderRoads(mesh: mesh, texture: nil, uniforms: RoadUniforms(renderMode: 1.0), context: context)
        renderer.renderRoads(mesh: mesh, texture: tex, uniforms: RoadUniforms(renderMode: 0.0), context: context)

        struct RawSkinnedVertex {
            var pos: (Float, Float, Float) = (0, 0, 0)
            var padPos: Float = 0
            var col: (Float, Float, Float, Float) = (1, 1, 1, 1)
            var uv: (Float, Float) = (0, 0)
            var joints: (UInt16, UInt16, UInt16, UInt16) = (0, 0, 0, 0)
            var norm: (Float, Float, Float) = (0, 0, 1)
            var padNorm: Float = 0
            var weights: (Float, Float, Float, Float) = (1, 0, 0, 0)
        }
        let skinnedData = [RawSkinnedVertex(), RawSkinnedVertex(), RawSkinnedVertex()].withUnsafeBufferPointer { Data(buffer: $0) }
        let skinnedMesh = try #require(renderer.createSkinnedMesh(skinnedVertexData: skinnedData, vertexCount: 3, indices: [0, 1, 2]))
        renderer.renderSkinned(mesh: skinnedMesh, texture: nil, uniforms: GlobalUniforms(), jointMatrices: [.identity], context: context)

        renderer.endFrame(context: context)
        renderer.waitIdle()
    }

    @Test("Headless Two-Pass Offscreen Color+Depth & Fullscreen Post-Process Execution")
    func headlessOffscreenAndPostProcessExecution() throws {
        let renderer = try NoGraphicsRenderer()
        let shaderPair = try NoGraphicsRenderer.loadCompiledShaderPair(prefix: "postprocess_passthrough")
        let pipeline = try #require(
            renderer.createPostProcessPipeline(
                vertexShaderData: shaderPair.vertex,
                fragmentShaderData: shaderPair.fragment
            )
        )
        let target = try #require(renderer.createOffscreenTarget(width: 128, height: 128))
        #expect(target.width == 128)
        #expect(target.height == 128)
        #expect(renderer.createOffscreenTarget(width: 0, height: 128) == nil)
        #expect(!renderer.resizeOffscreenTarget(target, width: 0, height: 128))
        #expect(renderer.resizeOffscreenTarget(target, width: 256, height: 192))
        #expect(target.width == 256)
        #expect(target.height == 192)

        let triangle = [
            Vertex(position: SIMD3<Float>(0, 0.5, 0.2), color: SIMD4<Float>(1, 0, 0, 1)),
            Vertex(position: SIMD3<Float>(-0.5, -0.5, 0.2), color: SIMD4<Float>(0, 1, 0, 1)),
            Vertex(position: SIMD3<Float>(0.5, -0.5, 0.2), color: SIMD4<Float>(0, 0, 1, 1))
        ]
        let mesh = try #require(renderer.createMesh(vertices: triangle))

        let firstContext = try #require(
            renderer.beginOffscreenFrame(target: target, clearColor: SIMD4<Float>(0.3, 0.34, 0.32, 1.0))
        )
        renderer.render(mesh: mesh, texture: nil, uniforms: GlobalUniforms(), context: firstContext)
        renderer.beginPostProcessPass(context: firstContext)
        renderer.renderPostProcess(
            pipeline: pipeline,
            target: target,
            uniforms: SIMD4<Float>(0.2, 0.8, 0.3, 0.5),
            context: firstContext
        )
        renderer.endFrame(context: firstContext)

        // Verify a second frame after another resize retires previous offscreen textures cleanly
        #expect(renderer.resizeSurface(width: 320, height: 240))
        let secondContext = try #require(
            renderer.beginOffscreenFrame(target: target, clearColor: SIMD4<Float>(0.1, 0.2, 0.3, 1.0))
        )
        #expect(target.width == 320)
        #expect(target.height == 240)
        renderer.render(mesh: mesh, texture: nil, uniforms: GlobalUniforms(), context: secondContext)
        renderer.beginPostProcessPass(context: secondContext)
        renderer.renderPostProcess(
            pipeline: pipeline,
            target: target,
            uniforms: SIMD4<Float>(0.0, 0.0, 0.0, 0.0),
            context: secondContext
        )
        renderer.endFrame(context: secondContext)
        renderer.waitIdle()
    }
}
