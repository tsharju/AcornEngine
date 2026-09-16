import Foundation
import AcornMath

/// A component that holds a skinned mesh, texture, base color, skin index, and computed joint transformation matrices for GPU skeletal animation.
public struct SkinnedMeshComponent: Component, Sendable {
    /// The skinned mesh to render.
    public let mesh: any Mesh
    
    /// The global color tint applied to this mesh.
    public var color: SIMD4<Float>
    
    /// The texture applied to this mesh.
    public var texture: (any Texture)?
    
    /// Index of the skin in the model's skins array.
    public var skinIndex: Int
    
    /// Per-joint transformation matrices in model/mesh-local space for the current frame.
    public var jointMatrices: [Matrix4x4]
    
    /// Initializes a new skinned mesh component.
    /// - Parameters:
    ///   - mesh: The skinned mesh.
    ///   - color: Base color tint. Defaults to white.
    ///   - texture: Optional texture. Defaults to nil.
    ///   - skinIndex: Index of the skin. Defaults to 0.
    ///   - jointMatrices: Current frame joint matrices. Defaults to empty.
    public init(
        mesh: any Mesh,
        color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        texture: (any Texture)? = nil,
        skinIndex: Int = 0,
        jointMatrices: [Matrix4x4] = []
    ) {
        self.mesh = mesh
        self.color = color
        self.texture = texture
        self.skinIndex = skinIndex
        self.jointMatrices = jointMatrices
    }
}
