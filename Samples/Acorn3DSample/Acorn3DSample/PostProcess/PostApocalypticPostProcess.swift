import Foundation
import CoreGraphics
import AcornEngine
import AcornMath

/// Uniform structure passed to the post-apocalyptic post-processing shader.
/// Memory layout is strictly aligned to 16 bytes for GPU constant buffers.
public struct PostApocalypticUniforms: Sendable, Equatable {
    /// Inverse of the camera's view-projection matrix used for depth-to-world unprojection.
    public var inverseViewProjectionMatrix: Matrix4x4
    /// Camera view-projection matrix used for world-to-clip projection in SSAO.
    public var viewProjectionMatrix: Matrix4x4
    /// Camera world position (xyz) with 1.0 in w.
    public var cameraPosition: SIMD4<Float>
    /// Player character world position (xyz) used to exclude the player from post-processing.
    public var playerPosition: SIMD4<Float>
    /// Dark moss / damp vegetation base color.
    public var mossColorDark: SIMD4<Float>
    /// Fresh vibrant moss highlight color.
    public var mossColorLight: SIMD4<Float>
    /// Lichen / chartreuse accents.
    public var mossColorLichen: SIMD4<Float>
    /// Atmospheric overcast sky and distance fog color.
    public var skyFogColor: SIMD4<Float>
    /// Moss coverage density factor [0.0 ... 1.0].
    public var mossDensity: Float
    /// Perlin noise spatial scale factor.
    public var mossScale: Float
    /// Weathering, dirt and desaturation amount [0.0 ... 1.0].
    public var weatheringAmount: Float
    /// Exponential distance fog density factor.
    public var fogDensity: Float
    /// Elapsed time in seconds for atmospheric animation.
    public var time: Float
    /// 1.0 if post-apocalyptic rendering is active, 0.0 for pristine baseline.
    public var isEnabled: Float
    /// Screen-space ambient occlusion intensity factor [0.0 ... 2.0].
    public var ssaoIntensity: Float
    /// World-space radius in meters for occlusion sampling.
    public var ssaoRadius: Float
    /// Horizon bias to prevent self-occlusion artifacts on flat surfaces.
    public var ssaoBias: Float
    /// Padding floats to maintain strict 16-byte alignment.
    public var pad0: Float
    public var pad1: Float
    public var pad2: Float

    /// Initializes post-apocalyptic rendering parameters with atmospheric botanical defaults.
    public init(
        inverseViewProjectionMatrix: Matrix4x4 = .identity,
        viewProjectionMatrix: Matrix4x4 = .identity,
        cameraPosition: SIMD4<Float> = SIMD4<Float>(0, 30, 60, 1),
        playerPosition: SIMD4<Float> = .zero,
        mossColorDark: SIMD4<Float> = SIMD4<Float>(0.13, 0.24, 0.09, 1.0),
        mossColorLight: SIMD4<Float> = SIMD4<Float>(0.28, 0.42, 0.15, 1.0),
        mossColorLichen: SIMD4<Float> = SIMD4<Float>(0.46, 0.54, 0.18, 1.0),
        skyFogColor: SIMD4<Float> = SIMD4<Float>(0.32, 0.36, 0.33, 1.0),
        mossDensity: Float = 0.70,
        mossScale: Float = 0.055,
        weatheringAmount: Float = 0.65,
        fogDensity: Float = 0.0018,
        time: Float = 0.0,
        isEnabled: Float = 1.0,
        ssaoIntensity: Float = 1.25,
        ssaoRadius: Float = 3.5,
        ssaoBias: Float = 0.035
    ) {
        self.inverseViewProjectionMatrix = inverseViewProjectionMatrix
        self.viewProjectionMatrix = viewProjectionMatrix
        self.cameraPosition = cameraPosition
        self.playerPosition = playerPosition
        self.mossColorDark = mossColorDark
        self.mossColorLight = mossColorLight
        self.mossColorLichen = mossColorLichen
        self.skyFogColor = skyFogColor
        self.mossDensity = mossDensity
        self.mossScale = mossScale
        self.weatheringAmount = weatheringAmount
        self.fogDensity = fogDensity
        self.time = time
        self.isEnabled = isEnabled
        self.ssaoIntensity = ssaoIntensity
        self.ssaoRadius = ssaoRadius
        self.ssaoBias = ssaoBias
        self.pad0 = 0.0
        self.pad1 = 0.0
        self.pad2 = 0.0
    }
}

