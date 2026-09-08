import Testing
import Foundation
@testable import AcornMath

#if canImport(simd)
import simd
#endif

@Suite("Matrix4x4 Tests")
struct Matrix4x4Tests {

    @Test("Zero and Identity matrices")
    func testZeroAndIdentity() {
        let zero = Matrix4x4.zero
        for col in 0..<4 {
            for row in 0..<4 {
                #expect(zero[row, col] == 0)
            }
        }

        let id = Matrix4x4.identity
        for col in 0..<4 {
            for row in 0..<4 {
                if row == col {
                    #expect(id[row, col] == 1)
                } else {
                    #expect(id[row, col] == 0)
                }
            }
        }
        #expect(id.determinant == 1.0)
    }

    @Test("Translation matrix")
    func testTranslation() {
        let t = Matrix4x4(translation: SIMD3<Float>(10, -20, 30))
        #expect(t.columns.3.x == 10)
        #expect(t.columns.3.y == -20)
        #expect(t.columns.3.z == 30)
        #expect(t.columns.3.w == 1)

        let point = SIMD4<Float>(1, 2, 3, 1)
        let transformed = t * point
        #expect(transformed == SIMD4<Float>(11, -18, 33, 1))

        let direction = SIMD4<Float>(1, 2, 3, 0)
        let dirTransformed = t * direction
        #expect(dirTransformed == direction)
    }

    @Test("Scaling matrix")
    func testScale() {
        let s = Matrix4x4(scale: SIMD3<Float>(2, 3, 4))
        #expect(s.columns.0.x == 2)
        #expect(s.columns.1.y == 3)
        #expect(s.columns.2.z == 4)
        #expect(s.columns.3.w == 1)

        let point = SIMD4<Float>(1, 2, 3, 1)
        let transformed = s * point
        #expect(transformed == SIMD4<Float>(2, 6, 12, 1))
    }

    @Test("Rotations around axes")
    func testRotations() {
        let angle = Float.pi / 2 // 90 degrees

        let rx = Matrix4x4(rotationX: angle)
        let p1 = rx * SIMD4<Float>(0, 1, 0, 1)
        #expect(abs(p1.x - 0) < 1e-5)
        #expect(abs(p1.y - 0) < 1e-5)
        #expect(abs(p1.z - 1) < 1e-5)

        let ry = Matrix4x4(rotationY: angle)
        let p2 = ry * SIMD4<Float>(0, 0, 1, 1)
        #expect(abs(p2.x - 1) < 1e-5)
        #expect(abs(p2.y - 0) < 1e-5)
        #expect(abs(p2.z - 0) < 1e-5)

        let rz = Matrix4x4(rotationZ: angle)
        let p3 = rz * SIMD4<Float>(1, 0, 0, 1)
        #expect(abs(p3.x - 0) < 1e-5)
        #expect(abs(p3.y - 1) < 1e-5)
        #expect(abs(p3.z - 0) < 1e-5)
    }

    @Test("Composite model matrix TRS")
    func testModelMatrixTRS() {
        let pos = SIMD3<Float>(5, 10, 15)
        let rot = SIMD3<Float>(0, Float.pi / 2, 0)
        let scl = SIMD3<Float>(2, 2, 2)

        let model = Matrix4x4(position: pos, rotation: rot, scale: scl)

        let localPt = SIMD4<Float>(1, 0, 0, 1)
        // Scaled: (2, 0, 0)
        // Rotated 90 deg around Y: (0, 0, -2)
        // Translated: (5, 10, 13)
        let worldPt = model * localPt
        #expect(abs(worldPt.x - 5) < 1e-4)
        #expect(abs(worldPt.y - 10) < 1e-4)
        #expect(abs(worldPt.z - 13) < 1e-4)
    }

    @Test("Orthographic projection")
    func testOrthographic() {
        let proj = Matrix4x4(orthographic: -10, right: 10, bottom: -5, top: 5, nearZ: 0.1, farZ: 100)
        let expectedWidthScale: Float = 2.0 / 20.0
        let expectedHeightScale: Float = 2.0 / 10.0
        let expectedZScale: Float = 1.0 / (100.0 - 0.1)

        #expect(abs(proj.columns.0.x - expectedWidthScale) < 1e-5)
        #expect(abs(proj.columns.1.y - expectedHeightScale) < 1e-5)
        #expect(abs(proj.columns.2.z - expectedZScale) < 1e-5)
    }

