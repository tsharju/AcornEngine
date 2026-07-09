import Testing
import AcornEngine
import simd
@testable import MatchAcorn

@MainActor
struct MatchAcornTests {
    
    @Test func testHorizontalMatchThree() async throws {
        let world = World()
        var grid = Array(repeating: Array(repeating: Entity?.none, count: 8), count: 8)
        
        // Setup 3 horizontal red acorns at (0,0), (1,0), (2,0)
        let e1 = world.createEntity()
        let e2 = world.createEntity()
        let e3 = world.createEntity()
        
        world.addComponent(AcornComponent(color: .red, gridX: 0, gridY: 0), to: e1)
        world.addComponent(AcornComponent(color: .red, gridX: 1, gridY: 0), to: e2)
        world.addComponent(AcornComponent(color: .red, gridX: 2, gridY: 0), to: e3)
        
        grid[0][0] = e1
        grid[1][0] = e2
        grid[2][0] = e3
        
        // Add a 4th green acorn at (3,0) which should NOT match
        let e4 = world.createEntity()
        world.addComponent(AcornComponent(color: .green, gridX: 3, gridY: 0), to: e4)
        grid[3][0] = e4
        
        let matches = BoardSystem.findMatches(grid: grid, world: world)
        
        #expect(matches.count == 3)
        #expect(matches.contains(e1))
        #expect(matches.contains(e2))
        #expect(matches.contains(e3))
        #expect(!matches.contains(e4))
    }
    
    @Test func testVerticalMatchThree() async throws {
        let world = World()
        var grid = Array(repeating: Array(repeating: Entity?.none, count: 8), count: 8)
        
        // Setup 3 vertical blue acorns at (2,1), (2,2), (2,3)
        let e1 = world.createEntity()
        let e2 = world.createEntity()
        let e3 = world.createEntity()
        
        world.addComponent(AcornComponent(color: .blue, gridX: 2, gridY: 1), to: e1)
        world.addComponent(AcornComponent(color: .blue, gridX: 2, gridY: 2), to: e2)
        world.addComponent(AcornComponent(color: .blue, gridX: 2, gridY: 3), to: e3)
        
        grid[2][1] = e1
        grid[2][2] = e2
        grid[2][3] = e3
        
        let matches = BoardSystem.findMatches(grid: grid, world: world)
        
        #expect(matches.count == 3)
        #expect(matches.contains(e1))
        #expect(matches.contains(e2))
        #expect(matches.contains(e3))
    }
    
    @Test func testNoMatchForTwo() async throws {
        let world = World()
        var grid = Array(repeating: Array(repeating: Entity?.none, count: 8), count: 8)
        
        // Setup only 2 horizontal purple acorns at (4,4), (5,4)
        let e1 = world.createEntity()
        let e2 = world.createEntity()
        
        world.addComponent(AcornComponent(color: .purple, gridX: 4, gridY: 4), to: e1)
        world.addComponent(AcornComponent(color: .purple, gridX: 5, gridY: 4), to: e2)
        
        grid[4][4] = e1
        grid[5][4] = e2
        
        let matches = BoardSystem.findMatches(grid: grid, world: world)
        
        #expect(matches.isEmpty)
    }
}
