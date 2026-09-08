import Foundation

/// ECS component that identifies an entity as containing road network geometry rendered with line width and outline.
public struct RoadComponent: Component, Sendable {
    /// The GPU road mesh containing line segment ribbons.
    public var mesh: any Mesh
    
    /// Global outline color tint applied to this road mesh.
    public var outlineColor: SIMD4<Float>
    
    /// Outline width ratio (e.g. 0.18 for 18% border width).
    public var outlineWidth: Float
    
    /// Global width scale multiplier for the road.
    public var widthScale: Float
    
    /// Initializes a new road component.
    /// - Parameters:
    ///   - mesh: The road mesh.
    ///   - outlineColor: Outline color (defaults to dark charcoal/slate).
    ///   - outlineWidth: Outline width fraction (defaults to 0.18).
    ///   - widthScale: Global width scale multiplier (defaults to 1.0).
    public init(
        mesh: any Mesh,
        outlineColor: SIMD4<Float> = SIMD4<Float>(0.45, 0.45, 0.48, 1.0),
        outlineWidth: Float = 0.18,
        widthScale: Float = 1.0
    ) {
        self.mesh = mesh
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
        self.widthScale = widthScale
    }
}
