import Foundation

/// A component that tracks a particle's age and lifetime.
public struct ParticleComponent: Component {
    /// The maximum age of the particle in seconds.
    public var lifetime: Double
    
    /// The current age of the particle in seconds.
    public var age: Double = 0.0
    
    public init(lifetime: Double, age: Double = 0.0) {
        self.lifetime = lifetime
        self.age = age
    }
}
