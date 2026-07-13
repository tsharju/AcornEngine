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
    
    @Test("Load Real GLTF Model")
    func loadReal() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return
        }
        
        let fm = FileManager.default
        let currentDir = fm.currentDirectoryPath
        let candidatePaths = [
            "../Samples/Acorn3DSample/Acorn3DSample/Resources/Avocado.glb",
            "../Samples/AcornSampleApp/AcornSampleApp/Resources/Avocado.glb"
        ]
        
        var avocadoUrl: URL?
        for path in candidatePaths {
            let fullPath = (currentDir as NSString).appendingPathComponent(path)
            if fm.fileExists(atPath: fullPath) {
                avocadoUrl = URL(fileURLWithPath: fullPath)
                break
            }
        }
        
        guard let url = avocadoUrl else {
            return
        }
        
        let loader = GLTFModelLoader(device: device)
        let result = try loader.load(from: url)
        
        #expect(result.meshes.count > 0)
        #expect(result.nodes.count > 0)
        #expect(result.textureData != nil)
        
        let rootNodes = result.nodes.filter { $0.parentIndex == nil }
        #expect(rootNodes.count > 0)
        
        for mesh in result.meshes {
            #expect(mesh.vertexCount > 0)
            #expect(mesh.vertexBuffer.length > 0)
        }
    }
}
