import Foundation

/// A protocol representing a 2D texture resource on the GPU.
public protocol Texture: Sendable {
    /// The width of the texture in pixels.
    var width: Int { get }
    
    /// The height of the texture in pixels.
    var height: Int { get }
}

/// The pixel format of a 2D texture.
public enum TextureFormat: Sendable, Equatable {
    /// Single-channel 8-bit normalized format (grayscale/alpha/SDF).
    case r8Unorm
    /// 4-channel 8-bit normalized RGBA format.
    case rgba8Unorm
    /// 4-channel 8-bit normalized BGRA format.
    case bgra8Unorm
}

/// Errors that can occur during texture loading or creation.
public enum TextureError: Error, Equatable {
    /// The input data or URL is invalid.
    case invalidData
    /// Failed to create the texture resource on the renderer or graphics device.
    case deviceCreationFailed
    /// Underlying loader error.
    case loaderError(any Error)
    /// Unsupported pixel format or size mismatch.
    case invalidDimensions
    
    public static func == (lhs: TextureError, rhs: TextureError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidData, .invalidData):
            return true
        case (.deviceCreationFailed, .deviceCreationFailed):
            return true
        case (.invalidDimensions, .invalidDimensions):
            return true
        case (.loaderError(let e1), .loaderError(let e2)):
            return (e1 as NSError) == (e2 as NSError)
        default:
            return false
        }
    }
}
