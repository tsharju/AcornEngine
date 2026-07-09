import Foundation
import simd

/// Utility for generating meshes for sprites and tile maps.
public enum SpriteMeshGenerator {
    
    /// Generates vertices for a single sprite.
    /// - Parameters:
    ///   - spriteSheet: The sprite sheet containing the sprite.
    ///   - frameName: The name of the frame to render.
    ///   - color: The color tint.
    /// - Returns: An array of vertices, or empty if the frame is not found.
    public static func generateVertices(for frameName: String, in spriteSheet: SpriteSheet, color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)) -> [Vertex] {
        guard let frame = spriteSheet.frame(named: frameName) else { return [] }
        
        let uv = spriteSheet.uvRect(for: frame)
        let uvMin = uv.origin
        let uvMax = uv.origin + uv.size
        
        // Let's create a quad centered at origin, or top-left. Let's make it centered for easier transform.
        // Or size it relative to its pixel size.
        // 1 pixel = 1 world unit? Let's use world units based on pixel size.
        let halfWidth = Float(frame.sourceSize.w) * 0.5
        let halfHeight = Float(frame.sourceSize.h) * 0.5
        
        // Texture packer frames can be trimmed. 
        // We need to offset the geometry by the trim offset (spriteSourceSize).
        // spriteSourceSize.x, y is the top-left offset in the original image.
        // Assuming origin is center of the sourceSize.
        let offsetX = Float(frame.spriteSourceSize.x) - halfWidth + Float(frame.spriteSourceSize.w) * 0.5
        let offsetY = halfHeight - Float(frame.spriteSourceSize.y) - Float(frame.spriteSourceSize.h) * 0.5
        
        let quadHalfWidth = Float(frame.spriteSourceSize.w) * 0.5
        let quadHalfHeight = Float(frame.spriteSourceSize.h) * 0.5
        
        let minX = offsetX - quadHalfWidth
        let maxX = offsetX + quadHalfWidth
        let minY = offsetY - quadHalfHeight
        let maxY = offsetY + quadHalfHeight
        
        let v0 = Vertex(position: SIMD3<Float>(minX, minY, 0), color: color, texCoord: SIMD2<Float>(uvMin.x, uvMax.y))
        let v1 = Vertex(position: SIMD3<Float>(maxX, minY, 0), color: color, texCoord: SIMD2<Float>(uvMax.x, uvMax.y))
        let v2 = Vertex(position: SIMD3<Float>(minX, maxY, 0), color: color, texCoord: SIMD2<Float>(uvMin.x, uvMin.y))
        let v3 = Vertex(position: SIMD3<Float>(maxX, maxY, 0), color: color, texCoord: SIMD2<Float>(uvMax.x, uvMin.y))
        
        return [v0, v1, v2, v2, v1, v3]
    }
    
    /// Generates vertices for an entire tile map.
    /// - Parameters:
    ///   - component: The tile map component.
    /// - Returns: An array of vertices.
    public static func generateVertices(for component: TileMapComponent) -> [Vertex] {
        var vertices: [Vertex] = []
        let sheet = component.spriteSheet
        let tw = component.tileSize.x
        let th = component.tileSize.y
        let color = component.color
        
        // Generate tiles relative to the bottom-left or center.
        // Let's make the center of the tile map the origin.
        let mapWidth = Float(component.columns) * tw
        let mapHeight = Float(component.rows) * th
        let offsetX = -mapWidth * 0.5
        let offsetY = -mapHeight * 0.5
        
        for row in 0..<component.rows {
            for col in 0..<component.columns {
                let index = row * component.columns + col
                let frameName = component.tiles[index]
                if frameName.isEmpty { continue }
                
                guard let frame = sheet.frame(named: frameName) else { continue }
                
                let uv = sheet.uvRect(for: frame)
                let uvMin = uv.origin
                let uvMax = uv.origin + uv.size
                
                // Position of the bottom-left of the tile
                // We assume row 0 is top or bottom? Let's assume row 0 is bottom.
                // Wait, typically in arrays, row 0 is top. Let's make row 0 top.
                let x = offsetX + Float(col) * tw
                let y = offsetY + mapHeight - Float(row + 1) * th
                
                let minX = x
                let maxX = x + tw
                let minY = y
                let maxY = y + th
                
                let v0 = Vertex(position: SIMD3<Float>(minX, minY, 0), color: color, texCoord: SIMD2<Float>(uvMin.x, uvMax.y))
                let v1 = Vertex(position: SIMD3<Float>(maxX, minY, 0), color: color, texCoord: SIMD2<Float>(uvMax.x, uvMax.y))
                let v2 = Vertex(position: SIMD3<Float>(minX, maxY, 0), color: color, texCoord: SIMD2<Float>(uvMin.x, uvMin.y))
                let v3 = Vertex(position: SIMD3<Float>(maxX, maxY, 0), color: color, texCoord: SIMD2<Float>(uvMax.x, uvMin.y))
                
                vertices.append(contentsOf: [v0, v1, v2, v2, v1, v3])
            }
        }
        
        return vertices
    }
}
