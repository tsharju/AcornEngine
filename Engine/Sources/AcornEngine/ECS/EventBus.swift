import Foundation

/// A token representing an active event subscription.
@MainActor
public final class EventSubscription: Identifiable {
    public let id: UUID
    private var cancelAction: (@MainActor () -> Void)?
    
    internal init(id: UUID = UUID(), cancelAction: @escaping @MainActor () -> Void) {
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

/// A central decoupled event bus and frame-buffered message stream for ECS systems.
@MainActor
public final class EventBus {
    private var subscribers: [ObjectIdentifier: [UUID: @MainActor (any Event) -> Void]] = [:]
    private var frameEvents: [ObjectIdentifier: [any Event]] = [:]
    
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
        let id = UUID()
        
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
        
        // Buffer into current frame events
        if frameEvents[key] == nil {
            frameEvents[key] = []
        }
        frameEvents[key]?.append(event)
        
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
        guard let list = frameEvents[key] else { return [] }
        return list.compactMap { $0 as? T }
    }
    
    /// Returns a boolean value indicating whether any events of the specified type were published in the current frame.
    /// - Parameter type: The type of event to check.
    /// - Returns: `true` if at least one event of the specified type is present, otherwise `false`.
    public func hasEvents<T: Event>(ofType type: T.Type = T.self) -> Bool {
        let key = ObjectIdentifier(T.self)
        guard let list = frameEvents[key] else { return false }
        return !list.isEmpty
    }
    
    /// Clears all buffered frame events. Called automatically at the end of each frame or tick.
    public func clear() {
        frameEvents.removeAll(keepingCapacity: true)
    }
    
    /// Removes all subscribers and clears all buffered events.
    public func reset() {
        subscribers.removeAll()
        frameEvents.removeAll()
    }
}
