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

/// A struct representing an animation tag block (e.g. from Aseprite JSON export).
public struct SpriteSheetFrameTag: Codable, Sendable, Equatable {
    public var name: String
    public var from: Int
    public var to: Int
    public var direction: String?
    
    public init(name: String, from: Int, to: Int, direction: String? = nil) {
        self.name = name
        self.from = from
        self.to = to
        self.direction = direction
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
    public var duration: Int?
    
    public init(
        filename: String,
        frame: SpriteRect,
        rotated: Bool,
        trimmed: Bool,
        spriteSourceSize: SpriteRect,
        sourceSize: SpriteSize,
        duration: Int? = nil
    ) {
        self.filename = filename
        self.frame = frame
        self.rotated = rotated
        self.trimmed = trimmed
        self.spriteSourceSize = spriteSourceSize
        self.sourceSize = sourceSize
        self.duration = duration
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
    public var frameTags: [SpriteSheetFrameTag]?
    
    public init(
        app: String,
        version: String,
        image: String,
        format: String,
        size: SpriteSize,
        scale: String,
        frameTags: [SpriteSheetFrameTag]? = nil
    ) {
        self.app = app
        self.version = version
        self.image = image
        self.format = format
        self.size = size
        self.scale = scale
        self.frameTags = frameTags
    }
}

/// The root struct for TexturePacker / Aseprite JSON (Array or Hash format).
public struct SpriteSheetMetadata: Codable, Sendable, Equatable {
    public var frames: [SpriteFrame]
    public var meta: SpriteSheetMeta
    
    public init(frames: [SpriteFrame], meta: SpriteSheetMeta) {
        self.frames = frames
        self.meta = meta
    }
    
    // Custom decoding to support both Array and Hash TexturePacker/Aseprite formats.
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
                    sourceSize: value.sourceSize,
                    duration: value.duration
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
        var duration: Int?
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
        
        let uWidth = Float(frame.frame.w) / texWidth
        let vHeight = Float(frame.frame.h) / texHeight
        
        return (origin: SIMD2<Float>(u, v), size: SIMD2<Float>(uWidth, vHeight))
    }
    
    /// Automatically groups frames matching common prefix patterns into named animation clips.
    /// E.g. `["knight_walk_0", "knight_walk_1", "knight_jump_0"]` -> clips `"knight_walk"`, `"knight_jump"`.
    /// - Parameters:
    ///   - fps: The frame rate in frames per second (defaults to `10.0`).
    ///   - playbackMode: The playback mode (defaults to `.loop`).
    /// - Returns: A dictionary of animation clips keyed by clip name.
    public func createAnimationClips(
        fps: Double = 10.0,
        playbackMode: SpriteAnimationPlaybackMode = .loop
    ) -> [String: SpriteAnimationClip] {
        var groups: [String: [(index: Int, frame: SpriteFrame)]] = [:]
        
        let defaultDuration = 1.0 / max(0.001, fps)
        
        for frame in metadata.frames {
            // Strip file extensions if present
            var baseName = frame.filename
            if let dotIndex = baseName.lastIndex(of: ".") {
                baseName = String(baseName[..<dotIndex])
            }
            
            // Extract trailing numerical index if present: e.g. "hero_walk_03" -> ("hero_walk", 3)
            var clipName = baseName
            var frameIndex = 0
            
            if let lastUnderscore = baseName.lastIndex(of: "_") {
                let suffix = String(baseName[baseName.index(after: lastUnderscore)...])
                if let num = Int(suffix) {
                    clipName = String(baseName[..<lastUnderscore])
                    frameIndex = num
                }
            }
            
            groups[clipName, default: []].append((index: frameIndex, frame: frame))
        }
        
        var result: [String: SpriteAnimationClip] = [:]
        for (name, items) in groups {
            let sortedItems = items.sorted { $0.index < $1.index }
            let frames = sortedItems.map { item -> SpriteAnimationFrame in
                let duration: Double
                if let ms = item.frame.duration, ms > 0 {
                    duration = Double(ms) / 1000.0
                } else {
                    duration = defaultDuration
                }
                return SpriteAnimationFrame(frameName: item.frame.filename, duration: duration)
            }
            result[name] = SpriteAnimationClip(name: name, frames: frames, playbackMode: playbackMode)
        }
        
        return result
    }
    
    /// Creates animation clips using `frameTags` defined in the metadata (e.g. from Aseprite exports).
    /// - Parameter defaultFps: The fallback frame rate if individual frame duration is absent (defaults to `10.0`).
    /// - Returns: A dictionary of animation clips keyed by tag name.
    public func createAnimationClipsFromTags(defaultFps: Double = 10.0) -> [String: SpriteAnimationClip] {
        guard let tags = metadata.meta.frameTags, !tags.isEmpty else {
            return [:]
        }
        
        let defaultDuration = 1.0 / max(0.001, defaultFps)
        var result: [String: SpriteAnimationClip] = [:]
        let allFrames = metadata.frames
        
        for tag in tags {
            guard tag.from >= 0, tag.to >= tag.from, tag.from < allFrames.count else { continue }
            let clampedTo = min(tag.to, allFrames.count - 1)
            let subFrames = allFrames[tag.from...clampedTo]
            
            let frames = subFrames.map { frame -> SpriteAnimationFrame in
                let duration: Double
                if let ms = frame.duration, ms > 0 {
                    duration = Double(ms) / 1000.0
                } else {
                    duration = defaultDuration
                }
                return SpriteAnimationFrame(frameName: frame.filename, duration: duration)
            }
            
            let mode: SpriteAnimationPlaybackMode
            switch tag.direction?.lowercased() {
            case "pingpong":
                mode = .pingPong
            case "reverse":
                mode = .reverseLoop
            default:
                mode = .loop
            }
            
            result[tag.name] = SpriteAnimationClip(name: tag.name, frames: frames, playbackMode: mode)
        }
        
        return result
    }
}
