import Testing
@testable import AcornEngine

struct PositionComponent: Component {
    var x: Float
    var y: Float
}

struct VelocityComponent: Component {
    var dx: Float
    var dy: Float
}

struct MovementSystem: System {
    func update(world: World, deltaTime: Double) {
        let entities = world.entities(with: PositionComponent.self)
        for (entity, position) in entities {
            if let velocity = world.component(ofType: VelocityComponent.self, for: entity) {
                var newPos = position
                newPos.x += velocity.dx * Float(deltaTime)
                newPos.y += velocity.dy * Float(deltaTime)
                world.addComponent(newPos, to: entity)
            }
        }
    }
}

@Suite("ECS Tests")
@MainActor
struct ECSTests {
    
    @Test("Entity creation and destruction")
    func testEntityLifecycle() {
        let world = World()
        
        let e1 = world.createEntity()
        let e2 = world.createEntity()
        
        #expect(e1.id == 0)
        #expect(e2.id == 1)
        #expect(e1 != e2)
        
        world.destroyEntity(e1)
        // Components should be removed when destroyed
        world.addComponent(PositionComponent(x: 0, y: 0), to: e1) // Shouldn't be added since entity is destroyed
        let retrieved = world.component(ofType: PositionComponent.self, for: e1)
        #expect(retrieved == nil)
    }
    
    @Test("Component addition, retrieval and removal")
    func testComponentManagement() {
        let world = World()
        let entity = world.createEntity()
        
        let position = PositionComponent(x: 10, y: 20)
        world.addComponent(position, to: entity)
        
        let retrieved = world.component(ofType: PositionComponent.self, for: entity)
        #expect(retrieved?.x == 10)
        #expect(retrieved?.y == 20)
        
        world.removeComponent(ofType: PositionComponent.self, from: entity)
        let afterRemoval = world.component(ofType: PositionComponent.self, for: entity)
        #expect(afterRemoval == nil)
    }
    
    @Test("System execution updates components")
    func testSystemExecution() {
        let world = World()
        let entity = world.createEntity()
        
        world.addComponent(PositionComponent(x: 0, y: 0), to: entity)
        world.addComponent(VelocityComponent(dx: 5, dy: 10), to: entity)
        
        let system = MovementSystem()
        world.registerSystem(system)
        
        world.update(deltaTime: 2.0)
        
        let position = world.component(ofType: PositionComponent.self, for: entity)
        #expect(position?.x == 10)
        #expect(position?.y == 20)
    }
}
