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
        
        #expect(e1.index == 0)
        #expect(e2.index == 1)
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
    
    @Test("Parent-Child transform propagation")
    func testParentChildTransform() {
        let world = World()
        
        let parent = world.createEntity()
        let parentTransform = TransformComponent(
            position: SIMD3<Float>(10, 0, 0),
            rotation: SIMD3<Float>(0, 0, 0),
            scale: SIMD3<Float>(2, 2, 2)
        )
        world.addComponent(parentTransform, to: parent)
        
        let child = world.createEntity()
        let childTransform = TransformComponent(
            position: SIMD3<Float>(5, 0, 0),
            rotation: SIMD3<Float>(0, 0, 0),
            scale: SIMD3<Float>(1, 1, 1)
        )
        world.addComponent(childTransform, to: child)
        world.addComponent(ParentComponent(parent: parent), to: child)
        
        let childWorldMatrix = world.worldMatrix(for: child)
        let childWorldPos = world.worldPosition(for: child)
        
        // Parent translates by 10 and scales by 2
        // Local child translates by 5
        // Expected world position of child = parentPos + parentScale * childLocalPos = 10 + 2 * 5 = 20
        #expect(childWorldPos.x == 20)
        #expect(childWorldMatrix.columns.3.x == 20)
    }
    
    @Test("Parent-Child hierarchy mapping")
    func testParentChildHierarchy() {
        let world = World()
        
        let e1 = world.createEntity()
        let e2 = world.createEntity()
        let e3 = world.createEntity()
        
        // e2 and e3 are children of e1
        world.addComponent(ParentComponent(parent: e1), to: e2)
        world.addComponent(ParentComponent(parent: e1), to: e3)
        
        let allEntitiesList = world.allEntities
        var childrenMap: [Entity: [Entity]] = [:]
        var rootEntities: [Entity] = []
        
        for entity in allEntitiesList {
            if let parentComp = world.component(ofType: ParentComponent.self, for: entity),
               allEntitiesList.contains(parentComp.parent) {
                childrenMap[parentComp.parent, default: []].append(entity)
            } else {
                rootEntities.append(entity)
            }
        }
        
        #expect(rootEntities.count == 1)
        #expect(rootEntities.first == e1)
        
        let e1Children = childrenMap[e1] ?? []
        #expect(e1Children.count == 2)
        #expect(e1Children.contains(e2))
        #expect(e1Children.contains(e3))
    }
    
    @Test("Entity generational indexing and ABA protection")
    func testEntityGenerationalIndexing() {
        let world = World()
        let e1 = world.createEntity()
        #expect(e1.index == 0)
        #expect(e1.generation == 1)
        
        world.addComponent(PositionComponent(x: 10, y: 20), to: e1)
        world.destroyEntity(e1)
        
        // Re-creating entity recycles index 0 with generation 2
        let e2 = world.createEntity()
        #expect(e2.index == 0)
        #expect(e2.generation == 2)
        #expect(e1 != e2)
        #expect(e1.id != e2.id)
        
        // Old stale entity reference should not match or mutate e2's components
        world.addComponent(PositionComponent(x: 99, y: 99), to: e1)
        #expect(world.component(ofType: PositionComponent.self, for: e2) == nil)
    }
    
    @Test("In-place component mutation")
    func testMutateComponent() {
        let world = World()
        let entity = world.createEntity()
        world.addComponent(PositionComponent(x: 10, y: 20), to: entity)
        
        world.mutateComponent(ofType: PositionComponent.self, for: entity) { pos in
            pos.x += 5
            pos.y += 10
        }
        
        let retrieved = world.component(ofType: PositionComponent.self, for: entity)
        #expect(retrieved?.x == 15)
        #expect(retrieved?.y == 30)
    }
    
    @Test("mutateEach safe component pool mutation")
    func testMutateEach() {
        let world = World()
        let e1 = world.createEntity()
        let e2 = world.createEntity()
        
        world.addComponent(PositionComponent(x: 10, y: 20), to: e1)
        world.addComponent(PositionComponent(x: 30, y: 40), to: e2)
        
        world.mutateEach(PositionComponent.self) { entity, pos in
            pos.x += 1
            pos.y += 2
        }
        
        #expect(world.component(ofType: PositionComponent.self, for: e1)?.x == 11)
        #expect(world.component(ofType: PositionComponent.self, for: e2)?.x == 31)
    }
    
    @Test("firstEntity query with named tuple elements")
    func testFirstEntity() {
        let world = World()
        let empty = world.firstEntity(with: PositionComponent.self)
        #expect(empty == nil)
        
        let e1 = world.createEntity()
        world.addComponent(PositionComponent(x: 42, y: 84), to: e1)
        
        let match = world.firstEntity(with: PositionComponent.self)
        #expect(match != nil)
        #expect(match?.entity == e1)
        #expect(match?.component.x == 42)
    }
    
    @Test("forEach zero-allocation iteration")
    func testForEachIteration() {
        let world = World()
        let e1 = world.createEntity()
        let e2 = world.createEntity()
        let e3 = world.createEntity()
        
        world.addComponent(PositionComponent(x: 1, y: 2), to: e1)
        world.addComponent(VelocityComponent(dx: 10, dy: 20), to: e1)
        
        world.addComponent(PositionComponent(x: 3, y: 4), to: e2)
        world.addComponent(VelocityComponent(dx: 30, dy: 40), to: e2)
        
        world.addComponent(PositionComponent(x: 5, y: 6), to: e3) // No Velocity
        
        var totalX: Float = 0
        world.forEach(PositionComponent.self) { _, pos in
            totalX += pos.x
        }
        #expect(totalX == 9)
        
        var combinedCount = 0
        world.forEach(PositionComponent.self, VelocityComponent.self) { entity, pos, vel in
            combinedCount += 1
            #expect(entity == e1 || entity == e2)
        }
        #expect(combinedCount == 2)
    }
    
    @Test("Circular hierarchy recursion depth limit")
    func testCircularHierarchyGuard() {
        let world = World()
        let e1 = world.createEntity()
        let e2 = world.createEntity()
        
        world.addComponent(TransformComponent(position: SIMD3<Float>(1, 0, 0)), to: e1)
        world.addComponent(TransformComponent(position: SIMD3<Float>(2, 0, 0)), to: e2)
        
        world.addComponent(ParentComponent(parent: e2), to: e1)
        world.addComponent(ParentComponent(parent: e1), to: e2) // Circular reference
        
        // Should terminate gracefully due to max depth limit instead of hanging indefinitely
        let matrix = world.worldMatrix(for: e1)
        #expect(matrix.columns.3.x != 0)
    }
    
    @Test("Multi-component entity destruction")
    func testMultiComponentDestruction() {
        let world = World()
        let entity = world.createEntity()
        
        world.addComponent(PositionComponent(x: 1, y: 2), to: entity)
        world.addComponent(VelocityComponent(dx: 3, dy: 4), to: entity)
        
        #expect(world.component(ofType: PositionComponent.self, for: entity) != nil)
        #expect(world.component(ofType: VelocityComponent.self, for: entity) != nil)
        
        world.destroyEntity(entity)
        
        #expect(world.component(ofType: PositionComponent.self, for: entity) == nil)
        #expect(world.component(ofType: VelocityComponent.self, for: entity) == nil)
        #expect(world.entities(with: PositionComponent.self).isEmpty)
        #expect(world.entities(with: VelocityComponent.self).isEmpty)
    }
}
