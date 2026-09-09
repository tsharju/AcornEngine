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
    
    // MARK: - Camera Panning & Focus Tests
    
    @Test("ThirdPersonFollowCamera pan shifts focusPosition and detaches tracking")
    @MainActor
    func cameraPanShiftsFocusPosition() {
        let world = World()
        let target = world.createEntity()
        world.addComponent(TransformComponent(position: SIMD3<Float>(10, 0, 10)), to: target)
        let cameraEntity = world.createEntity()
        world.addComponent(TransformComponent(), to: cameraEntity)
        
        let camera = ThirdPersonFollowCamera(
            entity: cameraEntity,
            target: target,
            yaw: 0.0,
            focusPosition: SIMD3<Float>(10, 0, 10)
        )
        
        #expect(camera.isFollowingTarget == true)
        
        // Pan delta: right +5, forward +8 at yaw 0
        // When yaw is 0: camRight is +X (1,0,0), camForward is -Z (0,0,-1)
        camera.pan(deltaRight: 5.0, deltaForward: 8.0)
        
        #expect(camera.isFollowingTarget == false)
        #expect(camera.isInterpolatingToTarget == false)
        #expect(abs(camera.focusPosition.x - 15.0) < 1e-4)
        #expect(abs(camera.focusPosition.z - 2.0) < 1e-4) // 10 + 8 * (-1) = 2.0
    }
    
    @Test("ThirdPersonFollowCamera pan with deltaWorld shifts focusPosition directly")
    @MainActor
    func cameraPanDeltaWorld() {
        let world = World()
        let target = world.createEntity()
        let cameraEntity = world.createEntity()
        
        let camera = ThirdPersonFollowCamera(
            entity: cameraEntity,
            target: target,
            focusPosition: SIMD3<Float>(0, 0, 0)
        )
        
        camera.pan(deltaWorld: SIMD3<Float>(-20, 0, 35))
        #expect(camera.isFollowingTarget == false)
        #expect(camera.focusPosition == SIMD3<Float>(-20, 0, 35))
    }
    
    @Test("ThirdPersonFollowCamera focusOnTarget with animated false snaps immediately")
    @MainActor
    func cameraFocusOnTargetSnap() {
        let world = World()
        let target = world.createEntity()
        world.addComponent(TransformComponent(position: SIMD3<Float>(50, 0, -30)), to: target)
        let cameraEntity = world.createEntity()
        world.addComponent(TransformComponent(), to: cameraEntity)
        
        let camera = ThirdPersonFollowCamera(
            entity: cameraEntity,
            target: target,
            focusPosition: SIMD3<Float>(0, 0, 0)
        )
        camera.pan(deltaWorld: SIMD3<Float>(100, 0, 100))
        #expect(camera.isFollowingTarget == false)
        
        camera.focusOnTarget(animated: false)
        #expect(camera.isFollowingTarget == true)
        #expect(camera.isInterpolatingToTarget == false)
        
        camera.update(world: world)
        #expect(camera.focusPosition == SIMD3<Float>(50, 0, -30))
    }
    
    @Test("ThirdPersonFollowCamera focusOnTarget with animated true smoothly interpolates")
    @MainActor
    func cameraFocusOnTargetAnimated() {
        let world = World()
        let target = world.createEntity()
        world.addComponent(TransformComponent(position: SIMD3<Float>(100, 0, 0)), to: target)
        let cameraEntity = world.createEntity()
        world.addComponent(TransformComponent(), to: cameraEntity)
        
        let camera = ThirdPersonFollowCamera(
            entity: cameraEntity,
            target: target,
            focusPosition: SIMD3<Float>(0, 0, 0)
        )
        camera.focusInterpolationRate = 4.0
        camera.focusOnTarget(animated: true)
        #expect(camera.isFollowingTarget == true)
        #expect(camera.isInterpolatingToTarget == true)
        
        // Advance 1 frame (0.1s)
        camera.update(world: world, deltaTime: 0.1)
        #expect(camera.focusPosition.x > 10.0)
        #expect(camera.focusPosition.x < 100.0)
        #expect(camera.isInterpolatingToTarget == true)
        
        // Advance many frames to complete transition
        for _ in 0..<30 {
            camera.update(world: world, deltaTime: 0.1)
        }
        #expect(abs(camera.focusPosition.x - 100.0) < 0.05)
        #expect(camera.isInterpolatingToTarget == false)
    }
    
    @Test("ThirdPersonFollowCamera ignores followHeading when panned")
    @MainActor
    func cameraFollowHeadingIgnoredWhenPanned() {
        let world = World()
        let target = world.createEntity()
        let cameraEntity = world.createEntity()
        
        let camera = ThirdPersonFollowCamera(
            entity: cameraEntity,
            target: target,
            yaw: 0.0
        )
        
        camera.pan(deltaRight: 10, deltaForward: 10)
        #expect(camera.isFollowingTarget == false)
        
        // Attempt follow heading while panned
        camera.followHeading(1.5, deltaTime: 0.5, lerpRate: 5.0)
        #expect(camera.yaw == 0.0) // Must remain unaffected!
    }

    @Test("GameHUDView focusButton updates state and triggers callback")
    @MainActor
    func gameHUDFocusButtonStateAndCallback() {
        let hud = GameHUDView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        var focusCallbackCount = 0
        hud.onFocusPlayer = {
            focusCallbackCount += 1
        }
        
        // Initial state: following player
        #expect(hud.isFollowingPlayer == true)
        #expect(hud.focusButton.title(for: .normal) == "📍 Focused")
        
        // Set to detached/panned state
        hud.setFocusState(isFollowingPlayer: false)
        #expect(hud.isFollowingPlayer == false)
        #expect(hud.focusButton.title(for: .normal) == "📍 Focus Player")
        
        // Tap focus button
        hud.focusButton.sendActions(for: .touchUpInside)
        #expect(focusCallbackCount == 1)
        
        // Set back to focused
        hud.setFocusState(isFollowingPlayer: true)
        #expect(hud.isFollowingPlayer == true)
        #expect(hud.focusButton.title(for: .normal) == "📍 Focused")
    }

    @Test("Camera panning momentum velocity decelerates smoothly to zero")
    @MainActor
    func cameraPanningMomentumDeceleration() {
        let world = World()
        let target = world.createEntity()
        let cameraEntity = world.createEntity()
        let camera = ThirdPersonFollowCamera(
            entity: cameraEntity,
            target: target,
            yaw: 0.0,
            focusPosition: .zero
        )
        
        var velocity = SIMD2<Float>(50.0, -30.0)
        let friction: Float = 4.5
        let dt = 0.016
        
        var totalDistanceTraveled: Float = 0
        while simd_length(velocity) >= 0.1 {
            let step = velocity * Float(dt)
            totalDistanceTraveled += simd_length(step)
            camera.pan(deltaRight: step.x, deltaForward: step.y)
            let decay = exp(-friction * Float(dt))
            velocity *= decay
        }
        
        #expect(simd_length(velocity) < 0.1)
        #expect(totalDistanceTraveled > 10.0)
        #expect(camera.isFollowingTarget == false)
    }
}
