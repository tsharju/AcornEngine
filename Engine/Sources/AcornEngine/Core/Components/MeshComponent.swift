import Foundation

/// A component that holds a mesh for rendering.
public struct MeshComponent: Component {
    /// The mesh to render.
    public let mesh: any Mesh
    
    /// Initializes a new mesh component.
    /// - Parameter mesh: The mesh.
    public init(mesh: any Mesh) {
        self.mesh = mesh
    }
}
