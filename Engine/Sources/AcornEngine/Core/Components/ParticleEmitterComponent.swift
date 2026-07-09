import Foundation
import simd

/// A component that describes how particles are emitted.
public struct ParticleEmitterComponent: Component {
    /// Whether the emitter is currently active.
    public var isEmitting: Bool
    
    /// The number of particles emitted per second.
    public var emitRate: Double
    
    /// Internal timer tracking emission.
    public var timeSinceLastEmit: Double = 0.0
    
    // MARK: - Particle Template Properties
    
    /// The meshes to randomly pick from for the spawned particles.
    public var meshes: [any Mesh]
    
    /// The possible range of lifetime in seconds for the spawned particles.
    public var lifetime: ClosedRange<Double>
    
    /// The possible range for the initial X linear velocity.
    public var linearVelocityX: ClosedRange<Float>
    
    /// The possible range for the initial Y linear velocity.
    public var linearVelocityY: ClosedRange<Float>
    
    /// The possible range for the initial angular velocity.
    public var angularVelocity: ClosedRange<Float>
    
    /// The possible range for the uniform scale of the particles.
    public var scale: ClosedRange<Float>
    
    public init(
        isEmitting: Bool = true,
        emitRate: Double = 10.0,
        meshes: [any Mesh],
        lifetime: ClosedRange<Double> = 1.0...2.0,
        linearVelocityX: ClosedRange<Float> = -1.0...1.0,
        linearVelocityY: ClosedRange<Float> = -1.0...1.0,
        angularVelocity: ClosedRange<Float> = -3.0...3.0,
        scale: ClosedRange<Float> = 0.05...0.15
    ) {
        self.isEmitting = isEmitting
        self.emitRate = emitRate
        self.meshes = meshes
        self.lifetime = lifetime
        self.linearVelocityX = linearVelocityX
        self.linearVelocityY = linearVelocityY
        self.angularVelocity = angularVelocity
        self.scale = scale
    }
}
