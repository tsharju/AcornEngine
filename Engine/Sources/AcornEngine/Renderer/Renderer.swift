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
    
    #if DEBUG
    /// The CPU-side vertices of the mesh.
    var vertices: [Vertex] { get }
    #endif
}

/// Opaque protocol representing the context for the current frame (e.g., command buffer, render target).
public protocol RenderContext: Sendable {}

/// Global uniforms passed to the renderer.
public struct GlobalUniforms: Sendable, Equatable {
    /// The combined model-view-projection matrix.
    public var modelViewProjectionMatrix: simd_float4x4
    
    /// The model matrix.
    public var modelMatrix: simd_float4x4
    
    /// The normal matrix (inverse transpose of model matrix).
    public var normalMatrix: simd_float4x4
    
    /// The ambient light color.
    public var ambientLightColor: SIMD4<Float>
    
    /// The directional light color.
    public var directionalLightColor: SIMD4<Float>
    
    /// The directional light direction.
    public var directionalLightDirection: SIMD4<Float>
    
    /// The point light color.
    public var pointLightColor: SIMD4<Float>
    
    /// The point light position.
    public var pointLightPosition: SIMD4<Float>
    
    /// The mesh color tint.
    public var meshColor: SIMD4<Float>
    
    /// Initializes a new set of global uniforms.
    public init(
        modelViewProjectionMatrix: simd_float4x4 = .identity,
        modelMatrix: simd_float4x4 = .identity,
        normalMatrix: simd_float4x4 = .identity,
        ambientLightColor: SIMD4<Float> = SIMD4<Float>(repeating: 0.0),
        directionalLightColor: SIMD4<Float> = SIMD4<Float>(repeating: 0.0),
        directionalLightDirection: SIMD4<Float> = SIMD4<Float>(0, -1, 0, 0),
        pointLightColor: SIMD4<Float> = SIMD4<Float>(repeating: 0.0),
        pointLightPosition: SIMD4<Float> = SIMD4<Float>(repeating: 0.0),
        meshColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    ) {
        self.modelViewProjectionMatrix = modelViewProjectionMatrix
        self.modelMatrix = modelMatrix
        self.normalMatrix = normalMatrix
        self.ambientLightColor = ambientLightColor
        self.directionalLightColor = directionalLightColor
        self.directionalLightDirection = directionalLightDirection
        self.pointLightColor = pointLightColor
        self.pointLightPosition = pointLightPosition
        self.meshColor = meshColor
    }
}

/// Uniforms used by the sprite shader.
public struct SpriteUniforms: Sendable, Equatable {
    /// The combined model-view-projection matrix.
    public var modelViewProjectionMatrix: simd_float4x4
    /// A global color tint for the sprite.
    public var colorTint: SIMD4<Float>
    
    /// Initializes a new set of sprite uniforms.
    public init(modelViewProjectionMatrix: simd_float4x4 = .identity, colorTint: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)) {
        self.modelViewProjectionMatrix = modelViewProjectionMatrix
        self.colorTint = colorTint
    }
}

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
    /// Padding.
    public var padding: SIMD2<Float>
    /// The combined model-view-projection matrix.
    public var modelViewProjectionMatrix: simd_float4x4
    
    /// Initializes a new set of SDF rendering uniforms.
    public init(
        textColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        outlineColor: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1),
        outlineWidth: Float = 0.0,
        edgeWidth: Float = 0.05,
        modelViewProjectionMatrix: simd_float4x4 = .identity
    ) {
        self.textColor = textColor
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
        self.edgeWidth = edgeWidth
        self.padding = .zero
        self.modelViewProjectionMatrix = modelViewProjectionMatrix
    }
}

/// Frame-level uniforms for 3D rendering passes.
public struct FrameUniforms: Sendable, Equatable {
    /// The camera view-projection matrix.
    public var viewProjectionMatrix: simd_float4x4
    /// The ambient light color.
    public var ambientLightColor: SIMD4<Float>
    /// The directional light color.
    public var directionalLightColor: SIMD4<Float>
    /// The directional light direction.
    public var directionalLightDirection: SIMD4<Float>
    /// The point light color.
    public var pointLightColor: SIMD4<Float>
    /// The point light position.
    public var pointLightPosition: SIMD4<Float>
    
    /// Initializes a new set of frame uniforms.
    public init(
        viewProjectionMatrix: simd_float4x4 = .identity,
        ambientLightColor: SIMD4<Float> = SIMD4<Float>(repeating: 0.0),
        directionalLightColor: SIMD4<Float> = SIMD4<Float>(repeating: 0.0),
        directionalLightDirection: SIMD4<Float> = SIMD4<Float>(0, -1, 0, 0),
        pointLightColor: SIMD4<Float> = SIMD4<Float>(repeating: 0.0),
        pointLightPosition: SIMD4<Float> = SIMD4<Float>(repeating: 0.0)
    ) {
        self.viewProjectionMatrix = viewProjectionMatrix
        self.ambientLightColor = ambientLightColor
        self.directionalLightColor = directionalLightColor
        self.directionalLightDirection = directionalLightDirection
        self.pointLightColor = pointLightColor
        self.pointLightPosition = pointLightPosition
    }
}

