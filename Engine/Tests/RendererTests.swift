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
}
