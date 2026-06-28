import Testing
import Metal
@testable import AcornEngine

@MainActor
struct RendererTests {
    @Test("Renderer Initialization")
    func initialization() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            // No metal device available (e.g. in some CI environments), skip gracefully.
            return
        }
        
        let renderer = try MetalRenderer(device: device)
        _ = renderer
    }

    @Test("Mesh Creation")
    func meshCreation() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return
        }
        
        let renderer = try MetalRenderer(device: device)
        let vertices: [Vertex] = [
            Vertex(position: SIMD3<Float>(0, 0.5, 0), color: SIMD4<Float>(1, 0, 0, 1)),
            Vertex(position: SIMD3<Float>(-0.5, -0.5, 0), color: SIMD4<Float>(0, 1, 0, 1)),
            Vertex(position: SIMD3<Float>(0.5, -0.5, 0), color: SIMD4<Float>(0, 0, 1, 1))
        ]
        let mesh = try #require(renderer.createMesh(vertices: vertices) as? MetalMesh)
        #expect(mesh.vertexCount == 3)
        #expect(mesh.vertexBuffer.length > 0)
    }

    @Test("Texture Loader Raw Pixel Loading")
    func textureRawPixels() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return
        }
        
        let loader = TextureLoader(device: device)
        
        // Test 1-channel (R8Unorm) texture
        let width1 = 16
        let height1 = 16
        let pixels1 = [UInt8](repeating: 128, count: width1 * height1)
        let texture1 = try await loader.loadTexture(width: width1, height: height1, pixels: pixels1)
        
        #expect(texture1.width == width1)
        #expect(texture1.height == height1)
        if let metalTexture = texture1 as? MetalTexture {
            #expect(metalTexture.texture.pixelFormat == .r8Unorm)
        } else {
            Issue.record("Expected MetalTexture")
        }
        
        // Test 4-channel (RGBA8Unorm) texture
        let width4 = 8
        let height4 = 8
        let pixels4 = [UInt8](repeating: 255, count: width4 * height4 * 4)
        let texture4 = try await loader.loadTexture(width: width4, height: height4, pixels: pixels4)
        
        #expect(texture4.width == width4)
        #expect(texture4.height == height4)
        if let metalTexture = texture4 as? MetalTexture {
            #expect(metalTexture.texture.pixelFormat == .rgba8Unorm)
        } else {
            Issue.record("Expected MetalTexture")
        }
        
        // Test invalid dimensions
        let invalidPixels = [UInt8](repeating: 0, count: 10)
        await #expect(throws: TextureError.self) {
            _ = try await loader.loadTexture(width: 8, height: 8, pixels: invalidPixels)
        }
    }
}
