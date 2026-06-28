import Foundation
import simd

/// A utility for generating vertex data for text rendering from a string and a `FontAtlas`.
public enum TextMeshGenerator {
    /// Generates the list of vertices representing quads for the given text string.
    /// - Parameters:
    ///   - text: The string to generate mesh data for.
    ///   - atlas: The font atlas to use.
    ///   - color: The base color of the vertices (default is white).
    /// - Returns: An array of `Vertex` structures ready for rendering.
    public static func generateVertices(
        for text: String,
        in atlas: FontAtlas,
        color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    ) -> [Vertex] {
        var vertices: [Vertex] = []
        var penX: Float = 0.0
        var penY: Float = 0.0
        
        for char in text {
            if char == "\n" {
                penX = 0.0
                penY -= atlas.lineHeight
                continue
            }
            
            guard let glyph = atlas.glyphs[char] else {
                // If character is missing (like space or tab), advance penX by basic width
                if char == " " {
                    // Fallback to space advance if space glyph is missing, otherwise use space advance
                    if let spaceGlyph = atlas.glyphs[" "] {
                        penX += spaceGlyph.xAdvance
                    } else {
                        penX += atlas.fontSize * 0.25
                    }
                } else if char == "\t" {
                    if let spaceGlyph = atlas.glyphs[" "] {
                        penX += spaceGlyph.xAdvance * 4
                    } else {
                        penX += atlas.fontSize * 1.0
                    }
                }
                continue
            }
            
            // Calculate quad corners
            let x0 = penX + glyph.offset.x
            let y0 = penY + glyph.offset.y - glyph.size.y // Bottom
            let x1 = x0 + glyph.size.x
            let y1 = penY + glyph.offset.y // Top
            
            // Texture coordinates (UVs)
            let u0 = glyph.uvRect.x
            let v0 = glyph.uvRect.y
            let u1 = glyph.uvRect.x + glyph.uvRect.z
            let v1 = glyph.uvRect.y + glyph.uvRect.w
            
            // Generate two triangles (6 vertices) per quad
            // Triangle 1: Bottom-Left, Top-Left, Top-Right
            let vBL = Vertex(position: SIMD3<Float>(x0, y0, 0), color: color, texCoord: SIMD2<Float>(u0, v1))
            let vTL = Vertex(position: SIMD3<Float>(x0, y1, 0), color: color, texCoord: SIMD2<Float>(u0, v0))
            let vTR = Vertex(position: SIMD3<Float>(x1, y1, 0), color: color, texCoord: SIMD2<Float>(u1, v0))
            
            // Triangle 2: Bottom-Left, Top-Right, Bottom-Right
            let vBR = Vertex(position: SIMD3<Float>(x1, y0, 0), color: color, texCoord: SIMD2<Float>(u1, v1))
            
            vertices.append(vBL)
            vertices.append(vTL)
            vertices.append(vTR)
            
            vertices.append(vBL)
            vertices.append(vTR)
            vertices.append(vBR)
            
            // Advance pen position
            penX += glyph.xAdvance
        }
        
        return vertices
    }
}
