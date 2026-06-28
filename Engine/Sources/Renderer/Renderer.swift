import Foundation
import simd

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

/// Uniforms used by the SDF text shader.
public struct SDFUniforms: Sendable, Equatable {
    /// The text body color.
    public var textColor: SIMD4<Float>
    /// The text outline color.
    public var outlineColor: SIMD4<Float>
    /// The width of the outline (0.0 to 0.5).
    public var outlineWidth: Float
    /// The edge smoothing factor for anti-aliasing.
    public var edgeWidth: Float
    /// The translation applied to the text vertices.
    public var translation: SIMD4<Float>
    /// The scale applied to the text vertices.
    public var scale: SIMD4<Float>
    
    /// Initializes a new set of SDF rendering uniforms.
    public init(
        textColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        outlineColor: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1),
        outlineWidth: Float = 0.0,
        edgeWidth: Float = 0.05,
        translation: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 0),
        scale: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    ) {
        self.textColor = textColor
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
        self.edgeWidth = edgeWidth
        self.translation = translation
        self.scale = scale
    }
}

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
    
    /// Renders text using signed distance field shaders.
    /// - Parameters:
    ///   - mesh: The mesh containing character quads.
    ///   - texture: The texture containing the SDF font atlas.
    ///   - uniforms: The SDF outline/color parameters.
    ///   - context: The render context.
    func renderText(
        mesh: Mesh,
        texture: any Texture,
        uniforms: SDFUniforms,
        context: RenderContext
    )
}
