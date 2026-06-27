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
        
        let renderer = try ForwardRenderer(device: device)
        _ = renderer
    }

    @Test("Mesh Creation")
    func meshCreation() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return
        }
        
        let mesh = try #require(Mesh.makeTriangle(device: device))
        #expect(mesh.vertexCount == 3)
        #expect(mesh.vertexBuffer.length > 0)
    }
}
