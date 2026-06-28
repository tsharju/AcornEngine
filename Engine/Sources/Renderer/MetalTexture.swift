import Foundation
import Metal

/// A Metal-specific implementation of the `Texture` protocol.
public final class MetalTexture: Texture, @unchecked Sendable {
    /// The underlying Metal texture object.
    public let texture: any MTLTexture
    
    /// The width of the texture in pixels.
    public var width: Int {
        texture.width
    }
    
    /// The height of the texture in pixels.
    public var height: Int {
        texture.height
    }
    
    /// Initializes a new MetalTexture wrapping the given MTLTexture.
    /// - Parameter texture: The Metal texture to wrap.
    public init(texture: any MTLTexture) {
        self.texture = texture
    }
}
