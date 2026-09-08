import Foundation
import AcornMath

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(CoreText)
import CoreText
#endif

#if canImport(Metal)
import Metal
#endif

/// Errors that can occur during SDF Font Atlas generation.
public enum SDFFontAtlasGeneratorError: Error, Equatable {
    /// Failed to create the texture resource on the renderer/device.
    case textureCreationFailed
    /// A font rasterizer is required on this platform.
    case rasterizerRequired
    /// Cell size must be greater than zero.
    case invalidCellSize
    /// Font size must be greater than zero.
    case invalidFontSize
}

/// A generator that dynamically builds a signed distance field (SDF) font atlas.
public struct SDFFontAtlasGenerator {
    
    private static func nextPowerOfTwo(_ value: Int) -> Int {
        guard value > 0 else { return 1 }
        var v = value - 1
        v |= v >> 1
        v |= v >> 2
        v |= v >> 4
        v |= v >> 8
        v |= v >> 16
        return max(1, v + 1)
    }

    /// Internal helper that rasterizes glyphs, calculates signed distance fields, and packs cells into an atlas buffer.
    private static func buildAtlasData(
        fontName: String,
        fontSize: Float,
        characters: Set<Character>,
        rasterizer: any FontRasterizer,
        cellSize: Int,
        searchRadius: Float
    ) throws -> (glyphs: [Character: Glyph], atlasBytes: [UInt8], width: Int, height: Int, lineHeight: Float) {
        guard cellSize > 0 else {
            throw SDFFontAtlasGeneratorError.invalidCellSize
        }
        guard fontSize > 0 else {
            throw SDFFontAtlasGeneratorError.invalidFontSize
        }
        
        let (metrics, rasterizedGlyphs) = try rasterizer.rasterize(
            fontName: fontName,
            fontSize: fontSize,
            characters: characters,
            cellSize: cellSize
        )
        let lineHeight = metrics.lineHeight
        let sortedChars = characters.sorted()
        let numGlyphs = sortedChars.count
        
        // 1. Pack cells into a square texture atlas (power-of-two), ensuring atlas dimensions >= cellSize
        let minDimension = max(512, nextPowerOfTwo(cellSize))
        var atlasWidth = minDimension
        var atlasHeight = minDimension
        while true {
            let cellsPerRow = max(1, atlasWidth / cellSize)
            let numRows = (numGlyphs + cellsPerRow - 1) / cellsPerRow
            if numRows * cellSize <= atlasHeight {
                break
            }
            atlasWidth *= 2
            atlasHeight *= 2
        }
        
        let cellsPerRow = max(1, atlasWidth / cellSize)
        var atlasBytes = [UInt8](repeating: 0, count: atlasWidth * atlasHeight)
        var glyphs = [Character: Glyph]()
        
        for (index, char) in sortedChars.enumerated() {
            guard let rGlyph = rasterizedGlyphs[char] else { continue }
            let row = index / cellsPerRow
            let col = index % cellsPerRow
            let cellX = col * cellSize
            let cellY = row * cellSize
            
            var uvRect = SIMD4<Float>(0, 0, 0, 0)
            let bWidth = rGlyph.boundingRect.z
            let bHeight = rGlyph.boundingRect.w
            
            if let grayPixels = rGlyph.grayscalePixels, bWidth > 0 && bHeight > 0 {
                let sdfPixels = generateSDF(
                    pixelBuffer: grayPixels,
                    cellSize: cellSize,
                    maxRadius: searchRadius
                )
                
                // Copy to texture atlas
                for y in 0..<cellSize {
                    let srcOffset = y * cellSize
                    let destOffset = (cellY + y) * atlasWidth + cellX
                    
                    atlasBytes.withUnsafeMutableBufferPointer { destPtr in
                        sdfPixels.withUnsafeBufferPointer { srcPtr in
                            let destStart = destPtr.baseAddress!.advanced(by: destOffset)
                            let srcStart = srcPtr.baseAddress!.advanced(by: srcOffset)
                            destStart.initialize(from: srcStart, count: cellSize)
                        }
                    }
                }
                
                let uvX = Float(cellX) / Float(atlasWidth)
                let uvY = Float(cellY) / Float(atlasHeight)
                let uvWidth = Float(cellSize) / Float(atlasWidth)
                let uvHeight = Float(cellSize) / Float(atlasHeight)
                uvRect = SIMD4<Float>(uvX, uvY, uvWidth, uvHeight)
            } else {
                let uvX = Float(cellX) / Float(atlasWidth)
                let uvY = Float(cellY) / Float(atlasHeight)
                let uvWidth = Float(cellSize) / Float(atlasWidth)
                let uvHeight = Float(cellSize) / Float(atlasHeight)
                uvRect = SIMD4<Float>(uvX, uvY, uvWidth, uvHeight)
            }
            
            glyphs[char] = Glyph(
                char: char,
                uvRect: uvRect,
                size: rGlyph.size,
                offset: rGlyph.offset,
                xAdvance: rGlyph.xAdvance
            )
        }
        
        return (glyphs: glyphs, atlasBytes: atlasBytes, width: atlasWidth, height: atlasHeight, lineHeight: lineHeight)
    }
    
