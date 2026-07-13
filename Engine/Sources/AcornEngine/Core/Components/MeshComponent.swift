import Foundation

/// A component that holds a mesh for rendering.
public struct MeshComponent: Component {
    /// The mesh to render.
    public let mesh: any Mesh
    
    /// The global color tint applied to this mesh.
    public var color: SIMD4<Float>
    
    /// The texture applied to this mesh.
    public var texture: (any Texture)?
    
    /// Initializes a new mesh component.
    /// - Parameters:
    ///   - mesh: The mesh.
    ///   - color: The base color of the mesh. Defaults to white.
    ///   - texture: The texture. Defaults to nil.
    public init(mesh: any Mesh, color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1), texture: (any Texture)? = nil) {
        self.mesh = mesh
        self.color = color
        self.texture = texture
    }
}
