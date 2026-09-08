import Foundation
import simd
import AcornEngine
import AcornMath
#if canImport(Metal)
import Metal
#endif

/// A class that manages the player entity in the AcornEngine World.
///
/// `PlayerCharacter` handles 3D character positioning, smooth yaw rotation,
/// movement relative to third-person camera orientation, and real-world GPS synchronization.
@MainActor
public final class PlayerCharacter {
    /// The primary player entity in the ECS world.
    public let entity: Entity
    
    /// The locator ring / compass marker entity at the player's feet.
    public var beaconEntity: Entity?
    
    /// The current real-world GPS coordinate of the player.
    public private(set) var currentGPS: GPSCoordinate
    
    /// The current 3D world position of the player (in meters relative to world origin).
    public private(set) var worldPosition: SIMD3<Float>
    
    /// The current heading angle (yaw in radians) of the player.
    public private(set) var heading: Float
    
    /// Movement speed in meters per second.
    public var speed: Float
    
    /// Initializes a new player character instance.
    /// - Parameters:
    ///   - entity: The player's ECS entity.
    ///   - beaconEntity: Optional locator ring entity.
    ///   - currentGPS: Initial GPS location.
    ///   - worldPosition: Initial 3D world position.
    ///   - heading: Initial yaw heading in radians.
    ///   - speed: Movement speed in meters per second.
    public init(
        entity: Entity,
        beaconEntity: Entity? = nil,
        currentGPS: GPSCoordinate,
        worldPosition: SIMD3<Float>,
        heading: Float = 0.0,
        speed: Float = 10.0
    ) {
        self.entity = entity
        self.beaconEntity = beaconEntity
        self.currentGPS = currentGPS
        self.worldPosition = worldPosition
        self.heading = heading
        self.speed = speed
    }
    
