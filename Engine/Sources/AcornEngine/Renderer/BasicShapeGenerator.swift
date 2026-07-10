import Foundation
import simd

/// A utility for generating vertices of basic 3D shapes.
public enum BasicShapeGenerator {
    
    /// Generates vertices for a plane (quad) centered at the origin on the XY plane.
    /// - Parameters:
    ///   - width: The width of the plane.
    ///   - height: The height of the plane.
    ///   - color: The color to apply to all vertices.
    /// - Returns: An array of vertices representing the plane (6 vertices for 2 triangles).
    public static func generatePlane(width: Float = 1.0, height: Float = 1.0, color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)) -> [Vertex] {
        let hw = width * 0.5
        let hh = height * 0.5
        
        let v0 = Vertex(position: SIMD3<Float>(-hw, -hh, 0), color: color, texCoord: SIMD2<Float>(0, 1))
        let v1 = Vertex(position: SIMD3<Float>(hw, -hh, 0), color: color, texCoord: SIMD2<Float>(1, 1))
        let v2 = Vertex(position: SIMD3<Float>(-hw, hh, 0), color: color, texCoord: SIMD2<Float>(0, 0))
        let v3 = Vertex(position: SIMD3<Float>(hw, hh, 0), color: color, texCoord: SIMD2<Float>(1, 0))
        
        return [
            v0, v1, v2,
            v2, v1, v3
        ]
    }
    
    /// Generates vertices for a cube (box) centered at the origin.
    /// - Parameters:
    ///   - size: The size of the cube along X, Y, and Z axes.
    ///   - color: The color to apply to all vertices.
    /// - Returns: An array of vertices representing the cube (36 vertices for 12 triangles).
    public static func generateCube(size: SIMD3<Float> = SIMD3<Float>(1, 1, 1), color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)) -> [Vertex] {
        let hs = size * 0.5
        
        // Define the 8 corner vertices
        let p000 = SIMD3<Float>(-hs.x, -hs.y, -hs.z)
        let p100 = SIMD3<Float>(hs.x, -hs.y, -hs.z)
        let p010 = SIMD3<Float>(-hs.x, hs.y, -hs.z)
        let p110 = SIMD3<Float>(hs.x, hs.y, -hs.z)
        let p001 = SIMD3<Float>(-hs.x, -hs.y, hs.z)
        let p101 = SIMD3<Float>(hs.x, -hs.y, hs.z)
        let p011 = SIMD3<Float>(-hs.x, hs.y, hs.z)
        let p111 = SIMD3<Float>(hs.x, hs.y, hs.z)
        
        var vertices: [Vertex] = []
        
        // Helper to add a quad face with CCW winding looking from the outside
        func addFace(v0: SIMD3<Float>, v1: SIMD3<Float>, v2: SIMD3<Float>, v3: SIMD3<Float>) {
            vertices.append(contentsOf: [
                Vertex(position: v0, color: color, texCoord: SIMD2<Float>(0, 1)),
                Vertex(position: v1, color: color, texCoord: SIMD2<Float>(1, 1)),
                Vertex(position: v2, color: color, texCoord: SIMD2<Float>(0, 0)),
                
                Vertex(position: v2, color: color, texCoord: SIMD2<Float>(0, 0)),
                Vertex(position: v1, color: color, texCoord: SIMD2<Float>(1, 1)),
                Vertex(position: v3, color: color, texCoord: SIMD2<Float>(1, 0))
            ])
        }
        
        // Front (+Z): bottom-left, bottom-right, top-left, top-right
        addFace(v0: p001, v1: p101, v2: p011, v3: p111)
        // Back (-Z) (reverse direction to keep CCW winding from outside)
        addFace(v0: p100, v1: p000, v2: p110, v3: p010)
        // Left (-X)
        addFace(v0: p000, v1: p001, v2: p010, v3: p011)
        // Right (+X)
        addFace(v0: p101, v1: p100, v2: p111, v3: p110)
        // Top (+Y)
        addFace(v0: p011, v1: p111, v2: p010, v3: p110)
        // Bottom (-Y)
        addFace(v0: p000, v1: p100, v2: p001, v3: p101)
        
        return vertices
    }
    
    /// Generates vertices for a UV sphere centered at the origin.
    /// - Parameters:
    ///   - radius: The radius of the sphere.
    ///   - rings: The number of vertical divisions.
    ///   - segments: The number of horizontal divisions.
    ///   - color: The color of the vertices.
    /// - Returns: An array of vertices.
    public static func generateSphere(radius: Float = 0.5, rings: Int = 16, segments: Int = 32, color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)) -> [Vertex] {
        var vertices: [Vertex] = []
        
        // Generate grid of vertices
        var grid: [[Vertex]] = []
        for r in 0...rings {
            let theta = Float(r) * Float.pi / Float(rings)
            let sinTheta = sin(theta)
            let cosTheta = cos(theta)
            
            var row: [Vertex] = []
            for s in 0...segments {
                let phi = Float(s) * 2.0 * Float.pi / Float(segments)
                let sinPhi = sin(phi)
                let cosPhi = cos(phi)
                
                let x = radius * cosPhi * sinTheta
                let y = radius * cosTheta
                let z = radius * sinPhi * sinTheta
                
                let u = Float(s) / Float(segments)
                let v = Float(r) / Float(rings)
                
                row.append(Vertex(position: SIMD3<Float>(x, y, z), color: color, texCoord: SIMD2<Float>(u, v)))
            }
            grid.append(row)
        }
        
        // Build triangles
        for r in 0..<rings {
            for s in 0..<segments {
                let v0 = grid[r][s]
                let v1 = grid[r][s + 1]
                let v2 = grid[r + 1][s]
                let v3 = grid[r + 1][s + 1]
                
                // CCW winding
                vertices.append(contentsOf: [
                    v0, v1, v2,
                    v2, v1, v3
                ])
            }
        }
        
        return vertices
    }
    
    /// Generates vertices for a cylinder centered at the origin.
    /// - Parameters:
    ///   - radius: The radius of the cylinder.
    ///   - height: The height of the cylinder.
    ///   - segments: The number of radial segments.
    ///   - color: The color of the vertices.
    /// - Returns: An array of vertices.
    public static func generateCylinder(radius: Float = 0.5, height: Float = 1.0, segments: Int = 32, color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)) -> [Vertex] {
        var vertices: [Vertex] = []
        let hh = height * 0.5
        
        // Top and bottom centers
        let topCenter = SIMD3<Float>(0, hh, 0)
        let bottomCenter = SIMD3<Float>(0, -hh, 0)
        
        // Generate circular vertex coordinates
        var circleVertices: [SIMD3<Float>] = []
        for s in 0...segments {
            let theta = Float(s) * 2.0 * Float.pi / Float(segments)
            let x = radius * cos(theta)
            let z = radius * sin(theta)
            circleVertices.append(SIMD3<Float>(x, 0, z))
        }
        
        // 1. Side faces (Quads)
        for s in 0..<segments {
            let nextS = s + 1
            
            let p0 = circleVertices[s] + SIMD3<Float>(0, -hh, 0)
            let p1 = circleVertices[nextS] + SIMD3<Float>(0, -hh, 0)
            let p2 = circleVertices[s] + SIMD3<Float>(0, hh, 0)
            let p3 = circleVertices[nextS] + SIMD3<Float>(0, hh, 0)
            
            let u0 = Float(s) / Float(segments)
            let u1 = Float(nextS) / Float(segments)
            
            // CCW winding
            vertices.append(contentsOf: [
                Vertex(position: p0, color: color, texCoord: SIMD2<Float>(u0, 1)),
                Vertex(position: p1, color: color, texCoord: SIMD2<Float>(u1, 1)),
                Vertex(position: p2, color: color, texCoord: SIMD2<Float>(u0, 0)),
                
                Vertex(position: p2, color: color, texCoord: SIMD2<Float>(u0, 0)),
                Vertex(position: p1, color: color, texCoord: SIMD2<Float>(u1, 1)),
                Vertex(position: p3, color: color, texCoord: SIMD2<Float>(u1, 0))
            ])
        }
        
        // 2. Top Cap (CCW looking from above)
        for s in 0..<segments {
            let nextS = s + 1
            let pTop0 = circleVertices[s] + SIMD3<Float>(0, hh, 0)
            let pTop1 = circleVertices[nextS] + SIMD3<Float>(0, hh, 0)
            
            vertices.append(contentsOf: [
                Vertex(position: topCenter, color: color, texCoord: SIMD2<Float>(0.5, 0.5)),
                Vertex(position: pTop1, color: color, texCoord: SIMD2<Float>(0.5 + 0.5 * pTop1.x / radius, 0.5 + 0.5 * pTop1.z / radius)),
                Vertex(position: pTop0, color: color, texCoord: SIMD2<Float>(0.5 + 0.5 * pTop0.x / radius, 0.5 + 0.5 * pTop0.z / radius))
            ])
        }
        
        // 3. Bottom Cap (CCW looking from below / CW looking from above)
        for s in 0..<segments {
            let nextS = s + 1
            let pBottom0 = circleVertices[s] + SIMD3<Float>(0, -hh, 0)
            let pBottom1 = circleVertices[nextS] + SIMD3<Float>(0, -hh, 0)
            
            vertices.append(contentsOf: [
                Vertex(position: bottomCenter, color: color, texCoord: SIMD2<Float>(0.5, 0.5)),
                Vertex(position: pBottom0, color: color, texCoord: SIMD2<Float>(0.5 + 0.5 * pBottom0.x / radius, 0.5 + 0.5 * pBottom0.z / radius)),
                Vertex(position: pBottom1, color: color, texCoord: SIMD2<Float>(0.5 + 0.5 * pBottom1.x / radius, 0.5 + 0.5 * pBottom1.z / radius))
            ])
        }
        
        return vertices
    }
    
    /// Generates vertices for a cone centered at the origin.
    /// - Parameters:
    ///   - radius: The base radius of the cone.
    ///   - height: The height of the cone.
    ///   - segments: The number of radial segments.
    ///   - color: The color of the vertices.
    /// - Returns: An array of vertices.
    public static func generateCone(radius: Float = 0.5, height: Float = 1.0, segments: Int = 32, color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)) -> [Vertex] {
        var vertices: [Vertex] = []
        let hh = height * 0.5
        
        let apex = SIMD3<Float>(0, hh, 0)
        let bottomCenter = SIMD3<Float>(0, -hh, 0)
        
        // Generate circular vertex coordinates for the base
        var baseVertices: [SIMD3<Float>] = []
        for s in 0...segments {
            let theta = Float(s) * 2.0 * Float.pi / Float(segments)
            let x = radius * cos(theta)
            let z = radius * sin(theta)
            baseVertices.append(SIMD3<Float>(x, -hh, z))
        }
        
        // 1. Side faces
        for s in 0..<segments {
            let nextS = s + 1
            let p0 = baseVertices[s]
            let p1 = baseVertices[nextS]
            
            let u0 = Float(s) / Float(segments)
            let u1 = Float(nextS) / Float(segments)
            
            vertices.append(contentsOf: [
                Vertex(position: apex, color: color, texCoord: SIMD2<Float>(u0 + 0.5 / Float(segments), 0)),
                Vertex(position: p0, color: color, texCoord: SIMD2<Float>(u0, 1)),
                Vertex(position: p1, color: color, texCoord: SIMD2<Float>(u1, 1))
            ])
        }
        
        // 2. Bottom Cap
        for s in 0..<segments {
            let nextS = s + 1
            let pBottom0 = baseVertices[s]
            let pBottom1 = baseVertices[nextS]
            
            vertices.append(contentsOf: [
                Vertex(position: bottomCenter, color: color, texCoord: SIMD2<Float>(0.5, 0.5)),
                Vertex(position: pBottom0, color: color, texCoord: SIMD2<Float>(0.5 + 0.5 * pBottom0.x / radius, 0.5 + 0.5 * pBottom0.z / radius)),
                Vertex(position: pBottom1, color: color, texCoord: SIMD2<Float>(0.5 + 0.5 * pBottom1.x / radius, 0.5 + 0.5 * pBottom1.z / radius))
            ])
        }
        
        return vertices
    }
}
