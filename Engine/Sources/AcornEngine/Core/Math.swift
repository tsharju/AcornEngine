import Foundation
@_exported import AcornMath

#if canImport(simd)
import simd

extension simd_float4x4 {
    /// Creates an identity matrix.
    public static var identity: simd_float4x4 {
        matrix_identity_float4x4
    }

    /// Creates a 4x4 translation matrix.
    /// - Parameter translation: The translation vector.
    public init(translation: SIMD3<Float>) {
        self = Matrix4x4(translation: translation).asSIMD
    }

    /// Creates a 4x4 scaling matrix.
    /// - Parameter scale: The scaling vector.
    public init(scale: SIMD3<Float>) {
        self = Matrix4x4(scale: scale).asSIMD
    }

    /// Creates a 4x4 rotation matrix around the X axis.
    /// - Parameter angle: The rotation angle in radians.
    public init(rotationX angle: Float) {
        self = Matrix4x4(rotationX: angle).asSIMD
    }

    /// Creates a 4x4 rotation matrix around the Y axis.
    /// - Parameter angle: The rotation angle in radians.
    public init(rotationY angle: Float) {
        self = Matrix4x4(rotationY: angle).asSIMD
    }

    /// Creates a 4x4 rotation matrix around the Z axis.
    /// - Parameter angle: The rotation angle in radians.
    public init(rotationZ angle: Float) {
        self = Matrix4x4(rotationZ: angle).asSIMD
    }

    /// Creates a 4x4 rotation matrix from Euler angles (XYZ order).
    /// - Parameter eulerAngles: The rotation angles in radians (pitch, yaw, roll).
    public init(rotation eulerAngles: SIMD3<Float>) {
        self = Matrix4x4(rotation: eulerAngles).asSIMD
    }

    /// Creates a 4x4 model matrix from translation, rotation, and scale.
    /// - Parameters:
    ///   - position: The translation vector.
    ///   - rotation: The rotation Euler angles in radians.
    ///   - scale: The scaling vector.
    public init(position: SIMD3<Float>, rotation: SIMD3<Float>, scale: SIMD3<Float>) {
        self = Matrix4x4(position: position, rotation: rotation, scale: scale).asSIMD
    }

    /// Creates an orthographic projection matrix.
    /// - Parameters:
    ///   - left: The left coordinate of the viewing volume.
    ///   - right: The right coordinate of the viewing volume.
    ///   - bottom: The bottom coordinate of the viewing volume.
    ///   - top: The top coordinate of the viewing volume.
    ///   - nearZ: The near clipping plane.
    ///   - farZ: The far clipping plane.
    public init(orthographic left: Float, right: Float, bottom: Float, top: Float, nearZ: Float, farZ: Float) {
        self = Matrix4x4(orthographic: left, right: right, bottom: bottom, top: top, nearZ: nearZ, farZ: farZ).asSIMD
    }

    /// Creates a perspective projection matrix.
    /// - Parameters:
    ///   - fovY: The vertical field of view in radians.
    ///   - aspect: The aspect ratio (width / height).
    ///   - nearZ: The near clipping plane.
    ///   - farZ: The far clipping plane.
    public init(perspectiveFovY fovY: Float, aspect: Float, nearZ: Float, farZ: Float) {
        self = Matrix4x4(perspectiveFovY: fovY, aspect: aspect, nearZ: nearZ, farZ: farZ).asSIMD
    }
}
#endif