    /// Creates and spawns a player character entity hierarchy into the world.
    /// - Parameters:
    ///   - world: The ECS world.
    ///   - renderer: The MetalRenderer used for creating buffers and loading models.
    ///   - initialGPS: The initial GPS coordinate where the player spawns.
    ///   - referenceGPS: The reference GPS coordinate mapping to the world origin (0, 0, 0).
    /// - Returns: A fully initialized `PlayerCharacter`.
    public static func create(
        in world: World,
        renderer: MetalRenderer,
        initialGPS: GPSCoordinate,
        referenceGPS: GPSCoordinate
    ) -> PlayerCharacter {
        let playerEntity = world.createEntity()
        #if DEBUG
        world.setName("PlayerCharacter", for: playerEntity)
        #endif
        
        // Calculate initial world position relative to reference GPS
        let deltaLat = initialGPS.latitude - referenceGPS.latitude
        let deltaLon = initialGPS.longitude - referenceGPS.longitude
        let latRad = referenceGPS.latitude * .pi / 180.0
        let cosLat = max(0.0001, cos(latRad))
        let initialX = Float(deltaLon * .pi / 180.0 * TileCoordinate.earthEquatorialRadius * cosLat)
        let initialZ = Float(-deltaLat * .pi / 180.0 * TileCoordinate.earthEquatorialRadius)
        let initialY = Float(initialGPS.altitude - referenceGPS.altitude)
        let initialPosition = SIMD3<Float>(initialX, initialY, initialZ)
        
        let transform = TransformComponent(position: initialPosition, rotation: .zero, scale: SIMD3<Float>(1, 1, 1))
        world.addComponent(transform, to: playerEntity)
        world.addComponent(GPSPositionComponent(coordinate: initialGPS), to: playerEntity)
        
        // 1. Create character visual model
        var modelLoaded = false
        if let avocadoUrl = findAvocadoModelURL() {
            do {
                let loader = GLTFModelLoader(device: renderer.device)
                let loaded = try loader.load(from: avocadoUrl)
                
                var texture: (any Texture)? = nil
                if let texData = loaded.textureData {
                    let decoder = CoreGraphicsImageDecoder()
                    if let (w, h, pixels) = decoder.decode(data: texData) {
                        texture = renderer.createTexture(width: w, height: h, pixelData: pixels, format: .rgba8Unorm)
                    }
                }
                
                // Root node for the scaled model
                let modelRoot = world.createEntity()
                #if DEBUG
                world.setName("PlayerVisualRoot", for: modelRoot)
                #endif
                let rootTransform = TransformComponent(
                    position: SIMD3<Float>(0, 0, 0),
                    rotation: .zero,
                    scale: SIMD3<Float>(15.0, 15.0, 15.0)
                )
                world.addComponent(rootTransform, to: modelRoot)
                world.addComponent(ParentComponent(parent: playerEntity), to: modelRoot)
                
                var nodeEntities: [Entity] = []
                for node in loaded.nodes {
                    let nodeEntity = world.createEntity()
                    #if DEBUG
                    world.setName("Avocado_\(node.name)", for: nodeEntity)
                    #endif
                    let localTransform = TransformComponent(
                        position: node.translation,
                        rotation: quaternionToEuler(node.rotation),
                        scale: node.scale
                    )
                    world.addComponent(localTransform, to: nodeEntity)
                    if let meshIdx = node.meshIndex, meshIdx < loaded.meshes.count {
                        let meshComp = MeshComponent(
                            mesh: loaded.meshes[meshIdx],
                            color: SIMD4<Float>(1, 1, 1, 1),
                            texture: texture
                        )
                        world.addComponent(meshComp, to: nodeEntity)
                    }
                    nodeEntities.append(nodeEntity)
                }
                
                for (index, node) in loaded.nodes.enumerated() {
                    if let parentIdx = node.parentIndex, parentIdx < nodeEntities.count {
                        world.addComponent(ParentComponent(parent: nodeEntities[parentIdx]), to: nodeEntities[index])
                    } else {
                        world.addComponent(ParentComponent(parent: modelRoot), to: nodeEntities[index])
                    }
                }
                modelLoaded = true
            } catch {
                // Fallback to stylized avatar mesh
                modelLoaded = false
            }
        }
        
        // 1. Create stylized 3D Avatar (pawn / capsule)
        let avatarEntity = world.createEntity()
        #if DEBUG
        world.setName("PlayerStylizedAvatar", for: avatarEntity)
        #endif
        world.addComponent(TransformComponent(position: .zero), to: avatarEntity)
        world.addComponent(ParentComponent(parent: playerEntity), to: avatarEntity)
        
        let avatarVertices = generateAvatarVertices()
        if let avatarMesh = renderer.createMesh(vertices: avatarVertices) {
            world.addComponent(MeshComponent(mesh: avatarMesh), to: avatarEntity)
        }
        
        // 2. Create beacon ring / ground compass circle mesh at player's feet
        let beaconEntity = world.createEntity()
        #if DEBUG
        world.setName("PlayerBeaconRing", for: beaconEntity)
        #endif
        let beaconTransform = TransformComponent(position: SIMD3<Float>(0, 0.08, 0))
        world.addComponent(beaconTransform, to: beaconEntity)
        world.addComponent(ParentComponent(parent: playerEntity), to: beaconEntity)
        
        let beaconVertices = generateBeaconRingVertices()
        if let beaconMesh = renderer.createMesh(vertices: beaconVertices) {
            world.addComponent(MeshComponent(mesh: beaconMesh), to: beaconEntity)
        }
        
        return PlayerCharacter(
            entity: playerEntity,
            beaconEntity: beaconEntity,
            currentGPS: initialGPS,
            worldPosition: initialPosition,
            heading: 0.0,
            speed: 10.0
        )
    }
    
