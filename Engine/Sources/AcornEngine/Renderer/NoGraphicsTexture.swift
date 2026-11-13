import Foundation
internal import AcornRHI

/// A GPU-resident 2D texture backed by `NoGraphicsAPI`.
public final class NoGraphicsTexture: Texture, @unchecked Sendable {
    /// Texture width in pixels.
    public let width: Int

    /// Texture height in pixels.
    public let height: Int

    /// Pixel format of the texture data.
    public let format: TextureFormat

    internal let deviceBox: NoGraphicsDeviceBox
    internal let rhiHandle: OpaquePointer

    internal init(
        deviceBox: NoGraphicsDeviceBox,
        rhiHandle: OpaquePointer,
        format: TextureFormat
    ) {
        self.deviceBox = deviceBox
        self.rhiHandle = rhiHandle
        self.width = Int(acorn_rhi_texture_width(rhiHandle))
        self.height = Int(acorn_rhi_texture_height(rhiHandle))
        self.format = format
    }

    deinit {
        acorn_rhi_destroy_texture(deviceBox.handle, rhiHandle)
    }
}
