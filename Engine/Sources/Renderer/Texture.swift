import Foundation

/// A protocol representing a 2D texture resource on the GPU.
public protocol Texture: Sendable {
    /// The width of the texture in pixels.
    var width: Int { get }
    
    /// The height of the texture in pixels.
    var height: Int { get }
}

/// Errors that can occur during texture loading or creation.
public enum TextureError: Error {
    /// The input data or URL is invalid.
    case invalidData
    /// Failed to create the Metal texture resource.
    case deviceCreationFailed
    /// Underlying loader error.
    case loaderError(any Error)
    /// Unsupported pixel format or size mismatch.
    case invalidDimensions
}