/// Per-instance data for instanced 3D mesh rendering.
public struct MeshInstanceData: Sendable, Equatable {
    /// The model transformation matrix.
    public var modelMatrix: simd_float4x4
    /// The normal matrix (inverse transpose of model matrix).
    public var normalMatrix: simd_float4x4
    /// The color tint for this instance.
    public var color: SIMD4<Float>
    
    /// Initializes instance data for a 3D mesh.
    public init(
        modelMatrix: simd_float4x4 = .identity,
        normalMatrix: simd_float4x4 = .identity,
        color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    ) {
        self.modelMatrix = modelMatrix
        self.normalMatrix = normalMatrix
        self.color = color
    }
}

/// Frame-level uniforms for 2D sprite rendering passes.
public struct SpriteFrameUniforms: Sendable, Equatable {
    /// The camera view-projection matrix.
    public var viewProjectionMatrix: simd_float4x4
    
    /// Initializes sprite frame uniforms.
    public init(viewProjectionMatrix: simd_float4x4 = .identity) {
        self.viewProjectionMatrix = viewProjectionMatrix
    }
}

/// Per-instance data for instanced 2D sprite rendering.
public struct SpriteInstanceData: Sendable, Equatable {
    /// The model transformation matrix.
    public var modelMatrix: simd_float4x4
    /// The color tint for this sprite instance.
    public var colorTint: SIMD4<Float>
    /// The normalized UV rectangle (uMin, vMin, uMax, vMax).
    public var uvRect: SIMD4<Float>
    
    /// Initializes instance data for a 2D sprite.
    public init(
        modelMatrix: simd_float4x4 = .identity,
        colorTint: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        uvRect: SIMD4<Float> = SIMD4<Float>(0, 0, 1, 1)
    ) {
        self.modelMatrix = modelMatrix
        self.colorTint = colorTint
        self.uvRect = uvRect
    }
}

/// The base protocol for all rendering backends.
public protocol Renderer: Sendable {
    /// A shared unit quad mesh used for 2D sprite batching.
    var unitQuadMesh: (any Mesh)? { get }
    
    /// Creates a backend-specific mesh resource from an array of vertices.
    /// - Parameter vertices: The vertices to use.
    /// - Returns: A backend-specific `Mesh` resource, or `nil` if creation fails.
    func createMesh(vertices: [Vertex]) -> Mesh?
    
    /// Renders a mesh using the given frame context.
    /// - Parameters:
    ///   - mesh: The mesh to render.
    ///   - texture: An optional texture to map onto the mesh.
    ///   - uniforms: The global uniforms (e.g. view-projection).
    ///   - context: The render context for the current frame.
    func render(mesh: Mesh, texture: (any Texture)?, uniforms: GlobalUniforms, context: RenderContext)
    
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
    
    /// Renders a sprite or tile map using a sprite sheet texture.
    /// - Parameters:
    ///   - mesh: The mesh containing quads.
    ///   - texture: The texture containing the sprite sheet.
    ///   - uniforms: The sprite parameters.
    ///   - context: The render context.
    func renderSprite(
        mesh: Mesh,
        texture: any Texture,
        uniforms: SpriteUniforms,
        context: RenderContext
    )
    
    /// Renders multiple instances of a mesh in a single draw call.
    /// - Parameters:
    ///   - mesh: The mesh to render.
    ///   - texture: An optional texture to map onto the mesh.
    ///   - instances: Per-instance transform and color data.
    ///   - uniforms: Global frame uniforms (view-projection and lights).
    ///   - context: The render context for the current frame.
    func renderInstanced(
        mesh: any Mesh,
        texture: (any Texture)?,
        instances: [MeshInstanceData],
        uniforms: FrameUniforms,
        context: any RenderContext
    )
    
    /// Renders multiple sprite instances using a shared mesh and texture atlas in a single draw call.
    /// - Parameters:
    ///   - mesh: The unit quad mesh.
    ///   - texture: The sprite sheet texture.
    ///   - instances: Per-instance transform, color tint, and UV rectangle data.
    ///   - uniforms: Sprite frame uniforms.
    ///   - context: The render context for the current frame.
    func renderSpritesInstanced(
        mesh: any Mesh,
        texture: any Texture,
        instances: [SpriteInstanceData],
        uniforms: SpriteFrameUniforms,
        context: any RenderContext
    )
}

public extension Renderer {
    var unitQuadMesh: (any Mesh)? {
        return createMesh(vertices: SpriteMeshGenerator.generateUnitQuad())
    }
    
    func render(mesh: Mesh, uniforms: GlobalUniforms, context: RenderContext) {
        render(mesh: mesh, texture: nil, uniforms: uniforms, context: context)
    }
    
    func renderInstanced(
        mesh: any Mesh,
        texture: (any Texture)?,
        instances: [MeshInstanceData],
        uniforms: FrameUniforms,
        context: any RenderContext
    ) {}
    
    func renderSpritesInstanced(
        mesh: any Mesh,
        texture: any Texture,
        instances: [SpriteInstanceData],
        uniforms: SpriteFrameUniforms,
        context: any RenderContext
    ) {}
}
