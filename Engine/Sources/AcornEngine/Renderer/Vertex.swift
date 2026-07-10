import simd

/// A vertex containing position, color, and texture coordinate information for rendering.
public struct Vertex: Sendable, Equatable {
    /// The 3D position of the vertex.
    public var position: SIMD3<Float>
    /// The RGBA color of the vertex.
    public var color: SIMD4<Float>
    /// The texture coordinates of the vertex.
    public var texCoord: SIMD2<Float>
    /// The normal vector of the vertex.
    public var normal: SIMD3<Float>

    /// Creates a new vertex.
    /// - Parameters:
    ///   - position: The 3D position.
    ///   - color: The RGBA color.
    ///   - texCoord: The texture coordinates (UV). Defaults to `.zero`.
    ///   - normal: The normal vector. Defaults to `(0, 0, 1)`.
    public init(position: SIMD3<Float>, color: SIMD4<Float>, texCoord: SIMD2<Float> = .zero, normal: SIMD3<Float> = SIMD3<Float>(0, 0, 1)) {
        self.position = position
        self.color = color
        self.texCoord = texCoord
        self.normal = normal
    }
}
