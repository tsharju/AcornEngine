import Foundation
import simd

/// A description of a single glyph's layout and texture coordinates.
public struct Glyph: Sendable {
    /// The character represented by this glyph.
    public let char: Character
    
    /// The texture coordinates in [0, 1] range (x, y, width, height).
    public let uvRect: SIMD4<Float>
    
    /// The size of the glyph in points/local coordinates (width, height).
    public let size: SIMD2<Float>
    
    /// The bearing offset (xOffset, yOffset relative to the baseline pen origin).
    public let offset: SIMD2<Float>
    
    /// The distance to advance the pen after rendering this glyph.
    public let xAdvance: Float

    /// Initializes a new Glyph.
    public init(
        char: Character,
        uvRect: SIMD4<Float>,
        size: SIMD2<Float>,
        offset: SIMD2<Float>,
        xAdvance: Float
    ) {
        self.char = char
        self.uvRect = uvRect
        self.size = size
        self.offset = offset
        self.xAdvance = xAdvance
    }
}

/// A font atlas holding a single-channel texture and glyph metadata.
public final class FontAtlas: Sendable {
    /// The single-channel texture containing the SDF representation of all glyphs.
    public let texture: any Texture
    
    /// A dictionary mapping characters to their corresponding glyph metadata.
    public let glyphs: [Character: Glyph]
    
    /// The nominal font size this atlas was generated for.
    public let fontSize: Float
    
    /// The line height (ascent + descent + leading) for this font size.
    public let lineHeight: Float
    
    /// Initializes a new FontAtlas.
    public init(
        texture: any Texture,
        glyphs: [Character: Glyph],
        fontSize: Float,
        lineHeight: Float
    ) {
        self.texture = texture
        self.glyphs = glyphs
        self.fontSize = fontSize
        self.lineHeight = lineHeight
    }
}
