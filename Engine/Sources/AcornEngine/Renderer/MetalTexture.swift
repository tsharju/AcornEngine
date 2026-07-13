import Foundation
import Metal
import AcornMetal

/// A Metal-specific implementation of the `Texture` protocol.
public final class MetalTexture: Texture, @unchecked Sendable {
    /// The underlying C++ texture object.
    public let cxxTexture: UnsafeMutablePointer<Acorn.AcornMetalTexture>
    
    /// The width of the texture in pixels.
    public var width: Int {
        return Int(cxxTexture.pointee.getWidth())
    }
    
    /// The height of the texture in pixels.
    public var height: Int {
        return Int(cxxTexture.pointee.getHeight())
    }
    
    /// Initializes a new MetalTexture wrapping the given MTLTexture.
    /// - Parameter texture: The Metal texture to wrap.
    public init(texture: any MTLTexture) {
        let texturePtr = Unmanaged.passUnretained(texture).toOpaque()
        guard let cxxTexture = Acorn.AcornMetalTexture.create(texturePtr) else {
            fatalError("Failed to create AcornMetalTexture")
        }
        self.cxxTexture = cxxTexture
    }
    
    deinit {
        cxxTexture.pointee.destroy()
    }
}
