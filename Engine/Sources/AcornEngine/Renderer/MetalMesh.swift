import Foundation
import Metal

/// A Metal implementation of a 3D mesh consisting of vertices, backed by a Metal buffer.
public struct MetalMesh: Mesh, @unchecked Sendable {
    /// The Metal buffer containing the vertex data.
    public let vertexBuffer: any MTLBuffer
    
    /// The number of vertices in the mesh.
    public let vertexCount: Int

    /// Creates a mesh from an array of vertices.
    /// - Parameters:
    ///   - device: The Metal device used to create the buffers.
    ///   - vertices: An array of `Vertex` structures.
    /// - Returns: A new `MetalMesh`, or `nil` if buffer creation fails.
    public init?(device: any MTLDevice, vertices: [Vertex]) {
        self.vertexCount = vertices.count
        let size = vertices.count * MemoryLayout<Vertex>.stride
        guard let buffer = device.makeBuffer(bytes: vertices, length: size, options: .storageModeShared) else {
            return nil
        }
        self.vertexBuffer = buffer
    }
}
