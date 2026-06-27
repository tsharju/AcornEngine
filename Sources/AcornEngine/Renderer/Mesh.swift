import Foundation
import Metal

/// A 3D mesh consisting of vertices, backed by a Metal buffer.
public struct Mesh: @unchecked Sendable {
    /// The Metal buffer containing the vertex data.
    public let vertexBuffer: any MTLBuffer
    
    /// The number of vertices in the mesh.
    public let vertexCount: Int

    /// Creates a mesh from an array of vertices.
    /// - Parameters:
    ///   - device: The Metal device used to create the buffers.
    ///   - vertices: An array of `Vertex` structures.
    /// - Returns: A new `Mesh`, or `nil` if buffer creation fails.
    public init?(device: any MTLDevice, vertices: [Vertex]) {
        self.vertexCount = vertices.count
        let size = vertices.count * MemoryLayout<Vertex>.stride
        guard let buffer = device.makeBuffer(bytes: vertices, length: size, options: .storageModeShared) else {
            return nil
        }
        self.vertexBuffer = buffer
    }
    
    /// Creates a simple colored triangle mesh.
    /// - Parameter device: The Metal device.
    /// - Returns: A triangle `Mesh`, or `nil` if creation fails.
    public static func makeTriangle(device: any MTLDevice) -> Mesh? {
        let vertices: [Vertex] = [
            Vertex(position: SIMD3<Float>(0, 0.5, 0), color: SIMD4<Float>(1, 0, 0, 1)),
            Vertex(position: SIMD3<Float>(-0.5, -0.5, 0), color: SIMD4<Float>(0, 1, 0, 1)),
            Vertex(position: SIMD3<Float>(0.5, -0.5, 0), color: SIMD4<Float>(0, 0, 1, 1))
        ]
        return Mesh(device: device, vertices: vertices)
    }
}
