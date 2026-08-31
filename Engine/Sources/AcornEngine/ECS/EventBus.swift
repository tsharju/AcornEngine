import Foundation

/// A token representing an active event subscription.
@MainActor
public final class EventSubscription: Identifiable {
    public let id: UInt64
    private var cancelAction: (@MainActor () -> Void)?
    
    internal init(id: UInt64, cancelAction: @escaping @MainActor () -> Void) {
        self.id = id
        self.cancelAction = cancelAction
    }
    
    /// Cancels the subscription so no further events are received.
    public func cancel() {
        cancelAction?()
        cancelAction = nil
    }
    
    deinit {
        // MainActor deinit handling if needed; cancelAction is cleared on explicit cancel
    }
}

/// An internal type-erased interface for clearing typed frame event lists.
@MainActor
private protocol AnyEventList: AnyObject {
    func clear()
}

/// A strongly-typed list for frame-buffered events of type `T`.
/// Eliminates existential boxing and per-query dynamic downcasting.
@MainActor
private final class TypedEventList<T: Event>: AnyEventList {
    var items: [T] = []
    
    func clear() {
        items.removeAll(keepingCapacity: true)
    }
}

/// A central decoupled event bus and frame-buffered message stream for ECS systems.
@MainActor
public final class EventBus {
    private var nextSubscriptionID: UInt64 = 0
    private var subscribers: [ObjectIdentifier: [UInt64: @MainActor (any Event) -> Void]] = [:]
    private var frameEventLists: [ObjectIdentifier: any AnyEventList] = [:]
    
    /// Initializes an empty event bus.
    public init() {}
    
    /// Subscribes to events of a specific type.
    /// - Parameters:
    ///   - eventType: The type of event to subscribe to.
    ///   - handler: The closure invoked whenever an event of this type is published.
    /// - Returns: A subscription token that can be cancelled.
    @discardableResult
    public func subscribe<T: Event>(
        _ eventType: T.Type = T.self,
        handler: @escaping @MainActor (T) -> Void
    ) -> EventSubscription {
        let key = ObjectIdentifier(T.self)
        let id = nextSubscriptionID
        nextSubscriptionID += 1
        
        let wrapper: @MainActor (any Event) -> Void = { event in
            if let typed = event as? T {
                handler(typed)
            }
        }
        
        if subscribers[key] == nil {
            subscribers[key] = [:]
        }
        subscribers[key]?[id] = wrapper
        
        return EventSubscription(id: id) { [weak self] in
            self?.subscribers[key]?[id] = nil
        }
    }
    
    /// Publishes an event to all active subscribers and buffers it in the current frame stream.
    /// - Parameter event: The event to publish.
    public func publish<T: Event>(_ event: T) {
        let key = ObjectIdentifier(T.self)
        
        // Buffer into typed current frame events
        if let list = frameEventLists[key] as? TypedEventList<T> {
            list.items.append(event)
        } else {
            let list = TypedEventList<T>()
            list.items.append(event)
            frameEventLists[key] = list
        }
        
        // Notify immediate subscribers
        if let handlers = subscribers[key] {
            for handler in handlers.values {
                handler(event)
            }
        }
    }
    
    /// Retrieves all buffered events of the specified type published during the current frame.
    /// - Parameter type: The type of event to query.
    /// - Returns: An array of events of the given type.
    public func events<T: Event>(ofType type: T.Type = T.self) -> [T] {
        let key = ObjectIdentifier(T.self)
        guard let list = frameEventLists[key] as? TypedEventList<T> else { return [] }
        return list.items
    }
    
    /// Returns a boolean value indicating whether any events of the specified type were published in the current frame.
    /// - Parameter type: The type of event to check.
    /// - Returns: `true` if at least one event of the specified type is present, otherwise `false`.
    public func hasEvents<T: Event>(ofType type: T.Type = T.self) -> Bool {
        let key = ObjectIdentifier(T.self)
        guard let list = frameEventLists[key] as? TypedEventList<T> else { return false }
        return !list.items.isEmpty
    }
    
    /// Clears all buffered frame events. Called automatically at the end of each frame or tick.
    public func clear() {
        for list in frameEventLists.values {
            list.clear()
        }
    }
    
    /// Removes all subscribers and clears all buffered events.
    public func reset() {
        subscribers.removeAll()
        frameEventLists.removeAll()
    }
}
