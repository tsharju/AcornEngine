/// A protocol representing a system that acts upon entities and their components.
@MainActor
public protocol System {
    /// Updates the system's state.
    /// - Parameters:
    ///   - world: The world this system operates on.
    ///   - deltaTime: The time elapsed since the last update.
    func update(world: World, deltaTime: Double)
}
