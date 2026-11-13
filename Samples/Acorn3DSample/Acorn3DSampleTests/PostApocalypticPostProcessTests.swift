import Foundation
import simd
import Testing
import AcornEngine
import AcornMath
@testable import Acorn3DSample

@Suite("Post-Apocalyptic & Depth-Buffer Moss Shader Tests")
struct PostApocalypticPostProcessTests {

    @Test("PostApocalypticUniforms memory layout is strictly 16-byte aligned for Metal")
    func uniformsMemoryLayout() {
        let size = MemoryLayout<PostApocalypticUniforms>.size
        let stride = MemoryLayout<PostApocalypticUniforms>.stride
        let alignment = MemoryLayout<PostApocalypticUniforms>.alignment
        
        #expect(alignment == 16, "PostApocalypticUniforms must be 16-byte aligned for Metal constant buffers")
        #expect(stride % 16 == 0, "PostApocalypticUniforms stride must be a multiple of 16")
        #expect(size == 272, "PostApocalypticUniforms size should be exactly 272 bytes")
        #expect(stride == 272, "PostApocalypticUniforms stride should be exactly 272 bytes")
        #expect(size <= stride)
    }

    @Test("PostApocalypticUniforms default values and initialization")
    func uniformsDefaults() {
        let u = PostApocalypticUniforms()
        
        #expect(u.isEnabled == 1.0)
        #expect(abs(u.mossDensity - 0.70) < 0.001)
        #expect(abs(u.mossScale - 0.055) < 0.001)
        #expect(abs(u.weatheringAmount - 0.65) < 0.001)
        #expect(abs(u.fogDensity - 0.0018) < 0.0001)
        #expect(u.time == 0.0)
        #expect(u.playerPosition == .zero)
        
        // Check SSAO defaults
        #expect(abs(u.ssaoIntensity - 1.25) < 0.001)
        #expect(abs(u.ssaoRadius - 3.5) < 0.001)
        #expect(abs(u.ssaoBias - 0.035) < 0.001)
        #expect(u.pad0 == 0.0)
        #expect(u.pad1 == 0.0)
        #expect(u.pad2 == 0.0)
        
        // Check color palette validity
        #expect(u.mossColorDark.w == 1.0)
        #expect(u.mossColorLight.w == 1.0)
        #expect(u.mossColorLichen.w == 1.0)
        #expect(u.skyFogColor.w == 1.0)
    }

    @Test("SSAO uniforms toggle and parameter mutation")
    func ssaoUniformsToggleAndParameters() {
        var u = PostApocalypticUniforms()
        #expect(u.ssaoIntensity == 1.25)
        
        // Simulate disabling SSAO
        u.ssaoIntensity = 0.0
        #expect(u.ssaoIntensity == 0.0)
        
        // Simulate custom SSAO tuning
        u.ssaoRadius = 5.0
        u.ssaoBias = 0.05
        #expect(u.ssaoRadius == 5.0)
        #expect(u.ssaoBias == 0.05)
    }

    @Test("3D World Position unprojection roundtrip via inverse view-projection matrix")
    func worldPositionUnprojection() {
        // Construct camera view and projection matrices
        let camPos = SIMD3<Float>(10.0, 25.0, 50.0)
        let lookTarget = SIMD3<Float>(0.0, 0.0, 0.0)
        
        // Simple view matrix look-at
        let zAxis = simd_normalize(lookTarget - camPos)
        let xAxis = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), zAxis))
        let yAxis = simd_cross(zAxis, xAxis)
        
        let viewMatrix = Matrix4x4(
            SIMD4<Float>(xAxis.x, yAxis.x, zAxis.x, 0.0),
            SIMD4<Float>(xAxis.y, yAxis.y, zAxis.y, 0.0),
            SIMD4<Float>(xAxis.z, yAxis.z, zAxis.z, 0.0),
            SIMD4<Float>(-simd_dot(xAxis, camPos), -simd_dot(yAxis, camPos), -simd_dot(zAxis, camPos), 1.0)
        )
        
        let projMatrix = Matrix4x4(perspectiveFovY: .pi / 3.0, aspect: 1.5, nearZ: 1.0, farZ: 1000.0)
        let viewProj = projMatrix * viewMatrix
        let invViewProj = viewProj.inverse
        
        // Original world position (e.g. rooftop or ground point)
        let originalWorldPos = SIMD3<Float>(5.0, 12.0, -10.0)
        let clipPosH = viewProj * SIMD4<Float>(originalWorldPos.x, originalWorldPos.y, originalWorldPos.z, 1.0)
        
        // Perspective divide to NDC
        let ndc = SIMD3<Float>(clipPosH.x / clipPosH.w, clipPosH.y / clipPosH.w, clipPosH.z / clipPosH.w)
        
        // Reconstruct world position using inverse matrix
        let reconstructedH = invViewProj * SIMD4<Float>(ndc.x, ndc.y, ndc.z, 1.0)
        let reconstructedWorldPos = SIMD3<Float>(
            reconstructedH.x / reconstructedH.w,
            reconstructedH.y / reconstructedH.w,
            reconstructedH.z / reconstructedH.w
        )
        
        #expect(abs(reconstructedWorldPos.x - originalWorldPos.x) < 0.01)
        #expect(abs(reconstructedWorldPos.y - originalWorldPos.y) < 0.01)
        #expect(abs(reconstructedWorldPos.z - originalWorldPos.z) < 0.01)
    }

    @Test("PostApocalypticPostProcess offscreen target allocation and resize")
    @MainActor
    func textureAllocation() throws {
        let renderer = try NoGraphicsRenderer()
        let postProcess = PostApocalypticPostProcess(renderer: renderer)

        #expect(postProcess.offscreenTarget == nil)
        #expect(postProcess.drawableSize == nil)

        let targetSize = CGSize(width: 400, height: 800)
        postProcess.updateDrawableSize(targetSize)

        let target = try #require(postProcess.offscreenTarget)
        #expect(target.width == 400)
        #expect(target.height == 800)
        #expect(postProcess.drawableSize == targetSize)

        postProcess.updateDrawableSize(CGSize(width: 640, height: 480))
        #expect(target.width == 640)
        #expect(target.height == 480)
        #expect(postProcess.drawableSize == CGSize(width: 640, height: 480))
    }

    @Test("PostApocalypticPostProcess pipeline creation and headless two-pass render")
    @MainActor
    func pipelineStateCreation() throws {
        let renderer = try NoGraphicsRenderer()
        let postProcess = PostApocalypticPostProcess(renderer: renderer)
        #expect(postProcess.pipeline != nil, "Post-process Slang pipeline should load and compile successfully")

        postProcess.updateDrawableSize(CGSize(width: 256, height: 256))
        let context = try #require(postProcess.beginScenePass())
        let viewProj = Matrix4x4(perspectiveFovY: .pi / 3.0, aspect: 1.0, nearZ: 0.5, farZ: 100.0)
        postProcess.renderPostProcess(
            context: context,
            viewProjectionMatrix: viewProj,
            cameraPosition: SIMD3<Float>(0, 10, 20),
            playerPosition: .zero,
            deltaTime: 0.016
        )
        renderer.endFrame(context: context)
        renderer.waitIdle()
    }
}