/// Row-major GPU layout matching `PostApocalypticUniforms` in `postprocess.slang`.
private struct GpuPackedPostApocalypticUniforms {
    var inverseViewProjectionMatrix: NoGraphicsRenderer.RowMajorFloat4x4
    var viewProjectionMatrix: NoGraphicsRenderer.RowMajorFloat4x4
    var cameraPosition: SIMD4<Float>
    var playerPosition: SIMD4<Float>
    var mossColorDark: SIMD4<Float>
    var mossColorLight: SIMD4<Float>
    var mossColorLichen: SIMD4<Float>
    var skyFogColor: SIMD4<Float>
    var mossDensity: Float
    var mossScale: Float
    var weatheringAmount: Float
    var fogDensity: Float
    var time: Float
    var isEnabled: Float
    var ssaoIntensity: Float
    var ssaoRadius: Float
    var ssaoBias: Float
    var pad0: Float
    var pad1: Float
    var pad2: Float

    init(packing uniforms: PostApocalypticUniforms) {
        self.inverseViewProjectionMatrix = NoGraphicsRenderer.packRowMajor(
            uniforms.inverseViewProjectionMatrix,
            flipClipY: false
        )
        self.viewProjectionMatrix = NoGraphicsRenderer.packRowMajor(
            uniforms.viewProjectionMatrix,
            flipClipY: false
        )
        self.cameraPosition = uniforms.cameraPosition
        self.playerPosition = uniforms.playerPosition
        self.mossColorDark = uniforms.mossColorDark
        self.mossColorLight = uniforms.mossColorLight
        self.mossColorLichen = uniforms.mossColorLichen
        self.skyFogColor = uniforms.skyFogColor
        self.mossDensity = uniforms.mossDensity
        self.mossScale = uniforms.mossScale
        self.weatheringAmount = uniforms.weatheringAmount
        self.fogDensity = uniforms.fogDensity
        self.time = uniforms.time
        self.isEnabled = uniforms.isEnabled
        self.ssaoIntensity = uniforms.ssaoIntensity
        self.ssaoRadius = uniforms.ssaoRadius
        self.ssaoBias = uniforms.ssaoBias
        self.pad0 = uniforms.pad0
        self.pad1 = uniforms.pad1
        self.pad2 = uniforms.pad2
    }
}

/// A two-pass post-processing pipeline backed by `NoGraphicsAPI` that unprojects the depth buffer
/// to 3D world coordinates, reconstructs surface normals with screen-space derivatives, and renders
/// procedural Perlin noise moss, weathered surfaces, SSAO, distance fog, and overcast skies.
@MainActor
public final class PostApocalypticPostProcess {
    /// Active engine renderer driving offscreen scene capture and fullscreen post-processing.
    public let renderer: any Renderer

    /// Compiled Slang fullscreen post-processing pipeline, if loaded successfully.
    public private(set) var pipeline: (any PostProcessPipeline)?

    /// Resizable offscreen color and sampled-depth render target pair.
    public private(set) var offscreenTarget: (any OffscreenRenderTarget)?

    /// Current offscreen render target dimensions in pixels, or `nil` before initial layout.
    public var drawableSize: CGSize? {
        guard let offscreenTarget else { return nil }
        return CGSize(width: offscreenTarget.width, height: offscreenTarget.height)
    }

    /// Tunable post-apocalyptic post-process shader parameters.
    public var uniforms = PostApocalypticUniforms()

    /// Clear color matching atmospheric overcast twilight sky used for Pass 1 scene rendering.
    public var skyClearColor: SIMD4<Float> {
        SIMD4<Float>(0.30, 0.34, 0.32, 1.0)
    }

    private var elapsedTime: Float = 0.0

    /// Initializes the post-processing pipeline and compiles/loads the Slang fullscreen shader pair.
    /// - Parameter renderer: The active `AcornEngine` renderer.
    public init(renderer: any Renderer) {
        self.renderer = renderer
        self.pipeline = Self.buildPipeline(renderer: renderer)
    }

    /// Allocates or resizes offscreen color and depth textures to match the drawable pixel size.
    /// - Parameter size: Drawable dimensions in pixels.
    public func updateDrawableSize(_ size: CGSize) {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return }

