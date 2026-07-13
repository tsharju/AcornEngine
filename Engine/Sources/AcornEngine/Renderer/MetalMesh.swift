import Foundation
import Metal
import AcornMetal

/// A Metal implementation of a 3D mesh consisting of vertices, backed by a Metal buffer.
public final class MetalMesh: Mesh, @unchecked Sendable {
    /// The underlying C++ mesh object.
    public let cxxMesh: UnsafeMutablePointer<Acorn.AcornMetalMesh>
    
    /// The number of vertices in the mesh.
    public var vertexCount: Int {
        return Int(cxxMesh.pointee.getVertexCount())
    }

    #if DEBUG
    /// The CPU-side vertices of the mesh.
    public var vertices: [Vertex] {
        let debugVertsPtr = cxxMesh.pointee.getDebugVertexData()
        let count = Int(cxxMesh.pointee.getDebugVertexDataCount()) / 3
        var result = [Vertex]()
        result.reserveCapacity(count)
        for i in 0..<count {
            let x = debugVertsPtr![i * 3]
            let y = debugVertsPtr![i * 3 + 1]
            let z = debugVertsPtr![i * 3 + 2]
            result.append(Vertex(position: SIMD3<Float>(x, y, z), color: SIMD4<Float>(1, 1, 1, 1)))
        }
        return result
    }
    #endif
    
    /// Initializes from an existing C++ mesh pointer. Takes ownership.
    public init(cxxMesh: UnsafeMutablePointer<Acorn.AcornMetalMesh>) {
        self.cxxMesh = cxxMesh
    }

    /// Creates a mesh from an array of vertices.
    /// - Parameters:
    ///   - device: The Metal device used to create the buffers.
    ///   - vertices: An array of `Vertex` structures.
    /// - Returns: A new `MetalMesh`, or `nil` if buffer creation fails.
    public convenience init?(device: any MTLDevice, vertices: [Vertex]) {
        let size = vertices.count * MemoryLayout<Vertex>.stride
        guard let buffer = device.makeBuffer(bytes: vertices, length: size, options: .storageModeShared) else {
            return nil
        }
        
        let devicePtr = Unmanaged.passUnretained(device).toOpaque()
        let bufferPtr = Unmanaged.passUnretained(buffer).toOpaque()
        
        guard let mesh = Acorn.AcornMetalMesh.create(devicePtr, vertices.count, bufferPtr, nil, 0) else {
            return nil
        }
        self.init(cxxMesh: mesh)
    }
    
    deinit {
        cxxMesh.pointee.destroy()
    }
}
