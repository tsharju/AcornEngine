import Foundation
import Metal
import AcornMetal

/// A loader class responsible for loading glTF models from disk.
public final class GLTFModelLoader: Sendable {
    /// The Metal device to create mesh buffers on.
    private let device: any MTLDevice

    /// Initializes a new GLTFModelLoader.
    /// - Parameter device: The Metal device.
    public init(device: any MTLDevice) {
        self.device = device
    }

    /// Loads a glTF model from a local file URL.
    /// - Parameter url: The file URL of the model (.glb or .gltf).
    /// - Returns: A tuple containing the loaded meshes and the raw texture data, if any.
    /// - Throws: An error if loading fails.
    public func load(from url: URL) throws -> (meshes: [MetalMesh], textureData: Data?) {
        guard url.isFileURL else {
            throw NSError(domain: "GLTFModelLoaderErrorDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "Only file URLs are supported."])
        }

        let path = url.path
        let devicePtr = Unmanaged.passUnretained(device).toOpaque()

        // Allocate a buffer to store output meshes
        var meshesPtrs = [UnsafeMutableRawPointer?](repeating: nil, count: 128)
        var textureDataPtr: UnsafeRawPointer? = nil
        var textureSize: Int32 = 0
        
        let count = Int(Acorn.GLTFLoader.loadRaw(path, devicePtr, &meshesPtrs, 128, &textureDataPtr, &textureSize))

        guard count > 0 else {
            throw NSError(domain: "GLTFModelLoaderErrorDomain", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to load glTF meshes or file not found: \(path)"])
        }

        var meshes: [MetalMesh] = []
        meshes.reserveCapacity(count)
        for i in 0..<count {
            if let ptr = meshesPtrs[i] {
                let cxxMesh = ptr.assumingMemoryBound(to: Acorn.AcornMetalMesh.self)
                meshes.append(MetalMesh(cxxMesh: cxxMesh))
            }
        }

        var textureData: Data? = nil
        if let texPtr = textureDataPtr, textureSize > 0 {
            textureData = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: texPtr), count: Int(textureSize), deallocator: .free)
        }

        return (meshes, textureData)
    }
}
