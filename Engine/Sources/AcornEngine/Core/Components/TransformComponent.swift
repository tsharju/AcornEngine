import Foundation
import AcornMath

/// A component that represents an entity's position, rotation, and scale in 3D space.
public struct TransformComponent: Component {
    /// The position of the entity.
    public var position: SIMD3<Float>
    
    /// The rotation of the entity (Euler angles).
    public var rotation: SIMD3<Float>
    
    /// The scale of the entity.
    public var scale: SIMD3<Float>
    
    /// The orientation of the entity as a unit quaternion (x, y, z, w), if set.
    /// When specified, `matrix` computes rotation directly from this quaternion avoiding gimbal lock.
    public var orientation: SIMD4<Float>?
    
    /// Initializes a new transform component.
    /// - Parameters:
    ///   - position: The initial position. Defaults to `.zero`.
    ///   - rotation: The initial rotation. Defaults to `.zero`.
    ///   - scale: The initial scale. Defaults to `(1, 1, 1)`.
    ///   - orientation: The optional orientation quaternion. Defaults to `nil`.
    public init(
        position: SIMD3<Float> = .zero,
        rotation: SIMD3<Float> = .zero,
        scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
        orientation: SIMD4<Float>? = nil
    ) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.orientation = orientation
    }
    
    /// The 4x4 transformation matrix derived from position, rotation (or orientation quaternion), and scale.
    public var matrix: Matrix4x4 {
        if let q = orientation {
            let translationMatrix = Matrix4x4(translation: position)
            let rotationMatrix = Matrix4x4(quaternion: q)
            let scaleMatrix = Matrix4x4(scale: scale)
            return translationMatrix * rotationMatrix * scaleMatrix
        } else {
            return Matrix4x4(position: position, rotation: rotation, scale: scale)
        }
    }
}
