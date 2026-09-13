import Foundation

// MARK: - Dot Product

/// Computes the dot product of two 2D vectors.
@inlinable
public func dot(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
    (a * b).sum()
}

/// Computes the dot product of two 3D vectors.
@inlinable
public func dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    (a * b).sum()
}

/// Computes the dot product of two 4D vectors.
@inlinable
public func dot(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Float {
    (a * b).sum()
}

// MARK: - Cross Product

/// Computes the cross product of two 3D vectors.
@inlinable
public func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    )
}

// MARK: - Length & Distance

/// Computes the Euclidean length (magnitude) of a 2D vector.
@inlinable
public func length(_ v: SIMD2<Float>) -> Float {
    (v * v).sum().squareRoot()
}

/// Computes the Euclidean length (magnitude) of a 3D vector.
@inlinable
public func length(_ v: SIMD3<Float>) -> Float {
    (v * v).sum().squareRoot()
}

/// Computes the Euclidean length (magnitude) of a 4D vector.
@inlinable
public func length(_ v: SIMD4<Float>) -> Float {
    (v * v).sum().squareRoot()
}

/// Computes the squared Euclidean length of a 2D vector.
@inlinable
public func lengthSquared(_ v: SIMD2<Float>) -> Float {
    (v * v).sum()
}

/// Computes the squared Euclidean length of a 3D vector.
@inlinable
public func lengthSquared(_ v: SIMD3<Float>) -> Float {
    (v * v).sum()
}

/// Computes the squared Euclidean length of a 4D vector.
@inlinable
public func lengthSquared(_ v: SIMD4<Float>) -> Float {
    (v * v).sum()
}

/// Computes the distance between two 2D points.
@inlinable
public func distance(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
    length(a - b)
}

/// Computes the distance between two 3D points.
@inlinable
public func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    length(a - b)
}

/// Computes the distance between two 4D points.
@inlinable
public func distance(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Float {
    length(a - b)
}

// MARK: - Normalization

/// Returns a normalized vector with unit length. If the length is zero, returns zero.
@inlinable
public func normalize(_ v: SIMD2<Float>) -> SIMD2<Float> {
    let len = length(v)
    return len > 0 ? v / len : .zero
}

/// Returns a normalized vector with unit length. If the length is zero, returns zero.
@inlinable
public func normalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
    let len = length(v)
    return len > 0 ? v / len : .zero
}

/// Returns a normalized vector with unit length. If the length is zero, returns zero.
@inlinable
public func normalize(_ v: SIMD4<Float>) -> SIMD4<Float> {
    let len = length(v)
    return len > 0 ? v / len : .zero
}

// MARK: - Linear Interpolation (Mix / Lerp)

/// Linearly interpolates between two scalar values: `x + (y - x) * t`.
@inlinable
public func mix(_ x: Float, _ y: Float, t: Float) -> Float {
    x + (y - x) * t
}

/// Linearly interpolates component-wise between two 2D vectors by a scalar `t`.
@inlinable
public func mix(_ x: SIMD2<Float>, _ y: SIMD2<Float>, t: Float) -> SIMD2<Float> {
    x + (y - x) * SIMD2<Float>(repeating: t)
}

/// Linearly interpolates component-wise between two 2D vectors by a vector `t`.
@inlinable
public func mix(_ x: SIMD2<Float>, _ y: SIMD2<Float>, t: SIMD2<Float>) -> SIMD2<Float> {
    x + (y - x) * t
}

/// Linearly interpolates component-wise between two 3D vectors by a scalar `t`.
@inlinable
public func mix(_ x: SIMD3<Float>, _ y: SIMD3<Float>, t: Float) -> SIMD3<Float> {
    x + (y - x) * SIMD3<Float>(repeating: t)
}

/// Linearly interpolates component-wise between two 3D vectors by a vector `t`.
@inlinable
public func mix(_ x: SIMD3<Float>, _ y: SIMD3<Float>, t: SIMD3<Float>) -> SIMD3<Float> {
    x + (y - x) * t
}

/// Linearly interpolates component-wise between two 4D vectors by a scalar `t`.
@inlinable
public func mix(_ x: SIMD4<Float>, _ y: SIMD4<Float>, t: Float) -> SIMD4<Float> {
    x + (y - x) * SIMD4<Float>(repeating: t)
}

/// Linearly interpolates component-wise between two 4D vectors by a vector `t`.
@inlinable
public func mix(_ x: SIMD4<Float>, _ y: SIMD4<Float>, t: SIMD4<Float>) -> SIMD4<Float> {
    x + (y - x) * t
}

// MARK: - Quaternion Interpolation & Conversion

