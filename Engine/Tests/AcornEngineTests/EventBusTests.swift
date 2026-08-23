import Testing
import Foundation
@testable import AcornEngine

struct CustomScoreEvent: Event {
    let score: Int
}

struct CustomMessageEvent: Event {
    let message: String
}

@Suite("EventBus Tests")
@MainActor
struct EventBusTests {
    
    @Test("Immediate event subscription and dispatch")
    func testImmediateSubscription() {
        let bus = EventBus()
        var receivedScore: Int?
        
        let subscription = bus.subscribe(CustomScoreEvent.self) { event in
            receivedScore = event.score
        }
        
        bus.publish(CustomScoreEvent(score: 42))
        
        #expect(receivedScore == 42)
        _ = subscription
    }
    
    @Test("Multiple subscribers receive published event")
    func testMultipleSubscribers() {
        let bus = EventBus()
        var count1 = 0
        var count2 = 0
        
        let sub1 = bus.subscribe(CustomScoreEvent.self) { _ in
            count1 += 1
        }
        let sub2 = bus.subscribe(CustomScoreEvent.self) { _ in
            count2 += 1
        }
        
        bus.publish(CustomScoreEvent(score: 10))
        
        #expect(count1 == 1)
        #expect(count2 == 1)
        
        _ = sub1
        _ = sub2
    }
    
    @Test("Subscription cancellation stops notifications")
    func testSubscriptionCancellation() {
        let bus = EventBus()
        var receivedCount = 0
        
        let sub = bus.subscribe(CustomScoreEvent.self) { _ in
            receivedCount += 1
        }
        
        bus.publish(CustomScoreEvent(score: 1))
        #expect(receivedCount == 1)
        
        sub.cancel()
        
        bus.publish(CustomScoreEvent(score: 2))
        #expect(receivedCount == 1)
    }
    
    @Test("Frame buffered event retrieval and clearance")
    func testFrameBufferedEvents() {
        let bus = EventBus()
        
        #expect(!bus.hasEvents(ofType: CustomScoreEvent.self))
        #expect(bus.events(ofType: CustomScoreEvent.self).isEmpty)
        
        bus.publish(CustomScoreEvent(score: 100))
        bus.publish(CustomScoreEvent(score: 200))
        bus.publish(CustomMessageEvent(message: "hello"))
        
        #expect(bus.hasEvents(ofType: CustomScoreEvent.self))
        #expect(bus.hasEvents(ofType: CustomMessageEvent.self))
        
        let scores = bus.events(ofType: CustomScoreEvent.self)
        #expect(scores.count == 2)
        #expect(scores[0].score == 100)
        #expect(scores[1].score == 200)
        
        let messages = bus.events(ofType: CustomMessageEvent.self)
        #expect(messages.count == 1)
        #expect(messages[0].message == "hello")
        
        bus.clear()
        
        #expect(!bus.hasEvents(ofType: CustomScoreEvent.self))
        #expect(bus.events(ofType: CustomScoreEvent.self).isEmpty)
        #expect(!bus.hasEvents(ofType: CustomMessageEvent.self))
        #expect(bus.events(ofType: CustomMessageEvent.self).isEmpty)
    }
    
    @Test("World update publishes tick event and clears frame events")
    func testWorldUpdateTickEvent() {
        let world = World()
        var tickDelta: Double?
        
        let sub = world.eventBus.subscribe(EngineTickEvent.self) { event in
            tickDelta = event.deltaTime
        }
        
        world.update(deltaTime: 0.016)
        
        #expect(tickDelta == 0.016)
        // Frame events should be cleared at end of world update
        #expect(!world.eventBus.hasEvents(ofType: EngineTickEvent.self))
        
        _ = sub
    }
}
