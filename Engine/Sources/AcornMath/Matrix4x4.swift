import Foundation

/// A 4x4 column-major floating-point matrix representing 3D affine transformations and projections.
///
/// `Matrix4x4` is a pure-Swift value type designed for cross-platform graphics and physics engines.
/// It has a 64-byte memory layout and 16-byte alignment identical to Metal, Vulkan, and Darwin's `simd_float4x4`.
public struct Matrix4x4: Sendable, Equatable, Hashable {
    /// The four column vectors of the matrix.
    public var columns: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)

    // MARK: - Initializers

    /// Creates a matrix with all elements set to zero.
    public init() {
        self.columns = (
            SIMD4<Float>(0, 0, 0, 0),
            SIMD4<Float>(0, 0, 0, 0),
            SIMD4<Float>(0, 0, 0, 0),
            SIMD4<Float>(0, 0, 0, 0)
        )
    }

    /// Creates a matrix with the given column tuple.
    /// - Parameter columns: The four column vectors.
    public init(columns: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)) {
        self.columns = columns
    }

    /// Creates a matrix from four individual column vectors.
    /// - Parameters:
    ///   - col0: The first column vector.
    ///   - col1: The second column vector.
    ///   - col2: The third column vector.
    ///   - col3: The fourth column vector.
    public init(_ col0: SIMD4<Float>, _ col1: SIMD4<Float>, _ col2: SIMD4<Float>, _ col3: SIMD4<Float>) {
        self.columns = (col0, col1, col2, col3)
    }

    /// Creates a diagonal matrix with the specified vector on the diagonal.
    /// - Parameter diagonal: The diagonal elements.
    public init(diagonal: SIMD4<Float>) {
        self.columns = (
            SIMD4<Float>(diagonal.x, 0, 0, 0),
            SIMD4<Float>(0, diagonal.y, 0, 0),
            SIMD4<Float>(0, 0, diagonal.z, 0),
            SIMD4<Float>(0, 0, 0, diagonal.w)
        )
    }

    /// Creates a diagonal matrix with a scalar value along the diagonal.
    /// - Parameter scalar: The scalar value for each diagonal element.
    public init(scalar: Float) {
        self.init(diagonal: SIMD4<Float>(repeating: scalar))
    }

    // MARK: - Static Constants

    /// The zero matrix.
    public static let zero = Matrix4x4()

    /// The 4x4 identity matrix.
    public static let identity = Matrix4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))

    // MARK: - Subscripts

    /// Accesses the column vector at the given index.
    /// - Parameter index: Column index (0 to 3).
    public subscript(column: Int) -> SIMD4<Float> {
        get {
            switch column {
            case 0: return columns.0
            case 1: return columns.1
            case 2: return columns.2
            case 3: return columns.3
            default: fatalError("Matrix4x4 column index out of range: \(column)")
            }
        }
        set {
            switch column {
            case 0: columns.0 = newValue
            case 1: columns.1 = newValue
            case 2: columns.2 = newValue
            case 3: columns.3 = newValue
            default: fatalError("Matrix4x4 column index out of range: \(column)")
            }
        }
    }

    /// Accesses the element at the given row and column index.
    /// - Parameters:
    ///   - row: Row index (0 to 3).
    ///   - column: Column index (0 to 3).
    public subscript(row: Int, column: Int) -> Float {
        get {
            self[column][row]
        }
        set {
            self[column][row] = newValue
        }
    }

    // MARK: - Geometric Transform Initializers

    /// Creates a 4x4 translation matrix.
    /// - Parameter translation: The translation vector.
    public init(translation: SIMD3<Float>) {
        self = .identity
        self.columns.3 = SIMD4<Float>(translation.x, translation.y, translation.z, 1.0)
    }

    /// Creates a 4x4 scaling matrix from a 3D scale vector.
    /// - Parameter scale: The scaling vector.
    public init(scale: SIMD3<Float>) {
        self = .identity
        self.columns.0.x = scale.x
        self.columns.1.y = scale.y
        self.columns.2.z = scale.z
    }

    /// Creates a 4x4 uniform scaling matrix.
    /// - Parameter scale: The uniform scale factor.
    public init(scale: Float) {
        self.init(scale: SIMD3<Float>(repeating: scale))
    }

    /// Creates a 4x4 rotation matrix around the X axis.
    /// - Parameter angle: The rotation angle in radians.
    public init(rotationX angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self = .identity
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
        self = .identity
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
        self = .identity
        self.columns.0.x = c
        self.columns.0.y = s
        self.columns.1.x = -s
        self.columns.1.y = c
    }

    /// Creates a 4x4 rotation matrix from Euler angles (XYZ order: pitch, yaw, roll).
    /// - Parameter eulerAngles: The rotation angles in radians around X, Y, and Z.
    public init(rotation eulerAngles: SIMD3<Float>) {
        let rotX = Matrix4x4(rotationX: eulerAngles.x)
        let rotY = Matrix4x4(rotationY: eulerAngles.y)
        let rotZ = Matrix4x4(rotationZ: eulerAngles.z)
        self = rotZ * rotY * rotX
    }

    /// Creates a 4x4 model matrix from translation, rotation, and scale components.
    /// - Parameters:
    ///   - position: The translation vector.
    ///   - rotation: The rotation Euler angles in radians (XYZ order).
    ///   - scale: The scaling vector.
    public init(position: SIMD3<Float>, rotation: SIMD3<Float>, scale: SIMD3<Float>) {
        let translationMatrix = Matrix4x4(translation: position)
        let rotationMatrix = Matrix4x4(rotation: rotation)
        let scaleMatrix = Matrix4x4(scale: scale)
        self = translationMatrix * rotationMatrix * scaleMatrix
    }

    // MARK: - Projection Initializers

    /// Creates an orthographic projection matrix tailored for graphics APIs with NDC Z in `[0, 1]` (Metal / Vulkan).
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
        let zRange = farZ - nearZ

        self.init(
            SIMD4<Float>(2.0 / rsl, 0.0, 0.0, 0.0),
            SIMD4<Float>(0.0, 2.0 / tsb, 0.0, 0.0),
            SIMD4<Float>(0.0, 0.0, 1.0 / zRange, 0.0),
            SIMD4<Float>(-ral / rsl, -tab / tsb, -nearZ / zRange, 1.0)
        )
    }

    /// Creates a perspective projection matrix tailored for graphics APIs with NDC Z in `[0, 1]` (Metal / Vulkan).
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

    // MARK: - Properties and Operations

    /// The transpose of this matrix.
    public var transposed: Matrix4x4 {
        Matrix4x4(
            SIMD4<Float>(columns.0.x, columns.1.x, columns.2.x, columns.3.x),
            SIMD4<Float>(columns.0.y, columns.1.y, columns.2.y, columns.3.y),
            SIMD4<Float>(columns.0.z, columns.1.z, columns.2.z, columns.3.z),
            SIMD4<Float>(columns.0.w, columns.1.w, columns.2.w, columns.3.w)
        )
    }

    /// The transpose of this matrix (alias for `transposed` matching Darwin `simd_float4x4.transpose`).
    @inlinable public var transpose: Matrix4x4 { transposed }

    /// The determinant of this 4x4 matrix.
    public var determinant: Float {
        let m00 = columns.0.x, m10 = columns.0.y, m20 = columns.0.z, m30 = columns.0.w
        let m01 = columns.1.x, m11 = columns.1.y, m21 = columns.1.z, m31 = columns.1.w
        let m02 = columns.2.x, m12 = columns.2.y, m22 = columns.2.z, m32 = columns.2.w
        let m03 = columns.3.x, m13 = columns.3.y, m23 = columns.3.z, m33 = columns.3.w

        let s0 = m00 * m11 - m10 * m01
        let s1 = m00 * m12 - m10 * m02
        let s2 = m00 * m13 - m10 * m03
        let s3 = m01 * m12 - m11 * m02
        let s4 = m01 * m13 - m11 * m03
        let s5 = m02 * m13 - m12 * m03

        let c5 = m22 * m33 - m32 * m23
        let c4 = m21 * m33 - m31 * m23
        let c3 = m21 * m32 - m31 * m22
        let c2 = m20 * m33 - m30 * m23
        let c1 = m20 * m32 - m30 * m22
        let c0 = m20 * m31 - m30 * m21

        return s0 * c5 - s1 * c4 + s2 * c3 + s3 * c2 - s4 * c1 + s5 * c0
    }

    /// Computes the inverse of the matrix, returning `nil` if the matrix is singular.
    public func inverted() -> Matrix4x4? {
        let m00 = columns.0.x, m10 = columns.0.y, m20 = columns.0.z, m30 = columns.0.w
        let m01 = columns.1.x, m11 = columns.1.y, m21 = columns.1.z, m31 = columns.1.w
        let m02 = columns.2.x, m12 = columns.2.y, m22 = columns.2.z, m32 = columns.2.w
        let m03 = columns.3.x, m13 = columns.3.y, m23 = columns.3.z, m33 = columns.3.w

        let s0 = m00 * m11 - m10 * m01
        let s1 = m00 * m12 - m10 * m02
        let s2 = m00 * m13 - m10 * m03
        let s3 = m01 * m12 - m11 * m02
        let s4 = m01 * m13 - m11 * m03
        let s5 = m02 * m13 - m12 * m03

        let c5 = m22 * m33 - m32 * m23
        let c4 = m21 * m33 - m31 * m23
        let c3 = m21 * m32 - m31 * m22
        let c2 = m20 * m33 - m30 * m23
        let c1 = m20 * m32 - m30 * m22
        let c0 = m20 * m31 - m30 * m21

        let det = s0 * c5 - s1 * c4 + s2 * c3 + s3 * c2 - s4 * c1 + s5 * c0
        guard abs(det) > 1e-12 else {
            return nil
        }

        let invDet = 1.0 / det

        let col0 = SIMD4<Float>(
            (m11 * c5 - m12 * c4 + m13 * c3) * invDet,
            (-m10 * c5 + m12 * c2 - m13 * c1) * invDet,
            (m10 * c4 - m11 * c2 + m13 * c0) * invDet,
            (-m10 * c3 + m11 * c1 - m12 * c0) * invDet
        )

        let col1 = SIMD4<Float>(
            (-m01 * c5 + m02 * c4 - m03 * c3) * invDet,
            (m00 * c5 - m02 * c2 + m03 * c1) * invDet,
            (-m00 * c4 + m01 * c2 - m03 * c0) * invDet,
            (m00 * c3 - m01 * c1 + m02 * c0) * invDet
        )

        let col2 = SIMD4<Float>(
            (m31 * s5 - m32 * s4 + m33 * s3) * invDet,
            (-m30 * s5 + m32 * s2 - m33 * s1) * invDet,
            (m30 * s4 - m31 * s2 + m33 * s0) * invDet,
            (-m30 * s3 + m31 * s1 - m32 * s0) * invDet
        )

        let col3 = SIMD4<Float>(
            (-m21 * s5 + m22 * s4 - m23 * s3) * invDet,
            (m20 * s5 - m22 * s2 + m23 * s1) * invDet,
            (-m20 * s4 + m21 * s2 - m23 * s0) * invDet,
            (m20 * s3 - m21 * s1 + m22 * s0) * invDet
        )

        return Matrix4x4(col0, col1, col2, col3)
    }

    /// The inverse of this matrix. If singular, returns a zero matrix.
    public var inverse: Matrix4x4 {
        inverted() ?? .zero
    }

    // MARK: - Operators

    /// Multiplies two 4x4 matrices in column-major order.
    public static func * (lhs: Matrix4x4, rhs: Matrix4x4) -> Matrix4x4 {
        let col0 = lhs.columns.0 * rhs.columns.0.x +
                   lhs.columns.1 * rhs.columns.0.y +
                   lhs.columns.2 * rhs.columns.0.z +
                   lhs.columns.3 * rhs.columns.0.w

        let col1 = lhs.columns.0 * rhs.columns.1.x +
                   lhs.columns.1 * rhs.columns.1.y +
                   lhs.columns.2 * rhs.columns.1.z +
                   lhs.columns.3 * rhs.columns.1.w

        let col2 = lhs.columns.0 * rhs.columns.2.x +
                   lhs.columns.1 * rhs.columns.2.y +
                   lhs.columns.2 * rhs.columns.2.z +
                   lhs.columns.3 * rhs.columns.2.w

        let col3 = lhs.columns.0 * rhs.columns.3.x +
                   lhs.columns.1 * rhs.columns.3.y +
                   lhs.columns.2 * rhs.columns.3.z +
                   lhs.columns.3 * rhs.columns.3.w

        return Matrix4x4(col0, col1, col2, col3)
    }

    /// Multiplies a 4x4 matrix with a 4-component vector.
    public static func * (lhs: Matrix4x4, rhs: SIMD4<Float>) -> SIMD4<Float> {
        lhs.columns.0 * rhs.x +
        lhs.columns.1 * rhs.y +
        lhs.columns.2 * rhs.z +
        lhs.columns.3 * rhs.w
    }

    /// Multiplies the matrix in place.
    public static func *= (lhs: inout Matrix4x4, rhs: Matrix4x4) {
        lhs = lhs * rhs
    }

    /// Adds two 4x4 matrices component-wise.
    public static func + (lhs: Matrix4x4, rhs: Matrix4x4) -> Matrix4x4 {
        Matrix4x4(
            lhs.columns.0 + rhs.columns.0,
            lhs.columns.1 + rhs.columns.1,
            lhs.columns.2 + rhs.columns.2,
            lhs.columns.3 + rhs.columns.3
        )
    }

    /// Subtracts two 4x4 matrices component-wise.
    public static func - (lhs: Matrix4x4, rhs: Matrix4x4) -> Matrix4x4 {
        Matrix4x4(
            lhs.columns.0 - rhs.columns.0,
            lhs.columns.1 - rhs.columns.1,
            lhs.columns.2 - rhs.columns.2,
            lhs.columns.3 - rhs.columns.3
        )
    }

    // MARK: - Equatable & Hashable

    public static func == (lhs: Matrix4x4, rhs: Matrix4x4) -> Bool {
        lhs.columns.0 == rhs.columns.0 &&
        lhs.columns.1 == rhs.columns.1 &&
        lhs.columns.2 == rhs.columns.2 &&
        lhs.columns.3 == rhs.columns.3
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(columns.0)
        hasher.combine(columns.1)
        hasher.combine(columns.2)
        hasher.combine(columns.3)
    }
}

// MARK: - Codable Conformance

extension Matrix4x4: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let c0 = try container.decode(SIMD4<Float>.self)
        let c1 = try container.decode(SIMD4<Float>.self)
        let c2 = try container.decode(SIMD4<Float>.self)
        let c3 = try container.decode(SIMD4<Float>.self)
        self.init(c0, c1, c2, c3)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(columns.0)
        try container.encode(columns.1)
        try container.encode(columns.2)
        try container.encode(columns.3)
    }
}
