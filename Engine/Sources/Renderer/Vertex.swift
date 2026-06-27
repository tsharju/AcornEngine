import simd

/// A vertex containing position and color information for rendering.
public struct Vertex: Sendable, Equatable {
    /// The 3D position of the vertex.
    public var position: SIMD3<Float>
    /// The RGBA color of the vertex.
    public var color: SIMD4<Float>

    /// Creates a new vertex.
    /// - Parameters:
    ///   - position: The 3D position.
    ///   - color: The RGBA color.
    public init(position: SIMD3<Float>, color: SIMD4<Float>) {
        self.position = position
        self.color = color
    }
}
