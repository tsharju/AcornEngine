import Foundation

/// A component that defines a parent-child relationship between entities.
public struct ParentComponent: Component {
    /// The parent entity.
    public let parent: Entity
    
    /// Initializes a new parent component.
    /// - Parameter parent: The parent entity.
    public init(parent: Entity) {
        self.parent = parent
    }
}