    /// Moves the player character according to user directional input relative to camera orientation.
    /// - Parameters:
    ///   - input: Normalized input vector `(x: right/left, y: forward/back)`.
    ///   - cameraYaw: Current yaw angle of the third-person camera in radians.
    ///   - deltaTime: Elapsed frame time in seconds.
    ///   - referenceGPS: The reference GPS coordinate of the world origin.
    public func move(
        input: SIMD2<Float>,
        cameraYaw: Float,
        deltaTime: Double,
        referenceGPS: GPSCoordinate
    ) {
        let inputMagnitude = simd_length(input)
        guard inputMagnitude > 0.001 else { return }
        
        // Camera orientation on the horizontal XZ plane:
        // When cameraYaw is 0, camera looks along -Z (North) and right is +X (East).
        let camForward = SIMD3<Float>(-sin(cameraYaw), 0, -cos(cameraYaw))
        let camRight = SIMD3<Float>(cos(cameraYaw), 0, -sin(cameraYaw))
        
        let normalizedInput = input / inputMagnitude
        let moveDir3D = camRight * normalizedInput.x + camForward * normalizedInput.y
        let moveLen = simd_length(moveDir3D)
        guard moveLen > 0.001 else { return }
        let moveDir = moveDir3D / moveLen
        
        // Update world position
        let actualSpeed = speed * min(inputMagnitude, 1.0)
        let step = actualSpeed * Float(deltaTime)
        worldPosition.x += moveDir.x * step
        worldPosition.z += moveDir.z * step
        
        // Update heading smoothly towards movement direction.
        // In AcornEngine space, heading 0 faces -Z, pi/2 faces -X, -pi/2 faces +X, pi faces +Z.
        let targetHeading = atan2(-moveDir.x, -moveDir.z)
        var diff = targetHeading - heading
        while diff < -.pi { diff += 2 * .pi }
        while diff > .pi { diff -= 2 * .pi }
        
        let turnSpeed: Float = 12.0 // Radians per second
        let maxTurn = turnSpeed * Float(deltaTime)
        if abs(diff) <= maxTurn {
            heading = targetHeading
        } else {
            heading += (diff > 0 ? maxTurn : -maxTurn)
        }
        while heading < -.pi { heading += 2 * .pi }
        while heading > .pi { heading -= 2 * .pi }
        
        // Convert world position back to GPS coordinates relative to referenceGPS
        let latRad = referenceGPS.latitude * .pi / 180.0
        let cosLat = max(0.0001, cos(latRad))
        let deltaLon = Double(worldPosition.x) / (TileCoordinate.earthEquatorialRadius * cosLat) * 180.0 / .pi
        let deltaLat = Double(-worldPosition.z) / TileCoordinate.earthEquatorialRadius * 180.0 / .pi
        currentGPS = GPSCoordinate(
            latitude: referenceGPS.latitude + deltaLat,
            longitude: referenceGPS.longitude + deltaLon,
            altitude: referenceGPS.altitude + Double(worldPosition.y)
        )
    }
    
    /// Synchronizes the player's world position and GPS components to the ECS world.
    /// - Parameter world: The ECS world.
    public func updateWorld(world: World) {
        var transform = world.component(ofType: TransformComponent.self, for: entity) ?? TransformComponent()
        transform.position = worldPosition
        transform.rotation = SIMD3<Float>(0, heading, 0)
        world.addComponent(transform, to: entity)
        world.addComponent(GPSPositionComponent(coordinate: currentGPS), to: entity)
    }
    
    /// Teleports the player to a new GPS coordinate.
    /// - Parameters:
    ///   - newGPS: The new target GPS coordinate.
    ///   - referenceGPS: The reference GPS coordinate of the world origin.
    ///   - world: The ECS world.
    public func setGPSCoordinate(_ newGPS: GPSCoordinate, referenceGPS: GPSCoordinate, world: World) {
        currentGPS = newGPS
        
        let deltaLat = newGPS.latitude - referenceGPS.latitude
        let deltaLon = newGPS.longitude - referenceGPS.longitude
        let latRad = referenceGPS.latitude * .pi / 180.0
        let cosLat = max(0.0001, cos(latRad))
        let worldX = Float(deltaLon * .pi / 180.0 * TileCoordinate.earthEquatorialRadius * cosLat)
        let worldZ = Float(-deltaLat * .pi / 180.0 * TileCoordinate.earthEquatorialRadius)
        let worldY = Float(newGPS.altitude - referenceGPS.altitude)
        worldPosition = SIMD3<Float>(worldX, worldY, worldZ)
        
        updateWorld(world: world)
    }
    
    // MARK: - Helper Builders
    
    private static func findAvocadoModelURL() -> URL? {
        if let url = Bundle.main.url(forResource: "Avocado", withExtension: "glb") {
            return url
        }
        let bundle = Bundle(for: PlayerCharacter.self)
        if let url = bundle.url(forResource: "Avocado", withExtension: "glb") {
            return url
        }
        let documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Avocado.glb")
        if let documentsUrl, FileManager.default.fileExists(atPath: documentsUrl.path) {
            return documentsUrl
        }
        let candidatePaths = [
            "Samples/Acorn3DSample/Acorn3DSample/Resources/Avocado.glb",
            "../Samples/Acorn3DSample/Acorn3DSample/Resources/Avocado.glb"
        ]
        for p in candidatePaths {
            let u = URL(fileURLWithPath: p)
            if FileManager.default.fileExists(atPath: u.path) {
                return u
            }
        }
        return nil
    }
    
