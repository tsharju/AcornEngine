import Foundation

/// A component that holds a mesh for rendering.
public struct MeshComponent: Component {
    /// The mesh to render.
    public let mesh: any Mesh
    
    /// The global color tint applied to this mesh.
    public var color: SIMD4<Float>
    
    /// Initializes a new mesh component.
    /// - Parameters:
    ///   - mesh: The mesh.
    ///   - color: The base color of the mesh. Defaults to white.
    public init(mesh: any Mesh, color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)) {
        self.mesh = mesh
        self.color = color
    }
}
