import Foundation
import UIKit
import simd
import Testing
import AcornEngine
import AcornMath
@testable import Acorn3DSample

@Suite("PlayerCharacter, ThirdPersonFollowCamera, and GameHUDView Tests")
struct PlayerAndCameraTests {

    // MARK: - PlayerCharacter Tests
    
    @Test("PlayerCharacter initializes with expected properties")
    @MainActor
    func playerCharacterInitialization() {
        let world = World()
        let entity = world.createEntity()
        let initialGPS = GPSCoordinate(latitude: 60.1699, longitude: 24.9384, altitude: 10.0)
        let initialPos = SIMD3<Float>(10, 0, -20)
        
        let player = PlayerCharacter(
            entity: entity,
            currentGPS: initialGPS,
            worldPosition: initialPos,
            heading: 0.5,
            speed: 12.0
        )
        
        #expect(player.entity == entity)
        #expect(player.currentGPS == initialGPS)
        #expect(player.worldPosition == initialPos)
        #expect(player.heading == 0.5)
        #expect(player.speed == 12.0)
        #expect(player.beaconEntity == nil)
    }
    
    @Test("PlayerCharacter moves forward (-Z) when camera yaw is 0")
    @MainActor
    func playerMovementCameraYawZero() {
        let world = World()
        let entity = world.createEntity()
        let refGPS = GPSCoordinate(latitude: 60.1699, longitude: 24.9384, altitude: 0.0)
        
        let player = PlayerCharacter(
            entity: entity,
            currentGPS: refGPS,
            worldPosition: .zero,
            heading: 0.0,
            speed: 10.0
        )
        
        // Input: (0, 1) -> Forward
        player.move(input: SIMD2<Float>(0, 1), cameraYaw: 0.0, deltaTime: 1.0, referenceGPS: refGPS)
        
        // Should move in -Z by 10 meters (speed 10 * dt 1.0)
        #expect(abs(player.worldPosition.x - 0.0) < 1e-4)
        #expect(abs(player.worldPosition.z - (-10.0)) < 1e-4)
        #expect(abs(player.heading - 0.0) < 1e-4)
        
        // GPS should have moved north (deltaLat > 0)
        #expect(player.currentGPS.latitude > refGPS.latitude)
        #expect(abs(player.currentGPS.longitude - refGPS.longitude) < 1e-6)
    }
    
    @Test("PlayerCharacter moves west (-X) when camera yaw is 90 degrees and moving forward")
    @MainActor
    func playerMovementCameraYaw90() {
        let world = World()
        let entity = world.createEntity()
        let refGPS = GPSCoordinate(latitude: 60.1699, longitude: 24.9384, altitude: 0.0)
        
        let player = PlayerCharacter(
            entity: entity,
            currentGPS: refGPS,
            worldPosition: .zero,
            heading: 0.0,
            speed: 10.0
        )
        
        // Camera yaw = pi / 2. Input forward (0, 1). Camera looks West (-X).
        player.move(input: SIMD2<Float>(0, 1), cameraYaw: .pi / 2, deltaTime: 1.0, referenceGPS: refGPS)
        
        #expect(abs(player.worldPosition.x - (-10.0)) < 1e-4)
        #expect(abs(player.worldPosition.z - 0.0) < 1e-4)
        // Heading facing -X is pi / 2
        #expect(abs(player.heading - (.pi / 2)) < 1e-4)
        
        // GPS longitude should have moved west (deltaLon < 0)
        #expect(player.currentGPS.longitude < refGPS.longitude)
    }
    
    @Test("PlayerCharacter setGPSCoordinate teleports and updates components in world")
    @MainActor
    func playerTeleportGPS() {
        let world = World()
        let entity = world.createEntity()
        let refGPS = GPSCoordinate(latitude: 60.1699, longitude: 24.9384, altitude: 0.0)
        
        let player = PlayerCharacter(
            entity: entity,
            currentGPS: refGPS,
            worldPosition: .zero,
            heading: 0.0,
            speed: 10.0
        )
        player.updateWorld(world: world)
        
        let targetGPS = GPSCoordinate(latitude: 60.1708, longitude: 24.9414, altitude: 5.0)
        player.setGPSCoordinate(targetGPS, referenceGPS: refGPS, world: world)
        
        #expect(player.currentGPS == targetGPS)
        #expect(player.worldPosition.x > 0) // East
        #expect(player.worldPosition.z < 0) // North
        #expect(player.worldPosition.y == 5.0)
        
        // Verify world components
        let transform = world.component(ofType: TransformComponent.self, for: entity)
        #expect(transform != nil)
        #expect(transform?.position == player.worldPosition)
        
        let gpsComp = world.component(ofType: GPSPositionComponent.self, for: entity)
        #expect(gpsComp != nil)
        #expect(gpsComp?.coordinate == targetGPS)
    }

    // MARK: - ThirdPersonFollowCamera Tests
    
    @Test("ThirdPersonFollowCamera calculates position and look-at rotation")
    @MainActor
    func cameraPositionAndRotation() {
        let world = World()
        let targetEntity = world.createEntity()
        world.addComponent(TransformComponent(position: SIMD3<Float>(0, 0, 0)), to: targetEntity)
        
        let cameraEntity = world.createEntity()
        world.addComponent(TransformComponent(), to: cameraEntity)
        
        let camera = ThirdPersonFollowCamera(
            entity: cameraEntity,
            target: targetEntity,
            distance: 80.0,
            pitch: 0.785,
            yaw: 0.0
        )
        camera.update(world: world)
        
        let camTransform = world.component(ofType: TransformComponent.self, for: cameraEntity)
        #expect(camTransform != nil)
        
        if let transform = camTransform {
            let expectedH = 80.0 * cos(Float(0.785))
            let expectedV = 80.0 * sin(Float(0.785))
            
            #expect(abs(transform.position.x - 0.0) < 1e-4)
            #expect(abs(transform.position.y - expectedV) < 1e-4)
            #expect(abs(transform.position.z - expectedH) < 1e-4)
            
            // Camera yaw looking at target at (0, 2, 0) from (0, expectedV, expectedH) faces -Z (yaw = pi)
            #expect(abs(abs(transform.rotation.y) - .pi) < 1e-4)
            // Camera pitch looking down should be positive
            #expect(transform.rotation.x > 0.5)
        }
    }
    