/// Computes the spherical linear interpolation between two quaternions (x, y, z, w).
/// - Parameters:
///   - q1: The starting quaternion.
///   - q2: The destination quaternion.
///   - t: The interpolation parameter in `[0, 1]`.
/// - Returns: The spherically interpolated and normalized quaternion.
@inlinable
public func slerp(_ q1: SIMD4<Float>, _ q2: SIMD4<Float>, t: Float) -> SIMD4<Float> {
    var cosHalfTheta = dot(q1, q2)
    var target = q2
    if cosHalfTheta < 0 {
        target = -q2
        cosHalfTheta = -cosHalfTheta
    }
    
    if cosHalfTheta > 0.9995 {
        return normalize(mix(q1, target, t: t))
    }
    
    let halfTheta = acos(clamp(cosHalfTheta, min: -1.0, max: 1.0))
    let sinHalfTheta = sqrt(max(0.0, 1.0 - cosHalfTheta * cosHalfTheta))
    if sinHalfTheta < 0.0001 {
        return normalize(mix(q1, target, t: t))
    }
    let ratioA = sin((1.0 - t) * halfTheta) / sinHalfTheta
    let ratioB = sin(t * halfTheta) / sinHalfTheta
    return normalize(q1 * ratioA + target * ratioB)
}

/// Converts a unit quaternion (x, y, z, w) to XYZ Euler angles (pitch, yaw, roll).
/// - Parameter q: The quaternion.
/// - Returns: The 3D Euler angles in radians.
@inlinable
public func quaternionToEuler(_ q: SIMD4<Float>) -> SIMD3<Float> {
    let pitch = atan2(2 * (q.w * q.x + q.y * q.z), 1 - 2 * (q.x * q.x + q.y * q.y))
    let yaw = asin(clamp(2 * (q.w * q.y - q.z * q.x), min: -1.0, max: 1.0))
    let roll = atan2(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z))
    return SIMD3<Float>(pitch, yaw, roll)
}

// MARK: - Clamp

/// Clamps a scalar value to the range `[minValue, maxValue]`.
@inlinable
public func clamp<T: Comparable>(_ value: T, min minValue: T, max maxValue: T) -> T {
    min(max(value, minValue), maxValue)
}

/// Clamps each component of a 2D vector to the range `[minValue, maxValue]`.
@inlinable
public func clamp(_ v: SIMD2<Float>, min minValue: SIMD2<Float>, max maxValue: SIMD2<Float>) -> SIMD2<Float> {
    SIMD2<Float>(
        clamp(v.x, min: minValue.x, max: maxValue.x),
        clamp(v.y, min: minValue.y, max: maxValue.y)
    )
}

/// Clamps each component of a 3D vector to the range `[minValue, maxValue]`.
@inlinable
public func clamp(_ v: SIMD3<Float>, min minValue: SIMD3<Float>, max maxValue: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(
        clamp(v.x, min: minValue.x, max: maxValue.x),
        clamp(v.y, min: minValue.y, max: maxValue.y),
        clamp(v.z, min: minValue.z, max: maxValue.z)
    )
}

/// Clamps each component of a 4D vector to the range `[minValue, maxValue]`.
@inlinable
public func clamp(_ v: SIMD4<Float>, min minValue: SIMD4<Float>, max maxValue: SIMD4<Float>) -> SIMD4<Float> {
    SIMD4<Float>(
        clamp(v.x, min: minValue.x, max: maxValue.x),
        clamp(v.y, min: minValue.y, max: maxValue.y),
        clamp(v.z, min: minValue.z, max: maxValue.z),
        clamp(v.w, min: minValue.w, max: maxValue.w)
    )
}

// MARK: - SIMD Vector Extensions

extension SIMD2 where Scalar == Float {
    /// The Euclidean length of this vector.
    @inlinable
    public var length: Float {
        AcornMath.length(self)
    }

    /// The squared Euclidean length of this vector.
    @inlinable
    public var lengthSquared: Float {
        AcornMath.lengthSquared(self)
    }

    /// Returns a normalized copy of this vector with unit length.
    @inlinable
    public func normalized() -> SIMD2<Float> {
        AcornMath.normalize(self)
    }

    /// Computes the dot product of this vector with another.
    @inlinable
    public func dot(_ other: SIMD2<Float>) -> Float {
        AcornMath.dot(self, other)
    }
}

extension SIMD3 where Scalar == Float {
    /// The Euclidean length of this vector.
    @inlinable
    public var length: Float {
        AcornMath.length(self)
    }

    /// The squared Euclidean length of this vector.
    @inlinable
    public var lengthSquared: Float {
        AcornMath.lengthSquared(self)
    }

    /// Returns a normalized copy of this vector with unit length.
    @inlinable
    public func normalized() -> SIMD3<Float> {
        AcornMath.normalize(self)
    }

    /// Computes the dot product of this vector with another.
    @inlinable
    public func dot(_ other: SIMD3<Float>) -> Float {
        AcornMath.dot(self, other)
    }

    /// Computes the cross product of this vector with another.
    @inlinable
    public func cross(_ other: SIMD3<Float>) -> SIMD3<Float> {
        AcornMath.cross(self, other)
    }
}

extension SIMD4 where Scalar == Float {
    /// The Euclidean length of this vector.
    @inlinable
    public var length: Float {
        AcornMath.length(self)
    }

    /// The squared Euclidean length of this vector.
    @inlinable
    public var lengthSquared: Float {
        AcornMath.lengthSquared(self)
    }

    /// Returns a normalized copy of this vector with unit length.
    @inlinable
    public func normalized() -> SIMD4<Float> {
        AcornMath.normalize(self)
    }

    /// Computes the dot product of this vector with another.
    @inlinable
    public func dot(_ other: SIMD4<Float>) -> Float {
        AcornMath.dot(self, other)
    }
}
