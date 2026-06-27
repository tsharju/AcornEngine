import Foundation

/// An error that can occur during renderer initialization.
public enum RendererError: Error {
    /// Failed to create a command queue.
    case initializationFailed
    /// Failed to load the default Metal library.
    case libraryNotFound
    /// Failed to find the required shader functions.
    case functionNotFound
}


/// Opaque protocol representing a 3D mesh resource on the GPU.
public protocol Mesh: Sendable {
    /// The number of vertices in the mesh.
    var vertexCount: Int { get }
}

/// Opaque protocol representing the context for the current frame (e.g., command buffer, render target).
public protocol RenderContext: Sendable {}

/// The base protocol for all rendering backends.
public protocol Renderer: Sendable {
    /// Creates a backend-specific mesh resource from an array of vertices.
    /// - Parameter vertices: The vertices to use.
    /// - Returns: A backend-specific `Mesh` resource, or `nil` if creation fails.
    func createMesh(vertices: [Vertex]) -> Mesh?
    
    /// Renders a mesh using the given frame context.
    /// - Parameters:
    ///   - mesh: The mesh to render.
    ///   - context: The render context for the current frame.
    func render(mesh: Mesh, context: RenderContext)
}
