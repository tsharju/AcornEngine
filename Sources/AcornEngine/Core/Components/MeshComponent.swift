import Foundation

/// A component that contains a renderable mesh.
public struct MeshComponent: Component {
    /// The mesh to render.
    public var mesh: Mesh
    
    /// Initializes a new mesh component.
    /// - Parameter mesh: The mesh.
    public init(mesh: Mesh) {
        self.mesh = mesh
    }
}
