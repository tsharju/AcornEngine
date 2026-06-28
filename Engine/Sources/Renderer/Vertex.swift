import simd

/// A vertex containing position, color, and texture coordinate information for rendering.
public struct Vertex: Sendable, Equatable {
    /// The 3D position of the vertex.
    public var position: SIMD3<Float>
    /// The RGBA color of the vertex.
    public var color: SIMD4<Float>
    /// The texture coordinates of the vertex.
    public var texCoord: SIMD2<Float>

    /// Creates a new vertex.
    /// - Parameters:
    ///   - position: The 3D position.
    ///   - color: The RGBA color.
    ///   - texCoord: The texture coordinates (UV). Defaults to `.zero`.
    public init(position: SIMD3<Float>, color: SIMD4<Float>, texCoord: SIMD2<Float> = .zero) {
        self.position = position
        self.color = color
        self.texCoord = texCoord
    }
}
