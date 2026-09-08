import Foundation
import AcornMath

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(CoreText)
import CoreText
#endif

/// Font metrics specifying vertical layout dimensions in points.
public struct FontMetrics: Sendable, Equatable {
    /// Font ascent in points.
    public var ascent: Float
    /// Font descent in points.
    public var descent: Float
    /// Font leading in points.
    public var leading: Float
    /// Total line height in points (ascent + descent + leading).
    public var lineHeight: Float
    
    public init(ascent: Float, descent: Float, leading: Float, lineHeight: Float) {
        self.ascent = ascent
        self.descent = descent
        self.leading = leading
        self.lineHeight = lineHeight
    }
}

/// A rasterized glyph holding layout metadata and optional grayscale bitmap pixels.
public struct RasterizedGlyph: Sendable {
    /// The character represented by this glyph.
    public var char: Character
    /// The size of the glyph in points/local coordinates (width, height).
    public var size: SIMD2<Float>
    /// The bearing offset relative to baseline pen origin (xOffset, yOffset).
    public var offset: SIMD2<Float>
    /// The horizontal advance distance after drawing this glyph.
    public var xAdvance: Float
    /// The bounding rectangle in points (x, y, width, height).
    public var boundingRect: SIMD4<Float>
    /// Grayscale 8-bit bitmap buffer centered in a cellSize x cellSize grid, or nil for empty/whitespace glyphs.
    public var grayscalePixels: [UInt8]?
    
    public init(
        char: Character,
        size: SIMD2<Float>,
        offset: SIMD2<Float>,
        xAdvance: Float,
        boundingRect: SIMD4<Float>,
        grayscalePixels: [UInt8]? = nil
    ) {
        self.char = char
        self.size = size
        self.offset = offset
        self.xAdvance = xAdvance
        self.boundingRect = boundingRect
        self.grayscalePixels = grayscalePixels
    }
}

/// Errors that can occur during font rasterization.
public enum FontRasterizerError: Error, Equatable {
    /// Font size must be greater than zero.
    case invalidFontSize
    /// Cell size must be greater than zero.
    case invalidCellSize
    /// Requested font could not be loaded or located.
    case fontNotFound(String)
}

/// A protocol abstracting font glyph rasterization from platform-specific APIs.
/// Apple platforms use `CoreTextFontRasterizer` (CoreText / CoreGraphics).
/// Android and Linux platforms use an implementation backed by stb_truetype or FreeType.
public protocol FontRasterizer: Sendable {
    /// Retrieves font layout metrics for a given font and point size.
    func metrics(fontName: String, fontSize: Float) throws -> FontMetrics
    
    /// Rasterizes the specified characters into layout metadata and optional grayscale bitmaps.
    func rasterize(
        fontName: String,
        fontSize: Float,
        characters: Set<Character>,
        cellSize: Int
    ) throws -> (metrics: FontMetrics, glyphs: [Character: RasterizedGlyph])
}

#if canImport(CoreText) && canImport(CoreGraphics)
/// Apple platform font rasterizer using CoreText and CoreGraphics.
public final class CoreTextFontRasterizer: FontRasterizer, @unchecked Sendable {
    public init() {}
    
    public func metrics(fontName: String, fontSize: Float) throws -> FontMetrics {
        guard fontSize > 0 else { throw FontRasterizerError.invalidFontSize }
        let fontNameCF = fontName as CFString
        let ctFont = CTFontCreateWithName(fontNameCF, CGFloat(fontSize), nil)
        let ascent = Float(CTFontGetAscent(ctFont))
        let descent = Float(CTFontGetDescent(ctFont))
        let leading = Float(CTFontGetLeading(ctFont))
        let lineHeight = ascent + descent + leading
        return FontMetrics(ascent: ascent, descent: descent, leading: leading, lineHeight: lineHeight)
    }
    
    public func rasterize(
        fontName: String,
        fontSize: Float,
        characters: Set<Character>,
        cellSize: Int
    ) throws -> (metrics: FontMetrics, glyphs: [Character: RasterizedGlyph]) {
        guard fontSize > 0 else { throw FontRasterizerError.invalidFontSize }
        guard cellSize > 0 else { throw FontRasterizerError.invalidCellSize }
        let fontNameCF = fontName as CFString
        let ctFont = CTFontCreateWithName(fontNameCF, CGFloat(fontSize), nil)
        
        let ascent = Float(CTFontGetAscent(ctFont))
        let descent = Float(CTFontGetDescent(ctFont))
        let leading = Float(CTFontGetLeading(ctFont))
        let lineHeight = ascent + descent + leading
        let fontMetrics = FontMetrics(ascent: ascent, descent: descent, leading: leading, lineHeight: lineHeight)
        
        var glyphMap: [Character: RasterizedGlyph] = [:]
        
        for char in characters {
            let utf16Chars = Array(char.utf16)
            var cgGlyph = CGGlyph()
            let hasGlyph = CTFontGetGlyphsForCharacters(ctFont, utf16Chars, &cgGlyph, utf16Chars.count)
            guard hasGlyph else { continue }
            
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &cgGlyph, &advance, 1)
            
            var boundingRect = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(ctFont, .horizontal, &cgGlyph, &boundingRect, 1)
            
            let glyphSize = SIMD2<Float>(Float(boundingRect.width), Float(boundingRect.height))
            let glyphOffset = SIMD2<Float>(Float(boundingRect.origin.x), Float(boundingRect.origin.y))
            let xAdvance = Float(advance.width)
            let boundRectVec = SIMD4<Float>(
                Float(boundingRect.origin.x),
                Float(boundingRect.origin.y),
                Float(boundingRect.width),
                Float(boundingRect.height)
            )
            
            var grayPixels: [UInt8]? = nil
            if !boundingRect.isEmpty && boundingRect.width > 0 && boundingRect.height > 0 {
                grayPixels = renderGlyphGrayscale(
                    ctFont: ctFont,
                    glyph: cgGlyph,
                    boundingRect: boundingRect,
                    cellSize: cellSize
                )
            }
            
            glyphMap[char] = RasterizedGlyph(
                char: char,
                size: glyphSize,
                offset: glyphOffset,
                xAdvance: xAdvance,
                boundingRect: boundRectVec,
                grayscalePixels: grayPixels
            )
        }
        
        return (metrics: fontMetrics, glyphs: glyphMap)
    }
    
    private func renderGlyphGrayscale(
        ctFont: CTFont,
        glyph: CGGlyph,
        boundingRect: CGRect,
        cellSize: Int
    ) -> [UInt8]? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixelBuffer = [UInt8](repeating: 0, count: cellSize * cellSize)
        
        guard let context = CGContext(
            data: &pixelBuffer,
            width: cellSize,
            height: cellSize,
            bitsPerComponent: 8,
            bytesPerRow: cellSize,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        
        context.setFillColor(gray: 0.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: cellSize, height: cellSize))
        
        let drawX = CGFloat(cellSize) / 2.0 - boundingRect.origin.x - boundingRect.width / 2.0
        let drawY = CGFloat(cellSize) / 2.0 - boundingRect.origin.y - boundingRect.height / 2.0
        
        context.textMatrix = .identity
        context.setFillColor(gray: 1.0, alpha: 1.0)
        
        var mutableGlyph = glyph
        var glyphPosition = CGPoint(x: drawX, y: drawY)
        CTFontDrawGlyphs(ctFont, &mutableGlyph, &glyphPosition, 1, context)
        
        return pixelBuffer
    }
}
#endif
