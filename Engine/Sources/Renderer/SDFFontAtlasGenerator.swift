import Foundation
import CoreGraphics
import CoreText
import Metal
import simd

/// Errors that can occur during SDF Font Atlas generation.
public enum SDFFontAtlasGeneratorError: Error {
    /// Failed to create the Metal texture resource.
    case textureCreationFailed
}

/// A generator that dynamically builds a signed distance field (SDF) font atlas.
public struct SDFFontAtlasGenerator {
    
    /// Generates a `FontAtlas` dynamically for a given font and set of characters.
    /// - Parameters:
    ///   - fontName: The PostScript or family name of the font (e.g., "Helvetica", "Courier").
    ///   - fontSize: The size of the font in points.
    ///   - characters: The set of characters to generate glyphs for.
    ///   - device: The Metal device to use for creating the texture.
    ///   - cellSize: The width and height of each glyph's cell in pixels. Defaults to 64.
    ///   - searchRadius: The distance radius in pixels to search for boundaries during SDF calculation. Defaults to 8.0.
    /// - Returns: A fully generated `FontAtlas`.
    /// - Throws: `SDFFontAtlasGeneratorError` if texture creation fails.
    public static func generate(
        fontName: String,
        fontSize: Float,
        characters: Set<Character> = Set((32...126).map { Character(UnicodeScalar($0)!) }),
        device: any MTLDevice,
        cellSize: Int = 64,
        searchRadius: Float = 8.0
    ) throws -> FontAtlas {
        let fontNameCF = fontName as CFString
        let ctFont = CTFontCreateWithName(fontNameCF, CGFloat(fontSize), nil)
        
        let ascent = CTFontGetAscent(ctFont)
        let descent = CTFontGetDescent(ctFont)
        let leading = CTFontGetLeading(ctFont)
        let lineHeight = Float(ascent + descent + leading)
        
        let sortedChars = characters.sorted()
        let numGlyphs = sortedChars.count
        
        // 1. Pack cells into a square texture atlas (power-of-two)
        var atlasWidth = 512
        var atlasHeight = 512
        while true {
            let cellsPerRow = atlasWidth / cellSize
            let numRows = (numGlyphs + cellsPerRow - 1) / cellsPerRow
            if numRows * cellSize <= atlasHeight {
                break
            }
            atlasWidth *= 2
            atlasHeight *= 2
        }
        
        let cellsPerRow = atlasWidth / cellSize
        var atlasBytes = [UInt8](repeating: 0, count: atlasWidth * atlasHeight)
        var glyphs = [Character: Glyph]()
        
        for (index, char) in sortedChars.enumerated() {
            let row = index / cellsPerRow
            let col = index % cellsPerRow
            let cellX = col * cellSize
            let cellY = row * cellSize
            
            let utf16Chars = Array(char.utf16)
            var cgGlyph = CGGlyph()
            let hasGlyph = CTFontGetGlyphsForCharacters(ctFont, utf16Chars, &cgGlyph, utf16Chars.count)
            
            guard hasGlyph else {
                continue
            }
            
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &cgGlyph, &advance, 1)
            
            var boundingRect = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(ctFont, .horizontal, &cgGlyph, &boundingRect, 1)
            
            let glyphSize = SIMD2<Float>(Float(boundingRect.width), Float(boundingRect.height))
            let glyphOffset = SIMD2<Float>(Float(boundingRect.origin.x), Float(boundingRect.origin.y))
            let xAdvance = Float(advance.width)
            
            var uvRect = SIMD4<Float>(0, 0, 0, 0)
            
            if !boundingRect.isEmpty && boundingRect.width > 0 && boundingRect.height > 0 {
                // Render grayscale glyph to temp buffer
                if let grayPixels = renderGlyphGrayscale(
                    ctFont: ctFont,
                    glyph: cgGlyph,
                    boundingRect: boundingRect,
                    cellSize: cellSize
                ) {
                    // Generate SDF representation
                    let sdfPixels = generateSDF(
                        pixelBuffer: grayPixels,
                        cellSize: cellSize,
                        maxRadius: searchRadius
                    )
                    
                    // Copy to texture atlas
                    for y in 0..<cellSize {
                        let srcOffset = y * cellSize
                        let destOffset = (cellY + y) * atlasWidth + cellX
                        
                        // Copy row
                        atlasBytes.withUnsafeMutableBufferPointer { destPtr in
                            sdfPixels.withUnsafeBufferPointer { srcPtr in
                                let destStart = destPtr.baseAddress!.advanced(by: destOffset)
                                let srcStart = srcPtr.baseAddress!.advanced(by: srcOffset)
                                destStart.initialize(from: srcStart, count: cellSize)
                            }
                        }
                    }
                    
                    // Compute UV coordinates in texture space (mapping to the exact glyph boundary)
                    let uvX = (Float(cellX) + (Float(cellSize) - Float(boundingRect.width)) / 2.0) / Float(atlasWidth)
                    let uvY = (Float(cellY) + (Float(cellSize) - Float(boundingRect.height)) / 2.0) / Float(atlasHeight)
                    let uvWidth = Float(boundingRect.width) / Float(atlasWidth)
                    let uvHeight = Float(boundingRect.height) / Float(atlasHeight)
                    uvRect = SIMD4<Float>(uvX, uvY, uvWidth, uvHeight)
                }
            } else {
                // Empty/whitespace glyph: just use a portion of the atlas mapped to cell bounds
                let uvX = Float(cellX) / Float(atlasWidth)
                let uvY = Float(cellY) / Float(atlasHeight)
                let uvWidth = Float(cellSize) / Float(atlasWidth)
                let uvHeight = Float(cellSize) / Float(atlasHeight)
                uvRect = SIMD4<Float>(uvX, uvY, uvWidth, uvHeight)
            }
            
            glyphs[char] = Glyph(
                char: char,
                uvRect: uvRect,
                size: glyphSize,
                offset: glyphOffset,
                xAdvance: xAdvance
            )
        }
        