    /// Generates a `FontAtlas` dynamically for a given font and set of characters using an abstract `Renderer`.
    /// - Parameters:
    ///   - fontName: The PostScript or family name of the font (e.g., "Helvetica", "Courier").
    ///   - fontSize: The size of the font in points.
    ///   - characters: The set of characters to generate glyphs for.
    ///   - renderer: The renderer backend used to create the texture.
    ///   - rasterizer: Optional font rasterizer (defaults to `CoreTextFontRasterizer` on Apple platforms).
    ///   - cellSize: The width and height of each glyph's cell in pixels. Defaults to 64.
    ///   - searchRadius: The distance radius in pixels to search for boundaries during SDF calculation. Defaults to 8.0.
    /// - Returns: A fully generated `FontAtlas`.
    /// - Throws: `SDFFontAtlasGeneratorError` if texture creation fails or no rasterizer is available.
    public static func generate(
        fontName: String,
        fontSize: Float,
        characters: Set<Character> = Set((32...126).map { Character(UnicodeScalar($0)!) }),
        renderer: any Renderer,
        rasterizer: (any FontRasterizer)? = nil,
        cellSize: Int = 64,
        searchRadius: Float = 8.0
    ) throws -> FontAtlas {
        #if canImport(CoreText) && canImport(CoreGraphics)
        let effectiveRasterizer: any FontRasterizer = rasterizer ?? CoreTextFontRasterizer()
        #else
        guard let effectiveRasterizer = rasterizer else {
            throw SDFFontAtlasGeneratorError.rasterizerRequired
        }
        #endif
        
        let data = try buildAtlasData(
            fontName: fontName,
            fontSize: fontSize,
            characters: characters,
            rasterizer: effectiveRasterizer,
            cellSize: cellSize,
            searchRadius: searchRadius
        )
        
        guard let texture = renderer.createTexture(
            width: data.width,
            height: data.height,
            pixelData: data.atlasBytes,
            format: .r8Unorm
        ) else {
            throw SDFFontAtlasGeneratorError.textureCreationFailed
        }
        
        return FontAtlas(
            texture: texture,
            glyphs: data.glyphs,
            fontSize: fontSize,
            lineHeight: data.lineHeight
        )
    }

    #if canImport(Metal)
    /// Generates a `FontAtlas` dynamically for a given font and set of characters using an Apple Metal device.
    /// Backward-compatible overload for Metal-only callers.
    public static func generate(
        fontName: String,
        fontSize: Float,
        characters: Set<Character> = Set((32...126).map { Character(UnicodeScalar($0)!) }),
        device: any MTLDevice,
        cellSize: Int = 64,
        searchRadius: Float = 8.0
    ) throws -> FontAtlas {
        #if canImport(CoreText) && canImport(CoreGraphics)
        let rasterizer = CoreTextFontRasterizer()
        let data = try buildAtlasData(
            fontName: fontName,
            fontSize: fontSize,
            characters: characters,
            rasterizer: rasterizer,
            cellSize: cellSize,
            searchRadius: searchRadius
        )
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: data.width,
            height: data.height,
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
            region: MTLRegionMake2D(0, 0, data.width, data.height),
            mipmapLevel: 0,
            withBytes: data.atlasBytes,
            bytesPerRow: data.width
        )
        
        let texture = MetalTexture(texture: mtlTexture)
        return FontAtlas(
            texture: texture,
            glyphs: data.glyphs,
            fontSize: fontSize,
            lineHeight: data.lineHeight
        )
        #else
        throw SDFFontAtlasGeneratorError.rasterizerRequired
        #endif
    }
    #endif
    
    /// Generates a signed distance field (SDF) from a grayscale pixel buffer.
    public static func generateSDF(
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
