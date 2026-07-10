import Testing
import simd
@testable import AcornEngine

struct BasicShapeTests {
    @Test("Plane Mesh Generation")
    func testPlaneGeneration() {
        let vertices = BasicShapeGenerator.generatePlane(width: 2.0, height: 3.0)
        #expect(vertices.count == 6)
        
        // Check bounding box
        let minX = vertices.map { $0.position.x }.min()
        let maxX = vertices.map { $0.position.x }.max()
        let minY = vertices.map { $0.position.y }.min()
        let maxY = vertices.map { $0.position.y }.max()
        
        #expect(minX == -1.0)
        #expect(maxX == 1.0)
        #expect(minY == -1.5)
        #expect(maxY == 1.5)
    }
    
    @Test("Cube Mesh Generation")
    func testCubeGeneration() {
        let vertices = BasicShapeGenerator.generateCube(size: SIMD3<Float>(2, 4, 6))
        #expect(vertices.count == 36)
        
        let minX = vertices.map { $0.position.x }.min()
        let maxX = vertices.map { $0.position.x }.max()
        let minY = vertices.map { $0.position.y }.min()
        let maxY = vertices.map { $0.position.y }.max()
        let minZ = vertices.map { $0.position.z }.min()
        let maxZ = vertices.map { $0.position.z }.max()
        
        #expect(minX == -1.0)
        #expect(maxX == 1.0)
        #expect(minY == -2.0)
        #expect(maxY == 2.0)
        #expect(minZ == -3.0)
        #expect(maxZ == 3.0)
    }
    
    @Test("Sphere Mesh Generation")
    func testSphereGeneration() {
        let rings = 10
        let segments = 20
        let vertices = BasicShapeGenerator.generateSphere(radius: 1.0, rings: rings, segments: segments)
        
        // Each quad has 2 triangles (6 vertices)
        let expectedCount = rings * segments * 6
        #expect(vertices.count == expectedCount)
        
        for vertex in vertices {
            let length = simd_length(vertex.position)
            #expect(abs(length - 1.0) < 0.001) // Distance to center should equal radius
        }
    }
    
    @Test("Cylinder Mesh Generation")
    func testCylinderGeneration() {
        let segments = 20
        let vertices = BasicShapeGenerator.generateCylinder(radius: 1.0, height: 4.0, segments: segments)
        
        // Quads for sides: segments * 6
        // Triangles for top cap: segments * 3
        // Triangles for bottom cap: segments * 3
        // Total = segments * 12
        let expectedCount = segments * 12
        #expect(vertices.count == expectedCount)
    }
    
    @Test("Cone Mesh Generation")
    func testConeGeneration() {
        let segments = 20
        let vertices = BasicShapeGenerator.generateCone(radius: 1.0, height: 4.0, segments: segments)
        
        // Triangles for sides: segments * 3
        // Triangles for bottom cap: segments * 3
        // Total = segments * 6
        let expectedCount = segments * 6
        #expect(vertices.count == expectedCount)
    }
}
