import Testing
import Metal
import Foundation
@testable import AcornEngine

struct FontAtlasTests {
    
    @Test("Font Atlas Generation - Success")
    func fontAtlasGeneration() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            // No Metal device available (e.g., in some CI/headless environments), skip gracefully
            return
        }
        
        let fontSize: Float = 32.0
        let atlas = try SDFFontAtlasGenerator.generate(
            fontName: "Helvetica",
            fontSize: fontSize,
            device: device
        )
        
        // Assertions on font metrics
        #expect(atlas.fontSize == fontSize)
        #expect(atlas.lineHeight > 0)
        
        // Assertions on texture
        #expect(atlas.texture.width >= 512)
        #expect(atlas.texture.height >= 512)
        #expect(atlas.texture as? MetalTexture != nil)
        
        // Check standard printable characters
        let asciiRange = 32...126
        #expect(atlas.glyphs.count >= asciiRange.count)
        
        // Test a specific character (e.g. 'A')
        let charA: Character = "A"
        let glyphA = try #require(atlas.glyphs[charA])
        #expect(glyphA.char == charA)
        #expect(glyphA.size.x > 0)
        #expect(glyphA.size.y > 0)
        #expect(glyphA.xAdvance > 0)
        
        // Check UV rect (should be within [0, 1])
        #expect(glyphA.uvRect.x >= 0.0 && glyphA.uvRect.x <= 1.0)
        #expect(glyphA.uvRect.y >= 0.0 && glyphA.uvRect.y <= 1.0)
        #expect(glyphA.uvRect.z > 0.0 && glyphA.uvRect.z <= 1.0)
        #expect(glyphA.uvRect.w > 0.0 && glyphA.uvRect.w <= 1.0)
        
        // Check whitespace character (e.g., ' ')
        let charSpace: Character = " "
        let glyphSpace = try #require(atlas.glyphs[charSpace])
        #expect(glyphSpace.char == charSpace)
        #expect(glyphSpace.xAdvance > 0)
    }
}