    private static func generateBeaconRingVertices() -> [Vertex] {
        var vertices: [Vertex] = []
        let segments = 36
        let innerRadius: Float = 0.85
        let outerRadius: Float = 1.20
        let ringColor = SIMD4<Float>(0.2, 0.85, 1.0, 0.95) // Bright cyan
        let pointerColor = SIMD4<Float>(1.0, 0.85, 0.15, 1.0) // Bright gold
        let upNormal = SIMD3<Float>(0, 1, 0)
        
        // Circular ring on XZ plane
        for i in 0..<segments {
            let theta0 = Float(i) * 2.0 * .pi / Float(segments)
            let theta1 = Float(i + 1) * 2.0 * .pi / Float(segments)
            
            let pIn0 = SIMD3<Float>(innerRadius * sin(theta0), 0, -innerRadius * cos(theta0))
            let pOut0 = SIMD3<Float>(outerRadius * sin(theta0), 0, -outerRadius * cos(theta0))
            let pIn1 = SIMD3<Float>(innerRadius * sin(theta1), 0, -innerRadius * cos(theta1))
            let pOut1 = SIMD3<Float>(outerRadius * sin(theta1), 0, -outerRadius * cos(theta1))
            
            // Double-sided quad for this segment
            vertices.append(contentsOf: [
                Vertex(position: pIn0, color: ringColor, texCoord: .zero, normal: upNormal),
                Vertex(position: pOut0, color: ringColor, texCoord: .zero, normal: upNormal),
                Vertex(position: pIn1, color: ringColor, texCoord: .zero, normal: upNormal),
                
                Vertex(position: pIn1, color: ringColor, texCoord: .zero, normal: upNormal),
                Vertex(position: pOut0, color: ringColor, texCoord: .zero, normal: upNormal),
                Vertex(position: pOut1, color: ringColor, texCoord: .zero, normal: upNormal),
                
                // Backface
                Vertex(position: pIn0, color: ringColor, texCoord: .zero, normal: -upNormal),
                Vertex(position: pIn1, color: ringColor, texCoord: .zero, normal: -upNormal),
                Vertex(position: pOut0, color: ringColor, texCoord: .zero, normal: -upNormal),
                
                Vertex(position: pIn1, color: ringColor, texCoord: .zero, normal: -upNormal),
                Vertex(position: pOut1, color: ringColor, texCoord: .zero, normal: -upNormal),
                Vertex(position: pOut0, color: ringColor, texCoord: .zero, normal: -upNormal)
            ])
        }
        
        // Front compass arrow tip pointing forward (-Z)
        let tip = SIMD3<Float>(0, 0.02, -outerRadius - 0.70)
        let leftBase = SIMD3<Float>(-0.35, 0.02, -outerRadius + 0.10)
        let rightBase = SIMD3<Float>(0.35, 0.02, -outerRadius + 0.10)
        
        vertices.append(contentsOf: [
            Vertex(position: tip, color: pointerColor, texCoord: .zero, normal: upNormal),
            Vertex(position: rightBase, color: pointerColor, texCoord: .zero, normal: upNormal),
            Vertex(position: leftBase, color: pointerColor, texCoord: .zero, normal: upNormal),
            
            Vertex(position: tip, color: pointerColor, texCoord: .zero, normal: -upNormal),
            Vertex(position: leftBase, color: pointerColor, texCoord: .zero, normal: -upNormal),
            Vertex(position: rightBase, color: pointerColor, texCoord: .zero, normal: -upNormal)
        ])
        
        return vertices
    }
    
    private static func generateAvatarVertices() -> [Vertex] {
        var vertices: [Vertex] = []
        // Body cylinder (radius 0.25, height 1.40) - representing average adult male torso & legs
        let bodyColor = SIMD4<Float>(0.1, 0.55, 1.0, 1.0)
        let bodyVerts = BasicShapeGenerator.generateCylinder(radius: 0.25, height: 1.40, segments: 20, color: bodyColor)
        for v in bodyVerts {
            var vOffset = v
            vOffset.position.y += 0.70 // Sit on ground (spans y: 0.0 to 1.40)
            vertices.append(vOffset)
        }
        
        // Head sphere (radius 0.19) - top of head reaches 1.78m (average adult male height)
        let headColor = SIMD4<Float>(1.0, 0.85, 0.25, 1.0)
        let headVerts = BasicShapeGenerator.generateSphere(radius: 0.19, rings: 12, segments: 20, color: headColor)
        for v in headVerts {
            var vOffset = v
            vOffset.position.y += 1.59 // Centered at 1.59m (spans y: 1.40 to 1.78)
            vertices.append(vOffset)
        }
        
        return vertices
    }
}
