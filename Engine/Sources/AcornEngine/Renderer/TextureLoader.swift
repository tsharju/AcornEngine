import Foundation
import Metal
import MetalKit

/// A class responsible for loading textures from various sources.
public final class TextureLoader: Sendable {
    /// The Metal device used to create textures.
    private let device: (any MTLDevice)?
    
    /// The generic renderer used to create textures, if available.
    public let renderer: (any Renderer)?
    
    /// Initializes a new TextureLoader with a Metal device.
    /// - Parameter device: The Metal device to use.
    public init(device: any MTLDevice) {
        self.device = device
        self.renderer = nil
    }
    
    /// Initializes a new TextureLoader with an abstract Renderer.
    /// - Parameter renderer: The Renderer backend to use.
    public init(renderer: any Renderer) {
        self.renderer = renderer
        self.device = (renderer as? MetalRenderer)?.device
    }
    
    /// Loads a texture from the given URL.
    /// - Parameter url: The URL of the image file.
    /// - Returns: A `Texture` object representing the loaded image.
    /// - Throws: `TextureError` if loading fails.
    public func loadTexture(from url: URL) async throws -> Texture {
        guard let device = self.device else {
            throw TextureError.deviceCreationFailed
        }
        return try await Task.detached {
            let loader = MTKTextureLoader(device: device)
            let options: [MTKTextureLoader.Option: Any] = [
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                .textureStorageMode: NSNumber(value: {
                    #if os(macOS)
                    return MTLStorageMode.managed.rawValue
                    #else
                    return MTLStorageMode.shared.rawValue
                    #endif
                }())
            ]
            do {
                let texture = try loader.newTexture(URL: url, options: options)
                return MetalTexture(texture: texture)
            } catch {
                throw TextureError.loaderError(error)
            }
        }.value
    }
    
    /// Loads a texture from the given binary data.
    /// - Parameter data: The data containing the image.
    /// - Returns: A `Texture` object representing the loaded image.
    /// - Throws: `TextureError` if loading fails.
    public func loadTexture(from data: Data) async throws -> Texture {
        guard let device = self.device else {
            throw TextureError.deviceCreationFailed
        }
        return try await Task.detached {
            let loader = MTKTextureLoader(device: device)
            let options: [MTKTextureLoader.Option: Any] = [
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                .textureStorageMode: NSNumber(value: {
                    #if os(macOS)
                    return MTLStorageMode.managed.rawValue
                    #else
                    return MTLStorageMode.shared.rawValue
                    #endif
                }())
            ]
            do {
                let texture = try loader.newTexture(data: data, options: options)
                return MetalTexture(texture: texture)
            } catch {
                throw TextureError.loaderError(error)
            }
        }.value
    }
    
    /// Creates a texture from raw pixel data using an explicit TextureFormat.
    /// - Parameters:
    ///   - width: The width of the texture.
    ///   - height: The height of the texture.
    ///   - pixels: The raw byte array of pixels.
    ///   - format: The pixel format of the data.
    /// - Returns: A `Texture` object representing the pixel data.
    /// - Throws: `TextureError` if parameters or sizes are invalid.
    public func loadTexture(width: Int, height: Int, pixels: [UInt8], format: TextureFormat) async throws -> Texture {
        if let renderer = self.renderer, let texture = renderer.createTexture(width: width, height: height, pixelData: pixels, format: format) {
            return texture
        }
        
        guard let device = self.device else {
            throw TextureError.deviceCreationFailed
        }
        
        return try await Task.detached {
            let pixelFormat: MTLPixelFormat
            let bytesPerPixel: Int
            
            switch format {
            case .r8Unorm:
                pixelFormat = .r8Unorm
                bytesPerPixel = 1
            case .rgba8Unorm:
                pixelFormat = .rgba8Unorm
                bytesPerPixel = 4
            }
            
            guard pixels.count == width * height * bytesPerPixel else {
                throw TextureError.invalidDimensions
            }
            
            let descriptor = MTLTextureDescriptor()
            descriptor.pixelFormat = pixelFormat
            descriptor.width = width
            descriptor.height = height
            descriptor.usage = .shaderRead
            #if os(macOS)
            descriptor.storageMode = .managed
            #else
            descriptor.storageMode = .shared
            #endif
            
            guard let mtlTexture = device.makeTexture(descriptor: descriptor) else {
                throw TextureError.deviceCreationFailed
            }
            
            let region = MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: width, height: height, depth: 1)
            )
            
            pixels.withUnsafeBytes { bufferPointer in
                if let baseAddress = bufferPointer.baseAddress {
                    mtlTexture.replace(
                        region: region,
                        mipmapLevel: 0,
                        withBytes: baseAddress,
                        bytesPerRow: width * bytesPerPixel
                    )
                }
            }
            
            return MetalTexture(texture: mtlTexture)
        }.value
    }

    /// Creates a texture from raw pixel data.
    /// Supports 1-channel (R8Unorm) if pixels count matches width * height,
    /// or 4-channel (RGBA8Unorm) if pixels count matches width * height * 4.
    /// - Parameters:
    ///   - width: The width of the texture.
    ///   - height: The height of the texture.
    ///   - pixels: The raw byte array of pixels.
    /// - Returns: A `Texture` object representing the pixel data.
    /// - Throws: `TextureError` if parameters or sizes are invalid.
    public func loadTexture(width: Int, height: Int, pixels: [UInt8]) async throws -> Texture {
        let format: TextureFormat
        if pixels.count == width * height {
            format = .r8Unorm
        } else if pixels.count == width * height * 4 {
            format = .rgba8Unorm
        } else {
            throw TextureError.invalidDimensions
        }
        return try await loadTexture(width: width, height: height, pixels: pixels, format: format)
    }
}
