import Foundation
internal import AcornRHI

/// A resizable offscreen color and sampled-depth render target backed by `NoGraphicsAPI`.
public final class NoGraphicsOffscreenTarget: OffscreenRenderTarget, @unchecked Sendable {
    /// Current width of the offscreen attachments in pixels.
    public var width: Int {
        Int(acorn_rhi_offscreen_target_width(rhiHandle))
    }

    /// Current height of the offscreen attachments in pixels.
    public var height: Int {
        Int(acorn_rhi_offscreen_target_height(rhiHandle))
    }

    internal let deviceBox: NoGraphicsDeviceBox
    internal let rhiHandle: OpaquePointer

    internal init(deviceBox: NoGraphicsDeviceBox, rhiHandle: OpaquePointer) {
        self.deviceBox = deviceBox
        self.rhiHandle = rhiHandle
    }

    deinit {
        acorn_rhi_destroy_offscreen_target(deviceBox.handle, rhiHandle)
    }
}

/// A compiled fullscreen post-processing pipeline backed by `NoGraphicsAPI`.
public final class NoGraphicsPostProcessPipeline: PostProcessPipeline, @unchecked Sendable {
    internal let deviceBox: NoGraphicsDeviceBox
    internal let rhiHandle: OpaquePointer

    internal init(deviceBox: NoGraphicsDeviceBox, rhiHandle: OpaquePointer) {
        self.deviceBox = deviceBox
        self.rhiHandle = rhiHandle
    }

    deinit {
        acorn_rhi_destroy_post_process_pipeline(deviceBox.handle, rhiHandle)
    }
}
