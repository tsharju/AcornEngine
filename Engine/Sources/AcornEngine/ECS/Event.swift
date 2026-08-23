import Foundation

/// A marker protocol representing an event that can be published and subscribed to via the `EventBus`.
public protocol Event: Sendable {}

/// An event published when an engine tick begins.
public struct EngineTickEvent: Event {
    /// The delta time in seconds for the current tick.
    public let deltaTime: Double
    
    /// Initializes a new engine tick event.
    /// - Parameter deltaTime: The delta time in seconds.
    public init(deltaTime: Double) {
        self.deltaTime = deltaTime
    }
}
