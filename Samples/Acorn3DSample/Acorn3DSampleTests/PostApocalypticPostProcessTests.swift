import Foundation
import Metal
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

    @Test("PostApocalypticPostProcess texture reallocation on size change")
    @MainActor
    func textureAllocation() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let postProcess = PostApocalypticPostProcess(device: device)
        
        #expect(postProcess.sceneColorTexture == nil)
        #expect(postProcess.sceneDepthTexture == nil)
        
        let targetSize = CGSize(width: 400, height: 800)
        postProcess.updateDrawableSize(targetSize)
        
        #expect(postProcess.sceneColorTexture != nil)
        #expect(postProcess.sceneDepthTexture != nil)
        #expect(postProcess.sceneColorTexture?.width == 400)
        #expect(postProcess.sceneColorTexture?.height == 800)
        #expect(postProcess.sceneDepthTexture?.width == 400)
        #expect(postProcess.sceneDepthTexture?.height == 800)
        #expect(postProcess.sceneDepthTexture?.pixelFormat == .depth32Float)
        #expect(postProcess.sceneColorTexture?.pixelFormat == .bgra8Unorm_srgb)
    }

    @Test("PostApocalypticPostProcess pipeline state creation")
    @MainActor
    func pipelineStateCreation() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let postProcess = PostApocalypticPostProcess(device: device)
        #expect(postProcess.pipelineState != nil, "Post-process render pipeline state should compile successfully")
    }
}
