import Foundation
import simd

/// A struct representing a rectangle in pixels.
public struct SpriteRect: Codable, Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var w: Int
    public var h: Int
    
    public init(x: Int, y: Int, w: Int, h: Int) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

/// A struct representing a size in pixels.
public struct SpriteSize: Codable, Sendable, Equatable {
    public var w: Int
    public var h: Int
    
    public init(w: Int, h: Int) {
        self.w = w
        self.h = h
    }
}

/// A struct representing the metadata for a single frame (sprite) in the texture packer format.
public struct SpriteFrame: Codable, Sendable, Equatable {
    public var filename: String
    public var frame: SpriteRect
    public var rotated: Bool
    public var trimmed: Bool
    public var spriteSourceSize: SpriteRect
    public var sourceSize: SpriteSize
    
    public init(filename: String, frame: SpriteRect, rotated: Bool, trimmed: Bool, spriteSourceSize: SpriteRect, sourceSize: SpriteSize) {
        self.filename = filename
        self.frame = frame
        self.rotated = rotated
        self.trimmed = trimmed
        self.spriteSourceSize = spriteSourceSize
        self.sourceSize = sourceSize
    }
}

/// A struct representing the metadata block in the texture packer format.
public struct SpriteSheetMeta: Codable, Sendable, Equatable {
    public var app: String
    public var version: String
    public var image: String
    public var format: String
    public var size: SpriteSize
    public var scale: String
    
    public init(app: String, version: String, image: String, format: String, size: SpriteSize, scale: String) {
        self.app = app
        self.version = version
        self.image = image
        self.format = format
        self.size = size
        self.scale = scale
    }
}

/// The root struct for TexturePacker JSON (Array or Hash format).
public struct SpriteSheetMetadata: Codable, Sendable, Equatable {
    public var frames: [SpriteFrame]
    public var meta: SpriteSheetMeta
    
    public init(frames: [SpriteFrame], meta: SpriteSheetMeta) {
        self.frames = frames
        self.meta = meta
    }
    
    // Custom decoding to support both Array and Hash TexturePacker formats.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.meta = try container.decode(SpriteSheetMeta.self, forKey: .meta)
        
        if let arrayFrames = try? container.decode([SpriteFrame].self, forKey: .frames) {
            self.frames = arrayFrames
        } else if let hashFrames = try? container.decode([String: FrameData].self, forKey: .frames) {
            self.frames = hashFrames.map { (key, value) in
                SpriteFrame(
                    filename: key,
                    frame: value.frame,
                    rotated: value.rotated,
                    trimmed: value.trimmed,
                    spriteSourceSize: value.spriteSourceSize,
                    sourceSize: value.sourceSize
                )
            }.sorted { $0.filename < $1.filename }
        } else {
            throw DecodingError.dataCorruptedError(forKey: .frames, in: container, debugDescription: "Expected Array or Hash format for frames.")
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case frames
        case meta
    }
    
    // Helper struct for decoding the Hash format
    private struct FrameData: Codable {
        var frame: SpriteRect
        var rotated: Bool
        var trimmed: Bool
        var spriteSourceSize: SpriteRect
        var sourceSize: SpriteSize
    }
}

/// A class representing a loaded Sprite Sheet containing a texture and its metadata.
public final class SpriteSheet: @unchecked Sendable {
    /// The loaded texture.
    public let texture: any Texture
    
    /// The parsed metadata.
    public let metadata: SpriteSheetMetadata
    
    /// Initializes a new Sprite Sheet.
    /// - Parameters:
    ///   - texture: The underlying texture.
    ///   - metadata: The parsed TexturePacker metadata.
    public init(texture: any Texture, metadata: SpriteSheetMetadata) {
        self.texture = texture
        self.metadata = metadata
    }
    
    /// Finds a frame by its exact filename.
    /// - Parameter name: The name of the frame.
    /// - Returns: The `SpriteFrame` if found.
    public func frame(named name: String) -> SpriteFrame? {
        return metadata.frames.first { $0.filename == name }
    }
    
    /// Computes the UV coordinates for a given frame.
    /// - Parameter frame: The sprite frame.
    /// - Returns: The origin (top-left) and size of the UV coordinates.
    public func uvRect(for frame: SpriteFrame) -> (origin: SIMD2<Float>, size: SIMD2<Float>) {
        let texWidth = Float(texture.width)
        let texHeight = Float(texture.height)
        
        let u = Float(frame.frame.x) / texWidth
        let v = Float(frame.frame.y) / texHeight
        
        // If rotated, w and h are swapped in the frame rect in TexturePacker,
        // but let's assume standard behavior where frame.w and frame.h correspond to the bounding box in the texture.
        let uWidth = Float(frame.frame.w) / texWidth
        let vHeight = Float(frame.frame.h) / texHeight
        
        return (origin: SIMD2<Float>(u, v), size: SIMD2<Float>(uWidth, vHeight))
    }
}