        // 2. Create Metal texture
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: atlasWidth,
            height: atlasHeight,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]
        
        #if os(macOS)
        let hasUnified = device.hasUnifiedMemory
        textureDescriptor.storageMode = hasUnified ? .shared : .managed
        #else
        textureDescriptor.storageMode = .shared
        #endif
        
        guard let mtlTexture = device.makeTexture(descriptor: textureDescriptor) else {
            throw SDFFontAtlasGeneratorError.textureCreationFailed
        }
        
        mtlTexture.replace(
            region: MTLRegionMake2D(0, 0, atlasWidth, atlasHeight),
            mipmapLevel: 0,
            withBytes: atlasBytes,
            bytesPerRow: atlasWidth
        )
        
        let texture = MetalTexture(mtlTexture: mtlTexture)
        return FontAtlas(
            texture: texture,
            glyphs: glyphs,
            fontSize: fontSize,
            lineHeight: lineHeight
        )
    }
    
    /// Renders a single glyph in a centered cell to a grayscale pixel buffer.
    private static func renderGlyphGrayscale(
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
        
        // Clear background to black (0)
        context.setFillColor(gray: 0.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: cellSize, height: cellSize))
        
        // Center the glyph's bounding box in the cell
        let drawX = CGFloat(cellSize) / 2.0 - boundingRect.origin.x - boundingRect.width / 2.0
        let drawY = CGFloat(cellSize) / 2.0 - boundingRect.origin.y - boundingRect.height / 2.0
        
        context.textMatrix = .identity
        context.setFillColor(gray: 1.0, alpha: 1.0)
        
        var mutableGlyph = glyph
        var glyphPosition = CGPoint(x: drawX, y: drawY)
        CTFontDrawGlyphs(ctFont, &mutableGlyph, &glyphPosition, 1, context)
        
        return pixelBuffer
    }
    
    /// Generates a signed distance field (SDF) from a grayscale pixel buffer.
    private static func generateSDF(
        pixelBuffer: [UInt8],
        cellSize: Int,
        maxRadius: Float
    ) -> [UInt8] {
        var sdfBuffer = [UInt8](repeating: 0, count: cellSize * cellSize)
        
        // Precompute inside/outside grid to speed up lookups
        var isInsideGrid = [Bool](repeating: false, count: cellSize * cellSize)
        for i in 0..<(cellSize * cellSize) {
            isInsideGrid[i] = pixelBuffer[i] > 127
        }
        
        let maxRadiusSq = maxRadius * maxRadius
        
        for y in 0..<cellSize {
            let startY = max(0, y - Int(maxRadius))
            let endY = min(cellSize - 1, y + Int(maxRadius))
            
            for x in 0..<cellSize {
                let idx = y * cellSize + x
                let isInside = isInsideGrid[idx]
                
                var minDistSq = maxRadiusSq
                
                let startX = max(0, x - Int(maxRadius))
                let endX = min(cellSize - 1, x + Int(maxRadius))
                
                for ny in startY...endY {
                    let dy = Float(ny - y)
                    let dySq = dy * dy
                    if dySq >= minDistSq { continue }
                    
                    let rowOffset = ny * cellSize
                    for nx in startX...endX {
                        if isInsideGrid[rowOffset + nx] != isInside {
                            let dx = Float(nx - x)
                            let distSq = dx * dx + dySq
                            if distSq < minDistSq {
                                minDistSq = distSq
                            }
                        }
                    }
                }
                
                let dist = sqrt(minDistSq)
                let signedDist = isInside ? dist : -dist
                
                // Map to [0, 255] where 0 is -maxRadius, 255 is +maxRadius, and 128 is 0.
                let normalized = signedDist / maxRadius
                let byteValue = UInt8(clamp(round((normalized + 1.0) * 127.5), 0.0, 255.0))
                sdfBuffer[idx] = byteValue
            }
        }
        
        return sdfBuffer
    }
    
    @inline(__always)
    private static func clamp<T: Comparable>(_ value: T, _ minValue: T, _ maxValue: T) -> T {
        return min(max(value, minValue), maxValue)
    }
}
