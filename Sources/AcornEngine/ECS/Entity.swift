/// An identifier representing a unique object in the engine's entity component system.
public struct Entity: Hashable, Sendable {
    /// The unique identifier of the entity.
    public let id: UInt64
    
    /// Creates a new entity with the given identifier.
    /// - Parameter id: The unique identifier.
    public init(id: UInt64) {
        self.id = id
    }
}
