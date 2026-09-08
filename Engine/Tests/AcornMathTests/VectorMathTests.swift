import Testing
import Foundation
@testable import AcornMath

#if canImport(simd)
import simd
#endif

@Suite("VectorMath Tests")
struct VectorMathTests {

    @Test("Dot product")
    func testDot() {
        let v2a = SIMD2<Float>(1, 2)
        let v2b = SIMD2<Float>(3, 4)
        #expect(AcornMath.dot(v2a, v2b) == 11.0)
        #expect(v2a.dot(v2b) == 11.0)

        let v3a = SIMD3<Float>(1, 2, 3)
        let v3b = SIMD3<Float>(4, 5, 6)
        #expect(AcornMath.dot(v3a, v3b) == 32.0)
        #expect(v3a.dot(v3b) == 32.0)

        let v4a = SIMD4<Float>(1, 2, 3, 4)
        let v4b = SIMD4<Float>(5, 6, 7, 8)
        #expect(AcornMath.dot(v4a, v4b) == 70.0)
        #expect(v4a.dot(v4b) == 70.0)
    }

    @Test("Cross product")
    func testCross() {
        let x = SIMD3<Float>(1, 0, 0)
        let y = SIMD3<Float>(0, 1, 0)
        let z = AcornMath.cross(x, y)
        #expect(z == SIMD3<Float>(0, 0, 1))
        #expect(x.cross(y) == SIMD3<Float>(0, 0, 1))

        let negZ = AcornMath.cross(y, x)
        #expect(negZ == SIMD3<Float>(0, 0, -1))
    }

    @Test("Length and squared length")
    func testLength() {
        let v2 = SIMD2<Float>(3, 4)
        #expect(AcornMath.length(v2) == 5.0)
        #expect(AcornMath.lengthSquared(v2) == 25.0)
        #expect(v2.length == 5.0)
        #expect(v2.lengthSquared == 25.0)

        let v3 = SIMD3<Float>(0, 0, 10)
        #expect(AcornMath.length(v3) == 10.0)
        #expect(v3.length == 10.0)

        let v4 = SIMD4<Float>(2, 2, 2, 2)
        #expect(AcornMath.length(v4) == 4.0)
        #expect(v4.length == 4.0)
    }

    @Test("Distance")
    func testDistance() {
        let p1 = SIMD3<Float>(0, 0, 0)
        let p2 = SIMD3<Float>(0, 3, 4)
        #expect(AcornMath.distance(p1, p2) == 5.0)
    }

    @Test("Normalization")
    func testNormalize() {
        let v = SIMD3<Float>(10, 0, 0)
        let n = AcornMath.normalize(v)
        #expect(n == SIMD3<Float>(1, 0, 0))
        #expect(v.normalized() == SIMD3<Float>(1, 0, 0))

        let zero = SIMD3<Float>(0, 0, 0)
        let nZero = AcornMath.normalize(zero)
        #expect(nZero == .zero)
        #expect(zero.normalized() == .zero)
    }

    @Test("Linear interpolation (mix)")
    func testMix() {
        #expect(AcornMath.mix(0.0, 10.0, t: 0.5) == 5.0)

        let a = SIMD3<Float>(0, 10, 20)
        let b = SIMD3<Float>(10, 20, 40)
        let m = AcornMath.mix(a, b, t: 0.5)
        #expect(m == SIMD3<Float>(5, 15, 30))

        let tVec = SIMD3<Float>(0.0, 0.5, 1.0)
        let mVec = AcornMath.mix(a, b, t: tVec)
        #expect(mVec == SIMD3<Float>(0, 15, 40))
    }

    @Test("Clamp")
    func testClamp() {
        let val1: Float = 15.0
        let val2: Float = -5.0
        let val3: Float = 5.0
        #expect(AcornMath.clamp(val1, min: 0.0, max: 10.0) == 10.0)
        #expect(AcornMath.clamp(val2, min: 0.0, max: 10.0) == 0.0)
        #expect(AcornMath.clamp(val3, min: 0.0, max: 10.0) == 5.0)

        let v = SIMD3<Float>(-1, 5, 20)
        let minV = SIMD3<Float>(0, 0, 0)
        let maxV = SIMD3<Float>(10, 10, 10)
        let clamped = AcornMath.clamp(v, min: minV, max: maxV)
        #expect(clamped == SIMD3<Float>(0, 5, 10))
    }

    #if canImport(simd)
    @Test("Parity with Darwin simd functions")
    func testDarwinSimdParity() {
        let v3a = SIMD3<Float>(1.5, -2.5, 3.5)
        let v3b = SIMD3<Float>(4.0, 1.0, -2.0)

        let dotDiff = abs(AcornMath.dot(v3a, v3b) - simd.simd_dot(v3a, v3b))
        #expect(dotDiff < 1e-6)

        let lenDiff = abs(AcornMath.length(v3a) - simd.simd_length(v3a))
        #expect(lenDiff < 1e-6)

        let myCross = AcornMath.cross(v3a, v3b)
        let appleCross = simd.simd_cross(v3a, v3b)
        #expect(myCross == appleCross)

        let myNorm = AcornMath.normalize(v3a)
        let appleNorm = simd.simd_normalize(v3a)
        let normDiff = AcornMath.length(myNorm - appleNorm)
        #expect(normDiff < 1e-6)
    }
    #endif
}