    @Test("Camera view projection projects left object to negative NDC X")
    @MainActor
    func cameraProjectionNDC() {
        let world = World()
        let target = world.createEntity()
        world.addComponent(TransformComponent(position: .zero), to: target)
        let cam = ThirdPersonFollowCamera.create(in: world, target: target, distance: 50.0, pitch: 0.75, yaw: 0.0)
        
        let viewMatrix = world.worldMatrix(for: cam.entity).inverse
        let cameraComp = world.component(ofType: CameraComponent.self, for: cam.entity)!
        let projMatrix = cameraComp.projectionMatrix()
        let vp = projMatrix * viewMatrix
        
        let leftPoint = vp * SIMD4<Float>(-5, 0, 0, 1)
        let rightPoint = vp * SIMD4<Float>(5, 0, 0, 1)
        
        let leftNDC_X = leftPoint.x / leftPoint.w
        let rightNDC_X = rightPoint.x / rightPoint.w
        
        #expect(leftNDC_X < 0)
        #expect(rightNDC_X > 0)
    }
    
    @Test("ThirdPersonFollowCamera followHeading smoothly interpolates yaw")
    @MainActor
    func cameraFollowHeading() {
        let world = World()
        let target = world.createEntity()
        let cameraEntity = world.createEntity()
        let camera = ThirdPersonFollowCamera(
            entity: cameraEntity,
            target: target,
            yaw: 0.0
        )
        
        // Follow target heading of 1.0 rad over 0.2s
        camera.followHeading(1.0, deltaTime: 0.2, lerpRate: 2.5)
        #expect(camera.yaw > 0.0)
        #expect(camera.yaw < 1.0)
        
        // After sufficient time, yaw reaches target heading
        for _ in 0..<10 {
            camera.followHeading(1.0, deltaTime: 0.5, lerpRate: 2.5)
        }
        #expect(abs(camera.yaw - 1.0) < 0.01)
    }
    
    @Test("ThirdPersonFollowCamera clamps distance and pitch")
    @MainActor
    func cameraClamping() {
        let world = World()
        let target = world.createEntity()
        let cameraEntity = world.createEntity()
        
        let camera = ThirdPersonFollowCamera(
            entity: cameraEntity,
            target: target,
            distance: 10.0, // under min 15.0
            pitch: 0.1,     // under min 0.2
            yaw: 0.0
        )
        
        #expect(camera.distance == 15.0)
        #expect(camera.pitch == 0.2)
        
        camera.distance = 1000.0
        #expect(camera.distance == 400.0)
        
        camera.pitch = 3.0
        #expect(camera.pitch == 1.4)
    }
    
    @Test("ThirdPersonFollowCamera zoom and orbit")
    @MainActor
    func cameraZoomAndOrbit() {
        let world = World()
        let target = world.createEntity()
        let cameraEntity = world.createEntity()
        
        let camera = ThirdPersonFollowCamera(
            entity: cameraEntity,
            target: target,
            distance: 80.0,
            pitch: 0.785,
            yaw: 0.0
        )
        
        // Zoom in by scale 2.0 -> distance becomes 40.0
        camera.zoom(scale: 2.0)
        #expect(abs(camera.distance - 40.0) < 1e-4)
        
        // Orbit yaw and pitch
        camera.orbit(deltaYaw: 0.5, deltaPitch: 0.2)
        #expect(abs(camera.yaw - 0.5) < 1e-4)
        #expect(abs(camera.pitch - 0.985) < 1e-4)
        
        // Reset behind heading
        camera.resetBehind(heading: -1.2)
        #expect(abs(camera.yaw - (-1.2)) < 1e-4)
        #expect(abs(camera.pitch - 0.785) < 1e-4)
    }

    // MARK: - GameHUDView Tests
    
    @Test("GameHUDView updates labels and speed presets correctly")
    @MainActor
    func gameHUDViewUpdates() {
        let hud = GameHUDView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        
        let testGPS = GPSCoordinate(latitude: 60.16992, longitude: 24.93841, altitude: 12.0)
        hud.updateGPS(testGPS)
        
        let testTile = TileCoordinate(zoom: 16, x: 37530, y: 18682)
        hud.updateTile(coordinate: testTile, loadedCount: 9)
        hud.updateLoadedTileCount(12)
        
        #expect(hud.currentSpeedPreset == .run)
        #expect(hud.currentSpeedPreset.speed == 10.0)
        
        let nextPreset = hud.currentSpeedPreset.next
        #expect(nextPreset == .drive)
        #expect(nextPreset.speed == 25.0)
        
        let wrapPreset = nextPreset.next
        #expect(wrapPreset == .walk)
        #expect(wrapPreset.speed == 4.0)
    }
    
    @Test("City presets contain five key world cities")
    func cityPresetsCountAndNames() {
        let cities = CityPreset.all
        #expect(cities.count == 5)
        let names = cities.map(\.name)
        #expect(names.contains("Helsinki"))
        #expect(names.contains("Munich"))
        #expect(names.contains("New York"))
        #expect(names.contains("San Francisco"))
        #expect(names.contains("Tokyo"))
    }
}
