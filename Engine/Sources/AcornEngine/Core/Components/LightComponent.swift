import Foundation
import simd

/// The type of light source.
public enum LightType: Sendable {
    /// Ambient light affects all objects equally regardless of position or orientation.
    case ambient
    /// Directional light simulates a distant light source (like the sun) with parallel rays.
    case directional
    /// Point light emits light in all directions from a specific position.
    case point
}

/// A component that defines a light source.
public struct LightComponent: Component {
    /// The type of the light.
    public var type: LightType
    
    /// The color of the light (RGB).
    public var color: SIMD3<Float>
    
    /// The intensity of the light.
    public var intensity: Float
    
    /// Initializes a new light component.
    /// - Parameters:
    ///   - type: The type of light.
    ///   - color: The color of the light (RGB). Defaults to white (1, 1, 1).
    ///   - intensity: The intensity of the light. Defaults to 1.0.
    public init(type: LightType, color: SIMD3<Float> = .init(1, 1, 1), intensity: Float = 1.0) {
        self.type = type
        self.color = color
        self.intensity = intensity
    }
}
