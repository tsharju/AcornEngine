#if canImport(Metal)
import Foundation
import Metal
internal import AcornMetal

/// A Metal implementation of a 3D mesh consisting of vertices, backed by a Metal buffer.
public final class MetalMesh: Mesh, @unchecked Sendable {
    /// The underlying C++ mesh object.
    package let cxxMesh: UnsafeMutablePointer<Acorn.AcornMetalMesh>
    
    /// The number of vertices in the mesh.
    public var vertexCount: Int {
        return Int(cxxMesh.pointee.getVertexCount())
    }

    /// The number of indices in the mesh, if indexed (0 for non-indexed meshes).
    public var indexCount: Int {
        return Int(cxxMesh.pointee.getIndexCount())
    }

    /// The underlying Metal vertex buffer.
    public var vertexBuffer: any MTLBuffer {
        let rawBuf = cxxMesh.pointee.getVertexBuffer()!
        return Unmanaged<any MTLBuffer>.fromOpaque(rawBuf).takeUnretainedValue()
    }

    /// The underlying Metal index buffer, if any.
    public var indexBuffer: (any MTLBuffer)? {
        guard let rawBuf = cxxMesh.pointee.getIndexBuffer() else {
            return nil
        }
        return Unmanaged<any MTLBuffer>.fromOpaque(rawBuf).takeUnretainedValue()
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
    package init(cxxMesh: UnsafeMutablePointer<Acorn.AcornMetalMesh>) {
        self.cxxMesh = cxxMesh
    }

    /// Creates a mesh from an array of vertices and optional indices.
    /// - Parameters:
    ///   - device: The Metal device used to create the buffers.
    ///   - vertices: An array of `Vertex` structures.
    ///   - indices: An optional array of 32-bit indices.
    /// - Returns: A new `MetalMesh`, or `nil` if buffer creation fails.
    public convenience init?(device: any MTLDevice, vertices: [Vertex], indices: [UInt32] = []) {
        let size = vertices.count * MemoryLayout<Vertex>.stride
        guard let buffer = device.makeBuffer(bytes: vertices, length: size, options: .storageModeShared) else {
            return nil
        }
        
        let iBuffer: (any MTLBuffer)?
        let iBufferPtr: UnsafeMutableRawPointer?
        if !indices.isEmpty {
            let iSize = indices.count * MemoryLayout<UInt32>.stride
            guard let ib = device.makeBuffer(bytes: indices, length: iSize, options: .storageModeShared) else {
                return nil
            }
            iBuffer = ib
            iBufferPtr = Unmanaged.passUnretained(ib).toOpaque()
        } else {
            iBuffer = nil
            iBufferPtr = nil
        }
        
        let devicePtr = Unmanaged.passUnretained(device).toOpaque()
        let bufferPtr = Unmanaged.passUnretained(buffer).toOpaque()
        
        guard let mesh = Acorn.AcornMetalMesh.create(devicePtr, vertices.count, bufferPtr, iBufferPtr, indices.count) else {
            return nil
        }
        _ = (buffer, iBuffer)
        self.init(cxxMesh: mesh)
    }

    /// Creates a mesh from an array of vertices.
    /// - Parameters:
    ///   - device: The Metal device used to create the buffers.
    ///   - vertices: An array of `Vertex` structures.
    /// - Returns: A new `MetalMesh`, or `nil` if buffer creation fails.
    public convenience init?(device: any MTLDevice, vertices: [Vertex]) {
        self.init(device: device, vertices: vertices, indices: [])
    }
    
    deinit {
        cxxMesh.pointee.destroy()
    }
}
#endif

