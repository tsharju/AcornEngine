import Foundation

/// ECS component that identifies an entity as containing a ground surface mesh
/// (e.g. flat landuse, water, or terrain overlay) rendered in Stage 1 before roads.
public struct GroundMeshComponent: Component, Sendable {
    /// The GPU mesh for the ground surface.
    public var mesh: any Mesh
    
    /// The base color tint applied to this ground mesh.
    public var color: SIMD4<Float>
    
    /// Optional texture applied to this ground mesh.
    public var texture: (any Texture)?
    
    /// Initializes a new ground mesh component.
    /// - Parameters:
    ///   - mesh: The mesh.
    ///   - color: Base color tint (defaults to white).
    ///   - texture: Optional texture.
    public init(
        mesh: any Mesh,
        color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        texture: (any Texture)? = nil
    ) {
        self.mesh = mesh
        self.color = color
        self.texture = texture
    }
}
