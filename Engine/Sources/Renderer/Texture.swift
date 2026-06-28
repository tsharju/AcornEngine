import Foundation
import Metal

/// Opaque protocol representing a 2D texture resource.
public protocol Texture: Sendable {
    /// The width of the texture in pixels.
    var width: Int { get }
    
    /// The height of the texture in pixels.
    var height: Int { get }
}

/// A Metal-backed implementation of the `Texture` protocol.
public struct MetalTexture: Texture, @unchecked Sendable {
    /// The underlying Metal texture.
    public let mtlTexture: any MTLTexture

    /// The width of the texture in pixels.
    public var width: Int {
        mtlTexture.width
    }

    /// The height of the texture in pixels.
    public var height: Int {
        mtlTexture.height
    }

    /// Initializes a new Metal texture wrapper.
    /// - Parameter mtlTexture: The underlying Metal texture.
    public init(mtlTexture: any MTLTexture) {
        self.mtlTexture = mtlTexture
    }
}
