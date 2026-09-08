import Foundation

// MARK: - Apple Darwin SIMD Interoperability

#if canImport(simd)
import simd

extension Matrix4x4 {
    /// Initializes a `Matrix4x4` from an Apple `simd_float4x4`.
    @inlinable
    public init(_ m: simd_float4x4) {
        self.columns = (m.columns.0, m.columns.1, m.columns.2, m.columns.3)
    }

    /// Converts this `Matrix4x4` to an Apple `simd_float4x4`.
    @inlinable
    public var asSIMD: simd_float4x4 {
        simd_float4x4(columns: (columns.0, columns.1, columns.2, columns.3))
    }
}

extension simd_float4x4 {
    /// Initializes an Apple `simd_float4x4` from an `AcornMath.Matrix4x4`.
    @inlinable
    public init(_ m: Matrix4x4) {
        self.init(columns: (m.columns.0, m.columns.1, m.columns.2, m.columns.3))
    }

    /// Converts this Apple `simd_float4x4` to an `AcornMath.Matrix4x4`.
    @inlinable
    public var asMatrix4x4: Matrix4x4 {
        Matrix4x4(self)
    }
}

#else

// MARK: - Non-Darwin (Linux / Android) SIMD Compatibility Shims

public typealias simd_float4x4 = Matrix4x4
public typealias simd_float2 = SIMD2<Float>
public typealias simd_float3 = SIMD3<Float>
public typealias simd_float4 = SIMD4<Float>
public typealias simd_double2 = SIMD2<Double>
public typealias simd_double3 = SIMD3<Double>
public typealias simd_double4 = SIMD4<Double>
public typealias simd_int2 = SIMD2<Int32>
public typealias simd_int3 = SIMD3<Int32>
public typealias simd_int4 = SIMD4<Int32>
public typealias simd_uint2 = SIMD2<UInt32>
public typealias simd_uint3 = SIMD3<UInt32>
public typealias simd_uint4 = SIMD4<UInt32>

@inlinable public var matrix_identity_float4x4: Matrix4x4 { Matrix4x4.identity }
@inlinable public func matrix_multiply(_ a: Matrix4x4, _ b: Matrix4x4) -> Matrix4x4 { a * b }
@inlinable public func simd_mul(_ a: Matrix4x4, _ b: Matrix4x4) -> Matrix4x4 { a * b }
@inlinable public func simd_mul(_ a: Matrix4x4, _ v: SIMD4<Float>) -> SIMD4<Float> { a * v }
@inlinable public func simd_inverse(_ m: Matrix4x4) -> Matrix4x4 { m.inverse }
@inlinable public func simd_transpose(_ m: Matrix4x4) -> Matrix4x4 { m.transposed }

@inlinable public func simd_make_float2(_ x: Float, _ y: Float) -> SIMD2<Float> { SIMD2<Float>(x, y) }
@inlinable public func simd_make_float3(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { SIMD3<Float>(x, y, z) }
@inlinable public func simd_make_float4(_ x: Float, _ y: Float, _ z: Float, _ w: Float) -> SIMD4<Float> { SIMD4<Float>(x, y, z, w) }

@inlinable public func simd_dot(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { dot(a, b) }
@inlinable public func simd_dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { dot(a, b) }
@inlinable public func simd_dot(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Float { dot(a, b) }

@inlinable public func simd_cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> { cross(a, b) }

@inlinable public func simd_length(_ v: SIMD2<Float>) -> Float { length(v) }
@inlinable public func simd_length(_ v: SIMD3<Float>) -> Float { length(v) }
@inlinable public func simd_length(_ v: SIMD4<Float>) -> Float { length(v) }

@inlinable public func simd_length_squared(_ v: SIMD2<Float>) -> Float { lengthSquared(v) }
@inlinable public func simd_length_squared(_ v: SIMD3<Float>) -> Float { lengthSquared(v) }
@inlinable public func simd_length_squared(_ v: SIMD4<Float>) -> Float { lengthSquared(v) }

@inlinable public func simd_normalize(_ v: SIMD2<Float>) -> SIMD2<Float> { normalize(v) }
@inlinable public func simd_normalize(_ v: SIMD3<Float>) -> SIMD3<Float> { normalize(v) }
@inlinable public func simd_normalize(_ v: SIMD4<Float>) -> SIMD4<Float> { normalize(v) }

@inlinable public func simd_distance(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { distance(a, b) }
@inlinable public func simd_distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { distance(a, b) }
@inlinable public func simd_distance(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Float { distance(a, b) }

@inlinable public func simd_mix(_ x: Float, _ y: Float, _ t: Float) -> Float { mix(x, y, t: t) }
@inlinable public func simd_mix(_ x: SIMD2<Float>, _ y: SIMD2<Float>, _ t: SIMD2<Float>) -> SIMD2<Float> { mix(x, y, t: t) }
@inlinable public func simd_mix(_ x: SIMD3<Float>, _ y: SIMD3<Float>, _ t: SIMD3<Float>) -> SIMD3<Float> { mix(x, y, t: t) }
@inlinable public func simd_mix(_ x: SIMD4<Float>, _ y: SIMD4<Float>, _ t: SIMD4<Float>) -> SIMD4<Float> { mix(x, y, t: t) }

@inlinable public func simd_min(_ x: SIMD2<Float>, _ y: SIMD2<Float>) -> SIMD2<Float> { x.pointwiseMin(y) }
@inlinable public func simd_min(_ x: SIMD3<Float>, _ y: SIMD3<Float>) -> SIMD3<Float> { x.pointwiseMin(y) }
@inlinable public func simd_min(_ x: SIMD4<Float>, _ y: SIMD4<Float>) -> SIMD4<Float> { x.pointwiseMin(y) }

@inlinable public func simd_max(_ x: SIMD2<Float>, _ y: SIMD2<Float>) -> SIMD2<Float> { x.pointwiseMax(y) }
@inlinable public func simd_max(_ x: SIMD3<Float>, _ y: SIMD3<Float>) -> SIMD3<Float> { x.pointwiseMax(y) }
@inlinable public func simd_max(_ x: SIMD4<Float>, _ y: SIMD4<Float>) -> SIMD4<Float> { x.pointwiseMax(y) }

@inlinable public func simd_clamp(_ x: Float, _ minValue: Float, _ maxValue: Float) -> Float { clamp(x, min: minValue, max: maxValue) }
@inlinable public func simd_clamp(_ x: SIMD2<Float>, _ minValue: SIMD2<Float>, _ maxValue: SIMD2<Float>) -> SIMD2<Float> { clamp(x, min: minValue, max: maxValue) }
@inlinable public func simd_clamp(_ x: SIMD3<Float>, _ minValue: SIMD3<Float>, _ maxValue: SIMD3<Float>) -> SIMD3<Float> { clamp(x, min: minValue, max: maxValue) }
@inlinable public func simd_clamp(_ x: SIMD4<Float>, _ minValue: SIMD4<Float>, _ maxValue: SIMD4<Float>) -> SIMD4<Float> { clamp(x, min: minValue, max: maxValue) }

#endif
