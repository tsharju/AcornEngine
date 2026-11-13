import Foundation

/// A protocol that decodes compressed image file data (e.g., PNG, JPEG) into uncompressed 32-bit RGBA pixels.
public protocol ImageDecoder: Sendable {
    /// Decodes compressed image file data into width, height, and raw RGBA8 pixels.
    /// - Parameter data: Encoded image file data.
    /// - Returns: A tuple of width, height, and RGBA pixel array, or nil if decoding failed.
    func decode(data: Data) -> (width: Int, height: Int, pixels: [UInt8])?
}

#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO

/// Apple platform image decoder using ImageIO and CoreGraphics.
public struct CoreGraphicsImageDecoder: ImageDecoder {
    public init() {}
    
    public func decode(data: Data) -> (width: Int, height: Int, pixels: [UInt8])? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0 && height > 0 else { return nil }
        
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (width, height, pixels)
    }
}
#endif

/// A class responsible for loading textures from various sources.
public final class TextureLoader: Sendable {
    /// The renderer used to create GPU textures.
    public let renderer: (any Renderer)?
    
    /// The image decoder used to decode compressed image formats.
    public let imageDecoder: (any ImageDecoder)?
    
    /// Initializes a new TextureLoader with a Renderer backend.
    /// - Parameters:
    ///   - renderer: The Renderer backend to use.
    ///   - imageDecoder: Optional image decoder for compressed image data.
    public init(renderer: any Renderer, imageDecoder: (any ImageDecoder)? = nil) {
        self.renderer = renderer
        #if canImport(CoreGraphics) && canImport(ImageIO)
        self.imageDecoder = imageDecoder ?? CoreGraphicsImageDecoder()
        #else
        self.imageDecoder = imageDecoder
        #endif
    }
    
    /// Loads a texture from the given URL.
    /// - Parameter url: The URL of the image file.
    /// - Returns: A `Texture` object representing the loaded image.
    /// - Throws: `TextureError` if loading fails.
    public func loadTexture(from url: URL) async throws -> Texture {
        guard self.renderer != nil else {
            throw TextureError.deviceCreationFailed
        }
        let data = try Data(contentsOf: url)
        return try await loadTexture(from: data)
    }
    
    /// Loads a texture from the given binary data.
    /// - Parameter data: The data containing the image.
    /// - Returns: A `Texture` object representing the loaded image.
    /// - Throws: `TextureError` if loading fails.
    public func loadTexture(from data: Data) async throws -> Texture {
        guard let renderer = self.renderer else {
            throw TextureError.deviceCreationFailed
        }
        guard let decoder = self.imageDecoder, let (width, height, pixels) = decoder.decode(data: data) else {
            throw TextureError.loaderError(
                NSError(domain: "TextureLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode image data for renderer"])
            )
        }
        guard let texture = renderer.createTexture(width: width, height: height, pixelData: pixels, format: .rgba8Unorm) else {
            throw TextureError.deviceCreationFailed
        }
        return texture
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
        guard width > 0, height > 0 else {
            throw TextureError.invalidDimensions
        }
        let bytesPerPixel: Int
        switch format {
        case .r8Unorm:
            bytesPerPixel = 1
        case .rgba8Unorm, .bgra8Unorm:
            bytesPerPixel = 4
        }
        guard pixels.count == width * height * bytesPerPixel else {
            throw TextureError.invalidDimensions
        }

        guard let renderer = self.renderer,
              let texture = renderer.createTexture(width: width, height: height, pixelData: pixels, format: format) else {
            throw TextureError.deviceCreationFailed
        }
        return texture
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
