/// An identifier representing a unique object in the engine's entity component system.
/// Uses a 32-bit slot index and a 32-bit generation counter to prevent the ABA stale-reference hazard.
public struct Entity: Hashable, Sendable, Identifiable {
    /// The slot index of the entity in the world's entity storage.
    public let index: UInt32
    
    /// The generational version of this entity slot, incremented whenever an entity is destroyed.
    public let generation: UInt32
    
    /// The combined 64-bit unique identifier of the entity.
    public var id: UInt64 {
        (UInt64(generation) << 32) | UInt64(index)
    }
    
    /// Creates a new entity with a slot index and generation counter.
    /// - Parameters:
    ///   - index: The slot index.
    ///   - generation: The generation counter (defaults to 1).
    public init(index: UInt32, generation: UInt32 = 1) {
        self.index = index
        self.generation = generation
    }
    
    /// Creates an entity from a 64-bit combined identifier.
    /// - Parameter id: The combined identifier.
    public init(id: UInt64) {
        self.index = UInt32(id & 0xFFFF_FFFF)
        let gen = UInt32((id >> 32) & 0xFFFF_FFFF)
        self.generation = gen == 0 ? 1 : gen
    }
}
