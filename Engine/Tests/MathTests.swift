import Testing
import simd
@testable import AcornEngine

@Suite("Math Tests")
struct MathTests {
    @Test("Translation matrix creates correct columns")
    func testTranslation() {
        let t = simd_float4x4(translation: SIMD3<Float>(1, 2, 3))
        #expect(t.columns.3.x == 1)
        #expect(t.columns.3.y == 2)
        #expect(t.columns.3.z == 3)
        #expect(t.columns.3.w == 1)
    }

    @Test("Scale matrix creates correct diagonal")
    func testScale() {
        let s = simd_float4x4(scale: SIMD3<Float>(2, 3, 4))
        #expect(s.columns.0.x == 2)
        #expect(s.columns.1.y == 3)
        #expect(s.columns.2.z == 4)
        #expect(s.columns.3.w == 1)
    }

    @Test("Orthographic projection creates valid matrix")
    func testOrthographic() {
        let proj = simd_float4x4(orthographic: -10, right: 10, bottom: -5, top: 5, nearZ: 0.1, farZ: 100)
        // Verify width scale
        let expectedWidthScale: Float = 2.0 / 20.0
        #expect(abs(proj.columns.0.x - expectedWidthScale) < 1e-5)
        // Verify height scale
        let expectedHeightScale: Float = 2.0 / 10.0
        #expect(abs(proj.columns.1.y - expectedHeightScale) < 1e-5)
        // Verify Z scale for Metal (0 to 1)
        let zScale: Float = 1.0 / (100.0 - 0.1)
        #expect(abs(proj.columns.2.z - zScale) < 1e-5)
    }
}
