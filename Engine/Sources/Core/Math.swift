import Foundation
import simd

extension simd_float4x4 {
    /// Creates an identity matrix.
    public static var identity: simd_float4x4 {
        matrix_identity_float4x4
    }

    /// Creates a 4x4 translation matrix.
    /// - Parameter translation: The translation vector.
    public init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        self.columns.3 = SIMD4<Float>(translation.x, translation.y, translation.z, 1.0)
    }

    /// Creates a 4x4 scaling matrix.
    /// - Parameter scale: The scaling vector.
    public init(scale: SIMD3<Float>) {
        self = matrix_identity_float4x4
        self.columns.0.x = scale.x
        self.columns.1.y = scale.y
        self.columns.2.z = scale.z
    }

    /// Creates a 4x4 rotation matrix around the X axis.
    /// - Parameter angle: The rotation angle in radians.
    public init(rotationX angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self = matrix_identity_float4x4
        self.columns.1.y = c
        self.columns.1.z = s
        self.columns.2.y = -s
        self.columns.2.z = c
    }

    /// Creates a 4x4 rotation matrix around the Y axis.
    /// - Parameter angle: The rotation angle in radians.
    public init(rotationY angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self = matrix_identity_float4x4
        self.columns.0.x = c
        self.columns.0.z = -s
        self.columns.2.x = s
        self.columns.2.z = c
    }

    /// Creates a 4x4 rotation matrix around the Z axis.
    /// - Parameter angle: The rotation angle in radians.
    public init(rotationZ angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self = matrix_identity_float4x4
        self.columns.0.x = c
        self.columns.0.y = s
        self.columns.1.x = -s
        self.columns.1.y = c
    }

    /// Creates a 4x4 rotation matrix from Euler angles (XYZ order).
    /// - Parameter eulerAngles: The rotation angles in radians (pitch, yaw, roll).
    public init(rotation eulerAngles: SIMD3<Float>) {
        let rotX = simd_float4x4(rotationX: eulerAngles.x)
        let rotY = simd_float4x4(rotationY: eulerAngles.y)
        let rotZ = simd_float4x4(rotationZ: eulerAngles.z)
        self = matrix_multiply(matrix_multiply(rotZ, rotY), rotX)
    }

    /// Creates a 4x4 model matrix from translation, rotation, and scale.
    /// - Parameters:
    ///   - position: The translation vector.
    ///   - rotation: The rotation Euler angles in radians.
    ///   - scale: The scaling vector.
    public init(position: SIMD3<Float>, rotation: SIMD3<Float>, scale: SIMD3<Float>) {
        let translationMatrix = simd_float4x4(translation: position)
        let rotationMatrix = simd_float4x4(rotation: rotation)
        let scaleMatrix = simd_float4x4(scale: scale)
        self = matrix_multiply(matrix_multiply(translationMatrix, rotationMatrix), scaleMatrix)
    }

    /// Creates an orthographic projection matrix.
    /// Metal's NDC z-range is [0, 1].
    /// - Parameters:
    ///   - left: The left coordinate of the viewing volume.
    ///   - right: The right coordinate of the viewing volume.
    ///   - bottom: The bottom coordinate of the viewing volume.
    ///   - top: The top coordinate of the viewing volume.
    ///   - nearZ: The near clipping plane.
    ///   - farZ: The far clipping plane.
    public init(orthographic left: Float, right: Float, bottom: Float, top: Float, nearZ: Float, farZ: Float) {
        let ral = right + left
        let rsl = right - left
        let tab = top + bottom
        let tsb = top - bottom
        
        self.init(
            SIMD4<Float>(2.0 / rsl, 0.0, 0.0, 0.0),
            SIMD4<Float>(0.0, 2.0 / tsb, 0.0, 0.0),
            SIMD4<Float>(0.0, 0.0, 1.0 / (farZ - nearZ), 0.0), // Metal uses 0..1 for Z
            SIMD4<Float>(-ral / rsl, -tab / tsb, -nearZ / (farZ - nearZ), 1.0)
        )
     }
     
     /// Creates a perspective projection matrix.
     /// Metal's NDC z-range is [0, 1].
     /// - Parameters:
     ///   - fovY: The vertical field of view in radians.
     ///   - aspect: The aspect ratio (width / height).
     ///   - nearZ: The near clipping plane.
     ///   - farZ: The far clipping plane.
     public init(perspectiveFovY fovY: Float, aspect: Float, nearZ: Float, farZ: Float) {
         let ys = 1.0 / tan(fovY * 0.5)
         let xs = ys / aspect
         let zs = farZ / (farZ - nearZ)
         
         self.init(
             SIMD4<Float>(xs, 0.0, 0.0, 0.0),
             SIMD4<Float>(0.0, ys, 0.0, 0.0),
             SIMD4<Float>(0.0, 0.0, zs, 1.0),
             SIMD4<Float>(0.0, 0.0, -nearZ * zs, 0.0)
         )
     }
}
