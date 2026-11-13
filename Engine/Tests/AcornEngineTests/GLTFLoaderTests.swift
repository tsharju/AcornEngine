import Testing
import Foundation
@testable import AcornEngine

@MainActor
struct GLTFLoaderTests {
    @Test("Load Non-existent GLTF Model")
    func loadNonExistent() throws {
        let renderer = try NoGraphicsRenderer()
        let loader = GLTFModelLoader(renderer: renderer)
        let url = URL(fileURLWithPath: "/nonexistent/model.gltf")
        #expect(throws: Error.self) {
            _ = try loader.load(from: url)
        }
    }

    @Test("Load Real GLTF Model")
    func loadReal() throws {
        let fm = FileManager.default
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AcornEngineTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Engine
            .deletingLastPathComponent() // repo root
        let candidateURLs = [
            repoRoot.appendingPathComponent("Samples/AcornSampleApp/AcornSampleApp/Resources/Avocado.glb"),
            repoRoot.appendingPathComponent("Samples/Acorn3DSample/Acorn3DSample/Resources/Avocado.glb")
        ]

        let url = try #require(candidateURLs.first { fm.fileExists(atPath: $0.path) })

        let renderer = try NoGraphicsRenderer()
        let loader = GLTFModelLoader(renderer: renderer)
        let result = try loader.load(from: url)

        #expect(!result.meshes.isEmpty)
        #expect(!result.nodes.isEmpty)
        #expect(result.textureData != nil)

        let rootNodes = result.nodes.filter { $0.parentIndex == nil }
        #expect(!rootNodes.isEmpty)

        for mesh in result.meshes {
            #expect(mesh.vertexCount > 0)
            #expect(mesh as? NoGraphicsMesh != nil)
        }
    }
}
