import Foundation
import simd

/// A component that renders a single sprite from a SpriteSheet.
public struct SpriteComponent: Component {
    /// The sprite sheet containing the sprite.
    public var spriteSheet: SpriteSheet
    
    /// The name of the frame to render.
    public var frameName: String
    
    /// An optional color tint.
    public var color: SIMD4<Float>
    
    /// The internally cached mesh for this sprite.
    public var mesh: (any Mesh)?
    
    /// A flag indicating whether the mesh needs to be rebuilt.
    public var isDirty: Bool = true
    
    /// Initializes a new SpriteComponent.
    /// - Parameters:
    ///   - spriteSheet: The sprite sheet.
    ///   - frameName: The name of the frame to render.
    ///   - color: An optional color tint, defaulting to white.
    public init(spriteSheet: SpriteSheet, frameName: String, color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)) {
        self.spriteSheet = spriteSheet
        self.frameName = frameName
        self.color = color
    }
}
