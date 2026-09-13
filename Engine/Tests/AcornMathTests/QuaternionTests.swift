import Testing
import Foundation
import AcornMath

@Suite("Quaternion Tests")
struct QuaternionTests {
    @Test("Matrix4x4 quaternion initialization matches Euler rotations")
    func testMatrixFromQuaternion() {
        // Identity quaternion
        let qIdentity = SIMD4<Float>(0, 0, 0, 1)
        let mIdentity = Matrix4x4(quaternion: qIdentity)
        #expect(mIdentity == Matrix4x4.identity)
        
        // 90 degrees around X
        let angleX = Float.pi / 2.0
        let qX = SIMD4<Float>(sin(angleX / 2.0), 0, 0, cos(angleX / 2.0))
        let mQuatX = Matrix4x4(quaternion: qX)
        let mEulerX = Matrix4x4(rotationX: angleX)
        
        for col in 0..<4 {
            for row in 0..<4 {
                #expect(abs(mQuatX[row, col] - mEulerX[row, col]) < 0.0001)
            }
        }
        
        // 90 degrees around Y
        let angleY = Float.pi / 2.0
        let qY = SIMD4<Float>(0, sin(angleY / 2.0), 0, cos(angleY / 2.0))
        let mQuatY = Matrix4x4(quaternion: qY)
        let mEulerY = Matrix4x4(rotationY: angleY)
        
        for col in 0..<4 {
            for row in 0..<4 {
                #expect(abs(mQuatY[row, col] - mEulerY[row, col]) < 0.0001)
            }
        }
        
        // 90 degrees around Z
        let angleZ = Float.pi / 2.0
        let qZ = SIMD4<Float>(0, 0, sin(angleZ / 2.0), cos(angleZ / 2.0))
        let mQuatZ = Matrix4x4(quaternion: qZ)
        let mEulerZ = Matrix4x4(rotationZ: angleZ)
        
        for col in 0..<4 {
            for row in 0..<4 {
                #expect(abs(mQuatZ[row, col] - mEulerZ[row, col]) < 0.0001)
            }
        }
    }
    
    @Test("Quaternion slerp interpolation")
    func testQuaternionSlerp() {
        let q1 = SIMD4<Float>(0, 0, 0, 1) // 0 deg
        let angle = Float.pi / 2.0
        let q2 = SIMD4<Float>(0, 0, sin(angle / 2.0), cos(angle / 2.0)) // 90 deg around Z
        
        // At t = 0
        let slerp0 = slerp(q1, q2, t: 0.0)
        #expect(abs(slerp0.x - q1.x) < 0.0001)
        #expect(abs(slerp0.y - q1.y) < 0.0001)
        #expect(abs(slerp0.z - q1.z) < 0.0001)
        #expect(abs(slerp0.w - q1.w) < 0.0001)
        
        // At t = 1
        let slerp1 = slerp(q1, q2, t: 1.0)
        #expect(abs(slerp1.x - q2.x) < 0.0001)
        #expect(abs(slerp1.y - q2.y) < 0.0001)
        #expect(abs(slerp1.z - q2.z) < 0.0001)
        #expect(abs(slerp1.w - q2.w) < 0.0001)
        
        // At t = 0.5 (should be 45 deg around Z)
        let midAngle = Float.pi / 4.0
        let expectedMid = SIMD4<Float>(0, 0, sin(midAngle / 2.0), cos(midAngle / 2.0))
        let slerpHalf = slerp(q1, q2, t: 0.5)
        #expect(abs(slerpHalf.x - expectedMid.x) < 0.0001)
        #expect(abs(slerpHalf.y - expectedMid.y) < 0.0001)
        #expect(abs(slerpHalf.z - expectedMid.z) < 0.0001)
        #expect(abs(slerpHalf.w - expectedMid.w) < 0.0001)
        
        // Collinear / identical quaternions
        let slerpCollinear = slerp(q1, q1, t: 0.5)
        #expect(abs(slerpCollinear.w - 1.0) < 0.0001)
        
        // Opposite sign representation of same rotation (q and -q)
        let slerpOpposite = slerp(q1, -q1, t: 0.5)
        #expect(abs(slerpOpposite.w - 1.0) < 0.0001 || abs(slerpOpposite.w - (-1.0)) < 0.0001)
    }
}
