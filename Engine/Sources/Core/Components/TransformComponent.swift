import Foundation
import simd

/// A component that represents an entity's position, rotation, and scale in 3D space.
public struct TransformComponent: Component {
    /// The position of the entity.
    public var position: SIMD3<Float>
    
    /// The rotation of the entity (Euler angles).
    public var rotation: SIMD3<Float>
    
    /// The scale of the entity.
    public var scale: SIMD3<Float>
    
    /// Initializes a new transform component.
    /// - Parameters:
    ///   - position: The initial position. Defaults to `.zero`.
    ///   - rotation: The initial rotation. Defaults to `.zero`.
    ///   - scale: The initial scale. Defaults to `(1, 1, 1)`.
    public init(position: SIMD3<Float> = .zero, rotation: SIMD3<Float> = .zero, scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1)) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }
    
    /// The 4x4 transformation matrix derived from position, rotation, and scale.
    public var matrix: simd_float4x4 {
        simd_float4x4(position: position, rotation: rotation, scale: scale)
    }
}
