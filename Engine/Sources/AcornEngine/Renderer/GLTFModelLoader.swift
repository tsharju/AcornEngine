import Foundation
import Metal
import AcornMetal
import simd

/// Represents a node within a loaded glTF scene.
public struct GLTFNode: Sendable {
    /// The name of the node.
    public let name: String
    /// The index of the mesh this node contains, if any.
    public let meshIndex: Int?
    /// The index of the parent node in the returned nodes array, if any.
    public let parentIndex: Int?
    /// The local translation of the node.
    public let translation: SIMD3<Float>
    /// The local rotation quaternion (x, y, z, w).
    public let rotation: SIMD4<Float>
    /// The local scale of the node.
    public let scale: SIMD3<Float>
}

/// Converts a quaternion to XYZ Euler angles.
public func quaternionToEuler(_ q: SIMD4<Float>) -> SIMD3<Float> {
    // q = (x, y, z, w)
    let pitch = atan2(2 * (q.w * q.x + q.y * q.z), 1 - 2 * (q.x * q.x + q.y * q.y))
    let yaw = asin(max(-1.0, min(1.0, 2 * (q.w * q.y - q.z * q.x))))
    let roll = atan2(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z))
    return SIMD3<Float>(pitch, yaw, roll)
}

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
    /// - Returns: A tuple containing the loaded meshes, nodes, and the raw texture data, if any.
    /// - Throws: An error if loading fails.
    public func load(from url: URL) throws -> (meshes: [MetalMesh], nodes: [GLTFNode], textureData: Data?) {
        guard url.isFileURL else {
            throw NSError(domain: "GLTFModelLoaderErrorDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "Only file URLs are supported."])
        }

        let path = url.path
        let devicePtr = Unmanaged.passUnretained(device).toOpaque()

        // Allocate buffers to store output meshes and nodes
        var meshesPtrs = [UnsafeMutableRawPointer?](repeating: nil, count: 256)
        var nodesData = [Acorn.GLTFNodeData](repeating: Acorn.GLTFNodeData(), count: 256)
        var nodeCount: Int32 = 0
        var textureDataPtr: UnsafeRawPointer? = nil
        var textureSize: Int32 = 0
        
        let count = Int(Acorn.GLTFLoader.loadRaw(
            path, 
            devicePtr, 
            &meshesPtrs, 
            256, 
            &nodesData, 
            256, 
            &nodeCount, 
            &textureDataPtr, 
            &textureSize
        ))

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

        var nodes: [GLTFNode] = []
        nodes.reserveCapacity(Int(nodeCount))
        for i in 0..<Int(nodeCount) {
            let data = nodesData[i]
            
            // Extract string from char[64] name tuple
            var nameBytes = [Int8]()
            withUnsafePointer(to: data.name) { ptr in
                ptr.withMemoryRebound(to: Int8.self, capacity: 64) { reboundPtr in
                    nameBytes = Array(UnsafeBufferPointer(start: reboundPtr, count: 64))
                }
            }
            if let nullIndex = nameBytes.firstIndex(of: 0) {
                nameBytes = Array(nameBytes[..<nullIndex])
            }
            let nodeName = String(decoding: nameBytes.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            
            let meshIndex = data.meshIndex >= 0 ? Int(data.meshIndex) : nil
            let parentIndex = data.parentIndex >= 0 ? Int(data.parentIndex) : nil
            
            let translation = SIMD3<Float>(data.translation.0, data.translation.1, data.translation.2)
            let rotation = SIMD4<Float>(data.rotation.0, data.rotation.1, data.rotation.2, data.rotation.3)
            let scale = SIMD3<Float>(data.scale.0, data.scale.1, data.scale.2)
            
            nodes.append(GLTFNode(
                name: nodeName,
                meshIndex: meshIndex,
                parentIndex: parentIndex,
                translation: translation,
                rotation: rotation,
                scale: scale
            ))
        }

        var textureData: Data? = nil
        if let texPtr = textureDataPtr, textureSize > 0 {
            textureData = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: texPtr), count: Int(textureSize), deallocator: .free)
        }

        return (meshes, nodes, textureData)
    }
}
