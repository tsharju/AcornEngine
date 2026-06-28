import Foundation
import simd

/// A component that stores parameters and state for rendering SDF text.
public struct TextComponent: Component {
    /// The text string to render.
    public var text: String {
        didSet {
            if oldValue != text {
                isDirty = true
            }
        }
    }
    
    /// The font atlas containing the glyph metric and texture data.
    public var fontAtlas: FontAtlas {
        didSet {
            isDirty = true
        }
    }
    
    /// The primary color of the text.
    public var textColor: SIMD4<Float> {
        didSet {
            if oldValue != textColor {
                isDirty = true
            }
        }
    }
    
    /// The color of the text outline.
    public var outlineColor: SIMD4<Float>
    
    /// The width of the outline (0.0 to 0.5).
    public var outlineWidth: Float
    
    /// The edge smoothing factor for anti-aliasing.
    public var edgeWidth: Float
    
    /// Cached mesh resource on the GPU.
    public var mesh: (any Mesh)?
    
    /// Flag indicating whether the cached mesh needs regeneration.
    public var isDirty: Bool = true
    
    /// Creates a new text component.
    public init(
        text: String,
        fontAtlas: FontAtlas,
        textColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        outlineColor: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1),
        outlineWidth: Float = 0.0,
        edgeWidth: Float = 0.05
    ) {
        self.text = text
        self.fontAtlas = fontAtlas
        self.textColor = textColor
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
        self.edgeWidth = edgeWidth
    }
}
