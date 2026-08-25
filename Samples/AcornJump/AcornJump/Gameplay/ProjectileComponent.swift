import Foundation
import simd
import AcornEngine

/// ECS Component for flying acorn seed bullets.
public struct ProjectileComponent: Component {
    public var velocity: SIMD2<Float>
    public var lifetime: Float
    public var radius: Float
    
    public init(
        velocity: SIMD2<Float> = SIMD2<Float>(0.0, 18.0),
        lifetime: Float = 2.0,
        radius: Float = 0.25
    ) {
        self.velocity = velocity
        self.lifetime = lifetime
        self.radius = radius
    }
}