    @Test("Perspective projection")
    func testPerspective() {
        let fov: Float = 60.0 * .pi / 180.0
        let aspect: Float = 16.0 / 9.0
        let near: Float = 0.1
        let far: Float = 1000.0

        let proj = Matrix4x4(perspectiveFovY: fov, aspect: aspect, nearZ: near, farZ: far)

        let ys = 1.0 / tan(fov * 0.5)
        let xs = ys / aspect
        let zs = far / (far - near)

        #expect(abs(proj.columns.0.x - xs) < 1e-5)
        #expect(abs(proj.columns.1.y - ys) < 1e-5)
        #expect(abs(proj.columns.2.z - zs) < 1e-5)
        #expect(proj.columns.2.w == 1.0)
        #expect(abs(proj.columns.3.z - (-near * zs)) < 1e-5)
    }

    @Test("Matrix multiplication and associativity")
    func testMatrixMultiplication() {
        let a = Matrix4x4(translation: SIMD3<Float>(1, 2, 3))
        let b = Matrix4x4(scale: SIMD3<Float>(2, 2, 2))
        let c = Matrix4x4(rotationZ: 0.5)

        let ab_c = (a * b) * c
        let a_bc = a * (b * c)

        for col in 0..<4 {
            for row in 0..<4 {
                #expect(abs(ab_c[row, col] - a_bc[row, col]) < 1e-5)
            }
        }
    }

    @Test("Transpose involution")
    func testTranspose() {
        let a = Matrix4x4(position: SIMD3<Float>(1, 2, 3), rotation: SIMD3<Float>(0.1, 0.2, 0.3), scale: SIMD3<Float>(2, 3, 4))
        let doubleTransposed = a.transposed.transposed

        for col in 0..<4 {
            for row in 0..<4 {
                #expect(abs(a[row, col] - doubleTransposed[row, col]) < 1e-6)
            }
        }
    }

    @Test("Determinant and analytic Inverse")
    func testInverse() {
        let m = Matrix4x4(position: SIMD3<Float>(1, -2, 3), rotation: SIMD3<Float>(0.2, 0.4, 0.6), scale: SIMD3<Float>(1.5, 2.0, 0.8))

        let inv = m.inverse
        let product = m * inv

        for col in 0..<4 {
            for row in 0..<4 {
                let expected: Float = (row == col) ? 1.0 : 0.0
                #expect(abs(product[row, col] - expected) < 1e-4)
            }
        }
    }

    @Test("Singular matrix returns nil for inverted()")
    func testSingularMatrix() {
        var singular = Matrix4x4.identity
        // Make row 0 identical to row 1
        singular.columns.0 = SIMD4<Float>(1, 1, 0, 0)
        singular.columns.1 = SIMD4<Float>(1, 1, 0, 0)

        #expect(singular.inverted() == nil)
        #expect(singular.inverse == .zero)
    }

    @Test("Subscripting getter and setter")
    func testSubscripts() {
        var m = Matrix4x4.identity
        m[2, 1] = 42.0 // row 2, col 1
        #expect(m.columns.1.z == 42.0)
        #expect(m[2, 1] == 42.0)

        m[3] = SIMD4<Float>(1, 2, 3, 4)
        #expect(m.columns.3 == SIMD4<Float>(1, 2, 3, 4))
    }

    @Test("Codable encoding and decoding")
    func testCodable() throws {
        let original = Matrix4x4(position: SIMD3<Float>(1, 2, 3), rotation: SIMD3<Float>(0.1, 0.2, 0.3), scale: SIMD3<Float>(4, 5, 6))
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Matrix4x4.self, from: data)

        #expect(original == decoded)
    }

    #if canImport(simd)
    @Test("Mathematical parity with Apple Darwin simd_float4x4")
    func testDarwinSimdParity() {
        let pos = SIMD3<Float>(3, -4, 5)
        let rot = SIMD3<Float>(0.2, -0.5, 0.8)
        let scl = SIMD3<Float>(1.2, 0.8, 2.5)

        let myM = Matrix4x4(position: pos, rotation: rot, scale: scl)
        let appleSimd = myM.asSIMD

        // Parity of inverse
        let myInv = myM.inverse
        let appleInv = appleSimd.inverse

        for col in 0..<4 {
            for row in 0..<4 {
                let diff = abs(myInv[row, col] - appleInv[col][row])
                #expect(diff < 1e-4)
            }
        }

        // Parity of transpose
        let myT = myM.transposed
        let appleT = appleSimd.transpose

        for col in 0..<4 {
            for row in 0..<4 {
                let diff = abs(myT[row, col] - appleT[col][row])
                #expect(diff < 1e-6)
            }
        }
    }
    #endif
}