        if let offscreenTarget {
            if offscreenTarget.width != width || offscreenTarget.height != height {
                renderer.resizeOffscreenTarget(offscreenTarget, width: width, height: height)
            }
        } else {
            offscreenTarget = renderer.createOffscreenTarget(width: width, height: height)
        }
    }

    /// Begins Pass 1 by returning a `RenderContext` targeting the offscreen color and sampled depth textures.
    /// - Returns: A `RenderContext` for rendering the 3D scene offscreen, or `nil` if unavailable.
    public func beginScenePass() -> (any RenderContext)? {
        guard pipeline != nil, let offscreenTarget else {
            return nil
        }
        return renderer.beginOffscreenFrame(target: offscreenTarget, clearColor: skyClearColor)
    }

    /// Executes Pass 2: transitions offscreen color & depth to fragment read and draws the fullscreen shader.
    /// - Parameters:
    ///   - context: The active frame context returned by `beginScenePass()`.
    ///   - viewProjectionMatrix: Unflipped camera `projection * view` matrix.
    ///   - cameraPosition: Camera world position in scene meters.
    ///   - playerPosition: Player character world position in scene meters.
    ///   - deltaTime: Elapsed frame delta in seconds.
    public func renderPostProcess(
        context: any RenderContext,
        viewProjectionMatrix: Matrix4x4,
        cameraPosition: SIMD3<Float>,
        playerPosition: SIMD3<Float>,
        deltaTime: TimeInterval
    ) {
        guard let pipeline, let offscreenTarget else { return }

        elapsedTime += Float(deltaTime)
        uniforms.time = elapsedTime
        uniforms.viewProjectionMatrix = viewProjectionMatrix
        uniforms.inverseViewProjectionMatrix = viewProjectionMatrix.inverse
        uniforms.cameraPosition = SIMD4<Float>(cameraPosition.x, cameraPosition.y, cameraPosition.z, 1.0)
        uniforms.playerPosition = SIMD4<Float>(playerPosition.x, playerPosition.y, playerPosition.z, 1.0)

        renderer.beginPostProcessPass(context: context)
        let gpuUniforms = GpuPackedPostApocalypticUniforms(packing: uniforms)
        renderer.renderPostProcess(
            pipeline: pipeline,
            target: offscreenTarget,
            uniforms: gpuUniforms,
            context: context
        )
    }

    // MARK: - Compiled Slang Shader Loading

    private static func buildPipeline(renderer: any Renderer) -> (any PostProcessPipeline)? {
        guard let (vertexData, fragmentData) = loadCompiledShaderPair() else {
            print("PostApocalypticPostProcess: Failed to locate compiled postprocess metallib shaders")
            return nil
        }
        let created = renderer.createPostProcessPipeline(
            vertexShaderData: vertexData,
            fragmentShaderData: fragmentData,
            vertexEntry: "vertexMain",
            fragmentEntry: "fragmentMain"
        )
        if created == nil {
            print("PostApocalypticPostProcess: Failed to create NoGraphics post-process pipeline")
        }
        return created
    }

    private static func loadCompiledShaderPair() -> (vertex: Data, fragment: Data)? {
        #if os(iOS)
        let vertexNames = ["postprocess_vertex_ios", "postprocess_vertex"]
        let fragmentNames = ["postprocess_fragment_ios", "postprocess_fragment"]
        let subdirectories = [nil, "Resources", "CompiledShaders/ios"]
        #elseif os(macOS)
        let vertexNames = ["postprocess_vertex", "postprocess_vertex_macos"]
        let fragmentNames = ["postprocess_fragment", "postprocess_fragment_macos"]
        let subdirectories = [nil, "Resources", "CompiledShaders/macos"]
        #else
        return nil
        #endif

        let bundles = [Bundle.main, Bundle(for: PostApocalypticPostProcess.self)]
        for bundle in bundles {
            for (vName, fName) in zip(vertexNames, fragmentNames) {
                for subdir in subdirectories {
                    if let vURL = bundle.url(forResource: vName, withExtension: "metallib", subdirectory: subdir),
                       let fURL = bundle.url(forResource: fName, withExtension: "metallib", subdirectory: subdir),
                       let vData = try? Data(contentsOf: vURL),
                       let fData = try? Data(contentsOf: fURL),
                       !vData.isEmpty, !fData.isEmpty {
                        return (vData, fData)
                    }
                }
            }
        }
        return nil
    }
}
