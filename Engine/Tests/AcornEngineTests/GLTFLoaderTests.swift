import Testing
import Metal
import Foundation
@testable import AcornEngine

@MainActor
struct GLTFLoaderTests {
    @Test("Load Non-existent GLTF Model")
    func loadNonExistent() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return
        }
        
        let loader = GLTFModelLoader(device: device)
        let url = URL(fileURLWithPath: "/nonexistent/model.gltf")
        #expect(throws: Error.self) {
            _ = try loader.load(from: url)
        }
    }
}
