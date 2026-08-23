import Foundation
import simd

/// Represents the lifecycle phase of a touch point.
public enum TouchPhase: Sendable, Hashable {
    /// A touch point has just contacted the screen.
    case began
    
    /// A touch point has moved across the screen.
    case moved
    
    /// A touch point is held in place without moving.
    case stationary
    
    /// A touch point has lifted off the screen.
    case ended
    
    /// A touch point was interrupted or cancelled by the system.
    case cancelled
}

/// Represents a single pointer touch input.
public struct Touch: Sendable, Hashable, Identifiable {
    /// Unique touch pointer identifier.
    public let id: Int
    
    /// The current position of the touch in screen/viewport coordinate space.
    public var position: SIMD2<Float>
    
    /// The change in position since the last frame.
    public var delta: SIMD2<Float>
    
    /// The current phase of the touch.
    public var phase: TouchPhase
    
    /// The number of consecutive taps recorded at this touch point.
    public var tapCount: Int
    
    /// The timestamp when the touch event occurred.
    public var timestamp: TimeInterval
    
    /// Initializes a new Touch instance.
    /// - Parameters:
    ///   - id: Unique touch identifier.
    ///   - position: Current position in screen space.
    ///   - delta: Movement delta since previous frame.
    ///   - phase: Current phase of the touch.
    ///   - tapCount: Number of consecutive taps.
    ///   - timestamp: Event timestamp.
    public init(
        id: Int,
        position: SIMD2<Float>,
        delta: SIMD2<Float> = .zero,
        phase: TouchPhase = .began,
        tapCount: Int = 1,
        timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        self.id = id
        self.position = position
        self.delta = delta
        self.phase = phase
        self.tapCount = tapCount
        self.timestamp = timestamp
    }
}
