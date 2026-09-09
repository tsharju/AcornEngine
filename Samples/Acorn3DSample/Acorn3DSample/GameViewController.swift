import AcornEngine
import AcornMath
import MetalKit
import UIKit

/// The primary view controller for the 3D Location-Based Map Game.
///
/// Manages the AcornEngine instance, Metal rendering pipeline, real-time Mapbox 3D vector tile
/// streaming via `MapTileSystem` and `MapboxTileService`, 3D player character locomotion,
/// third-person follow camera, and interactive on-screen HUD controls.
class GameViewController: UIViewController, MTKViewDelegate, UIGestureRecognizerDelegate {
    // MARK: - Engine & Rendering

    private var engine: Engine!
    private var renderer: MetalRenderer!
    private var postProcess: PostApocalypticPostProcess?
    private var commandQueue: MTLCommandQueue!
    private var lastRenderTime: CFTimeInterval = 0

    // MARK: - Map & Location Systems

    private var h3MapTileSystem: H3MapTileSystem!
    private var classicMapTileSystem: MapTileSystem!
    private var currentTileMode: MapTileMode = .h3Hexagonal
    private let mapboxService = MapboxTileService()
    private var locationService: LocationService!

    private var activeReferenceCoordinate: GPSCoordinate {
        currentTileMode == .h3Hexagonal ? h3MapTileSystem.referenceCoordinate : classicMapTileSystem.referenceCoordinate
    }

    // MARK: - Gameplay & Camera

    private var playerCharacter: PlayerCharacter!
    private var followCamera: ThirdPersonFollowCamera!
    private var hudView: GameHUDView!

    // Ground plane entity for base horizon
    private var groundPlaneEntity: Entity?

    // Input state
    private var currentJoystickInput: SIMD2<Float> = .zero
    private var keyMovementInput: SIMD2<Float> = .zero

    // Camera gesture state
    private var lastMapPanTranslation: CGPoint = .zero
    private var lastOrbitTranslation: CGPoint = .zero
    private var isCameraPanning: Bool = false
    private var panMomentumVelocity: SIMD2<Float> = .zero

    // GPS tracking state
    private var isFirstLocationUpdate: Bool = true
    private var isManualCitySelected: Bool = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = view as? MTKView else {
            print("GameViewController: View is not an MTKView")
            return
        }

        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("GameViewController: Metal is not supported on this device")
            return
        }

        mtkView.device = defaultDevice
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.depthStencilPixelFormat = .depth32Float
        // Atmospheric post-apocalyptic sky clear color
        mtkView.clearColor = MTLClearColor(red: 0.30, green: 0.34, blue: 0.32, alpha: 1.0)

        guard let queue = defaultDevice.makeCommandQueue() else {
            print("GameViewController: Failed to create MTLCommandQueue")
            return
        }
        commandQueue = queue

        do {
            renderer = try MetalRenderer(device: defaultDevice)
            postProcess = PostApocalypticPostProcess(device: defaultDevice, pixelFormat: mtkView.colorPixelFormat)
            postProcess?.uniforms.isEnabled = 0.0
            engine = Engine(renderer: renderer)

            // Register engine systems
            engine.world.registerSystem(CameraSystem())

            mtkView.delegate = self

            setupGameScene()
            setupHUD()
            setupGestureRecognizers()
            setupLocationTracking()

            // Set initial aspect ratio and post-process texture sizes
            self.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        } catch {
            print("GameViewController: Failed to initialize MetalRenderer: \(error)")
        }
    }

    // MARK: - Scene Setup

    private func setupGameScene() {
        let initialGPS = LocationService.defaultSenateSquare

        // 1a. Configure H3MapTileSystem with resolution 8 (edge ~461m) and zoom 15 source tiles
        let h3System = H3MapTileSystem(
            initialReference: initialGPS,
            h3Resolution: 8,
            sourceZoomLevel: 15,
            loadRingRadius: 1,
            recenterThresholdMeters: 4000.0,
            renderer: renderer,
            showsCellBoundaries: true
        )
        h3System.tileDataProvider = { [weak self] coord in
            guard let self = self else { return nil }
            return try await self.mapboxService.fetchTileData(coordinate: coord)
        }
        h3MapTileSystem = h3System

        // 1b. Configure classic MapTileSystem as optional fallback/comparison mode
        let classicSystem = MapTileSystem(
            initialReference: initialGPS,
            zoomLevel: 15,
            loadRadius: 1,
            recenterThresholdMeters: 4000.0,
            renderer: renderer
        )
        classicSystem.tileDataProvider = { [weak self] coord in
            guard let self = self else { return nil }
            return try await self.mapboxService.fetchTileData(coordinate: coord)
        }
        classicMapTileSystem = classicSystem

        // 2. Spawn Player Character at Initial GPS
        playerCharacter = PlayerCharacter.create(
            in: engine.world,
            renderer: renderer,
            initialGPS: initialGPS,
            referenceGPS: initialGPS
        )

        // 3. Spawn Third-Person Follow Camera
        followCamera = ThirdPersonFollowCamera.create(
            in: engine.world,
            target: playerCharacter.entity,
            distance: 140.0,
            pitch: 0.75, // ~43 degrees
            yaw: 0.0
        )

        // 4. Setup Lighting
        setupLighting()

        // 5. Setup Ground Horizon Plane
        setupGroundPlane()
    }

    private func setupLighting() {
        // Ambient Light: moody cool overcast skylight
        let ambientEntity = engine.world.createEntity()
        let ambientLight = LightComponent(
            type: .ambient,
            color: SIMD3<Float>(0.65, 0.70, 0.66),
            intensity: 0.50
        )
        engine.world.addComponent(ambientLight, to: ambientEntity)

        // Directional Sun Light: muted diffuse sunlight angled through overcast smog
        let sunEntity = engine.world.createEntity()
        let sunLight = LightComponent(
            type: .directional,
            color: SIMD3<Float>(0.90, 0.86, 0.78),
            intensity: 0.75
        )
        engine.world.addComponent(sunLight, to: sunEntity)

        var sunTransform = TransformComponent()
        sunTransform.rotation = SIMD3<Float>(-.pi / 4.0, -.pi / 3.5, 0)
        engine.world.addComponent(sunTransform, to: sunEntity)
    }

    private func setupGroundPlane() {
        let groundEntity = engine.world.createEntity()
        #if DEBUG
            engine.world.setName("HorizonGroundPlane", for: groundEntity)
        #endif

        let groundHalfSize: Float = 5000.0
        // Weathered overgrown wasteland earth
        let groundColor = SIMD4<Float>(0.42, 0.45, 0.39, 1.0)
        let upNormal = SIMD3<Float>(0, 1, 0)

        let groundVertices: [Vertex] = [
            Vertex(position: SIMD3<Float>(-groundHalfSize, -0.5, -groundHalfSize), color: groundColor, texCoord: .zero, normal: upNormal),
            Vertex(position: SIMD3<Float>(groundHalfSize, -0.5, -groundHalfSize), color: groundColor, texCoord: .zero, normal: upNormal),
            Vertex(position: SIMD3<Float>(groundHalfSize, -0.5, groundHalfSize), color: groundColor, texCoord: .zero, normal: upNormal),

            Vertex(position: SIMD3<Float>(-groundHalfSize, -0.5, -groundHalfSize), color: groundColor, texCoord: .zero, normal: upNormal),
            Vertex(position: SIMD3<Float>(groundHalfSize, -0.5, groundHalfSize), color: groundColor, texCoord: .zero, normal: upNormal),
            Vertex(position: SIMD3<Float>(-groundHalfSize, -0.5, groundHalfSize), color: groundColor, texCoord: .zero, normal: upNormal),
        ]

        if let groundMesh = renderer.createMesh(vertices: groundVertices) {
            engine.world.addComponent(MeshComponent(mesh: groundMesh), to: groundEntity)
            engine.world.addComponent(TransformComponent(position: .zero), to: groundEntity)
        }
        groundPlaneEntity = groundEntity
    }

    // MARK: - HUD & Controls Setup

    private func setupHUD() {
        let hud = GameHUDView(frame: view.bounds)
        hud.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hud)

        NSLayoutConstraint.activate([
            hud.topAnchor.constraint(equalTo: view.topAnchor),
            hud.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hud.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hud.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // Wire HUD Callbacks
        hud.onJoystickMoved = { [weak self] input in
            self?.currentJoystickInput = input
        }

        hud.onSpeedChanged = { [weak self] newSpeed in
            self?.playerCharacter.speed = newSpeed
        }

        hud.onCitySelected = { [weak self] cityGPS in
            guard let self = self else { return }
            self.isManualCitySelected = true
            self.teleport(to: cityGPS)
        }

        hud.onFocusPlayer = { [weak self] in
            guard let self = self else { return }
            self.panMomentumVelocity = .zero
            self.followCamera.focusOnTarget(animated: true)
        }

        hud.onRecenterCamera = { [weak self] in
            guard let self = self else { return }
            self.panMomentumVelocity = .zero
            self.followCamera.focusOnTarget(animated: false)
            self.followCamera.resetBehind(heading: self.playerCharacter.heading)
            self.hudView.setFocusState(isFollowingPlayer: true)
        }

        hud.onPostApocalypticToggled = { [weak self] isEnabled in
            self?.postProcess?.uniforms.isEnabled = isEnabled ? 1.0 : 0.0
        }

        hud.onMossDensityChanged = { [weak self] newDensity in
            self?.postProcess?.uniforms.mossDensity = newDensity
        }

        hud.onSSAOToggled = { [weak self] isEnabled in
            self?.postProcess?.uniforms.ssaoIntensity = isEnabled ? 1.25 : 0.0
        }

        hud.onTileModeToggled = { [weak self] newMode in
            self?.switchTileMode(to: newMode)
        }

        hud.onH3GridToggled = { [weak self] enabled in
            guard let self = self else { return }
            self.h3MapTileSystem.setShowsCellBoundaries(enabled, world: self.engine.world)
        }

        hudView = hud
    }

    private func switchTileMode(to newMode: MapTileMode) {
        guard newMode != currentTileMode else { return }
        currentTileMode = newMode
        let targetGPS = playerCharacter.currentGPS

        if newMode == .h3Hexagonal {
            classicMapTileSystem.recenterOrigin(to: targetGPS, world: engine.world)
            if distanceInMeters(from: h3MapTileSystem.referenceCoordinate, to: targetGPS) > 1000.0 {
                h3MapTileSystem.recenterOrigin(to: targetGPS, world: engine.world)
            }
        } else {
            h3MapTileSystem.clearActiveTiles(world: engine.world)
            if distanceInMeters(from: classicMapTileSystem.referenceCoordinate, to: targetGPS) > 1000.0 {
                classicMapTileSystem.recenterOrigin(to: targetGPS, world: engine.world)
            }
        }
    }

    private func setupGestureRecognizers() {
        // 1-finger pan gesture for panning the map
        let mapPanRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleMapPan(_:)))
        mapPanRecognizer.minimumNumberOfTouches = 1
        mapPanRecognizer.maximumNumberOfTouches = 1
        view.addGestureRecognizer(mapPanRecognizer)

        // 2-finger pan gesture for camera orbit and tilt
        let orbitPanRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleOrbitPan(_:)))
        orbitPanRecognizer.minimumNumberOfTouches = 2
        orbitPanRecognizer.maximumNumberOfTouches = 2
        view.addGestureRecognizer(orbitPanRecognizer)

        // Pinch gesture for camera zoom
        let pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handleCameraPinch(_:)))
        pinchRecognizer.delegate = self
        view.addGestureRecognizer(pinchRecognizer)

        // 2-finger rotation gesture for camera yaw
        let rotationRecognizer = UIRotationGestureRecognizer(target: self, action: #selector(handleCameraRotation(_:)))
        rotationRecognizer.delegate = self
        view.addGestureRecognizer(rotationRecognizer)
    }

    private func setupLocationTracking() {
        locationService = LocationService(defaultCoordinate: LocationService.defaultSenateSquare)

        locationService.onLocationUpdated = { [weak self] newGPS in
            guard let self = self else { return }
            if self.isManualCitySelected { return }

            let dist = self.distanceInMeters(from: self.activeReferenceCoordinate, to: newGPS)
            if self.isFirstLocationUpdate || dist > 500.0 {
                self.isFirstLocationUpdate = false
                self.teleport(to: newGPS)
            } else {
                self.playerCharacter.setGPSCoordinate(
                    newGPS,
                    referenceGPS: self.activeReferenceCoordinate,
                    world: self.engine.world
                )
            }
        }
    }

    // MARK: - Teleportation & Coordinate Conversion

    private func teleport(to targetGPS: GPSCoordinate) {
        panMomentumVelocity = .zero
        h3MapTileSystem.recenterOrigin(to: targetGPS, world: engine.world)
        classicMapTileSystem.recenterOrigin(to: targetGPS, world: engine.world)
        playerCharacter.setGPSCoordinate(
            targetGPS,
            referenceGPS: activeReferenceCoordinate,
            world: engine.world
        )
        followCamera.focusPosition = playerCharacter.worldPosition
        followCamera.focusOnTarget(animated: false)
        followCamera.resetBehind(heading: playerCharacter.heading)
        followCamera.update(world: engine.world)
        hudView.setFocusState(isFollowingPlayer: true)
    }

    private func distanceInMeters(from c1: GPSCoordinate, to c2: GPSCoordinate) -> Double {
        let lat1Rad = c1.latitude * .pi / 180.0
        let lat2Rad = c2.latitude * .pi / 180.0
        let dLat = lat2Rad - lat1Rad
        let dLon = (c2.longitude - c1.longitude) * .pi / 180.0

        let meanLat = (lat1Rad + lat2Rad) / 2.0
        let dx = dLon * TileCoordinate.earthEquatorialRadius * cos(meanLat)
        let dz = dLat * TileCoordinate.earthEquatorialRadius
        return sqrt(dx * dx + dz * dz)
    }

    // MARK: - Gesture Handling

    @objc private func handleMapPan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: view)

        switch recognizer.state {
        case .began:
            isCameraPanning = true
            panMomentumVelocity = .zero
            lastMapPanTranslation = translation
            hudView.setFocusState(isFollowingPlayer: false)
        case .changed:
            isCameraPanning = true
            let dx = Float(translation.x - lastMapPanTranslation.x)
            let dy = Float(translation.y - lastMapPanTranslation.y)
            lastMapPanTranslation = translation

            // Dynamic sensitivity: scale with camera distance so panning tracks 1:1 on ground
            let viewHeight = Float(max(view.bounds.height, 300.0))
            let sensitivity = (followCamera.distance / viewHeight) * 1.25

            // Drag right (+dx) moves map right -> camera focus moves left (-dx)
            // Drag down (+dy) moves map down (South) -> camera focus moves forward/North (+dy)
            followCamera.pan(
                deltaRight: -dx * sensitivity,
                deltaForward: dy * sensitivity
            )
            hudView.setFocusState(isFollowingPlayer: false)
        case .ended:
            isCameraPanning = false
            lastMapPanTranslation = .zero

            // Calculate flick / inertia velocity in ground space
            let touchVelocity = recognizer.velocity(in: view)
            let viewHeight = Float(max(view.bounds.height, 300.0))
            let sensitivity = (followCamera.distance / viewHeight) * 1.25

            let vRight = Float(-touchVelocity.x) * sensitivity
            let vForward = Float(touchVelocity.y) * sensitivity
            let speed = hypot(vRight, vForward)
            let maxSpeed: Float = 450.0
            if speed > maxSpeed {
                panMomentumVelocity = SIMD2<Float>(vRight * (maxSpeed / speed), vForward * (maxSpeed / speed))
            } else {
                panMomentumVelocity = SIMD2<Float>(vRight, vForward)
            }
        case .cancelled:
            isCameraPanning = false
            lastMapPanTranslation = .zero
            panMomentumVelocity = .zero
        default:
            break
        }
    }

    @objc private func handleOrbitPan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: view)

        switch recognizer.state {
        case .began:
            lastOrbitTranslation = translation
        case .changed:
            let dx = Float(translation.x - lastOrbitTranslation.x)
            let dy = Float(translation.y - lastOrbitTranslation.y)
            lastOrbitTranslation = translation

            let sensitivity: Float = 0.006
            followCamera.orbit(deltaYaw: -dx * sensitivity, deltaPitch: -dy * sensitivity)
        case .ended, .cancelled:
            lastOrbitTranslation = .zero
        default:
            break
        }
    }

    @objc private func handleCameraRotation(_ recognizer: UIRotationGestureRecognizer) {
        if recognizer.state == .changed {
            // Reversing delta sign so two-finger rotate turns the world synchronously with fingers
            let deltaYaw = Float(recognizer.rotation)
            followCamera.orbit(deltaYaw: deltaYaw, deltaPitch: 0)
            recognizer.rotation = 0
        }
    }

    @objc private func handleCameraPinch(_ recognizer: UIPinchGestureRecognizer) {
        if recognizer.state == .changed {
            let scale = Float(recognizer.scale)
            followCamera.zoom(scale: scale)
            recognizer.scale = 1.0
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Allow pinch and 2-finger rotation gestures to execute simultaneously
        if (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIRotationGestureRecognizer) ||
            (gestureRecognizer is UIRotationGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer)
        {
            return true
        }
        return false
    }

    // MARK: - Keyboard Controls (Simulator & Mac)

    override var canBecomeFirstResponder: Bool { true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key else { continue }
            switch key.keyCode {
            case .keyboardW, .keyboardUpArrow:
                keyMovementInput.y = 1.0
            case .keyboardS, .keyboardDownArrow:
                keyMovementInput.y = -1.0
            case .keyboardA, .keyboardLeftArrow:
                keyMovementInput.x = -1.0
            case .keyboardD, .keyboardRightArrow:
                keyMovementInput.x = 1.0
            case .keyboardF, .keyboardC:
                panMomentumVelocity = .zero
                followCamera.focusOnTarget(animated: true)
            default:
                break
            }
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key else { continue }
            switch key.keyCode {
            case .keyboardW, .keyboardUpArrow:
                if keyMovementInput.y > 0 { keyMovementInput.y = 0 }
            case .keyboardS, .keyboardDownArrow:
                if keyMovementInput.y < 0 { keyMovementInput.y = 0 }
            case .keyboardA, .keyboardLeftArrow:
                if keyMovementInput.x < 0 { keyMovementInput.x = 0 }
            case .keyboardD, .keyboardRightArrow:
                if keyMovementInput.x > 0 { keyMovementInput.x = 0 }
            default:
                break
            }
        }
        super.pressesEnded(presses, with: event)
    }

    // MARK: - MTKViewDelegate

    func mtkView(_: MTKView, drawableSizeWillChange size: CGSize) {
        guard let engine = engine else { return }
        let aspect = Float(max(size.width, 1.0) / max(size.height, 1.0))

        if let cameraTuple = engine.world.entities(with: CameraComponent.self).first {
            let entityId = cameraTuple.0
            var camera = cameraTuple.1
            camera.aspectRatio = aspect
            engine.world.addComponent(camera, to: entityId)
        }

        postProcess?.updateDrawableSize(size)
    }

    func draw(in view: MTKView) {
        guard let engine = engine,
              let commandQueue = commandQueue,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        let currentTime = CACurrentMediaTime()
        let deltaTime = lastRenderTime == 0 ? 0.016 : currentTime - lastRenderTime
        lastRenderTime = currentTime

        // 1. Combine touch joystick input and keyboard input
        var activeInput = currentJoystickInput
        if abs(keyMovementInput.x) > 0.001 || abs(keyMovementInput.y) > 0.001 {
            activeInput = keyMovementInput
        }

        // 2. Move player character relative to camera yaw
        playerCharacter.move(
            input: activeInput,
            cameraYaw: followCamera.yaw,
            deltaTime: deltaTime,
            referenceGPS: activeReferenceCoordinate
        )
        playerCharacter.updateWorld(world: engine.world)

        // 2b. Apply inertial panning momentum deceleration after finger lift
        if !isCameraPanning, abs(panMomentumVelocity.x) > 0.05 || abs(panMomentumVelocity.y) > 0.05 {
            followCamera.pan(
                deltaRight: panMomentumVelocity.x * Float(deltaTime),
                deltaForward: panMomentumVelocity.y * Float(deltaTime)
            )
            let decay = exp(-4.5 * Float(deltaTime))
            panMomentumVelocity *= decay
            if simd_length(panMomentumVelocity) < 0.1 {
                panMomentumVelocity = .zero
            }
        }

        // 3. Update third-person follow camera (smoothly follow movement direction with lerp)
        if !isCameraPanning, abs(activeInput.x) > 0.05 || abs(activeInput.y) > 0.05 {
            followCamera.followHeading(playerCharacter.heading, deltaTime: deltaTime, lerpRate: 2.2)
        }
        followCamera.update(world: engine.world, deltaTime: deltaTime)

        // Update HUD focus button state if camera has finished gliding back to target
        if followCamera.isFollowingTarget, !followCamera.isInterpolatingToTarget, !hudView.isFollowingPlayer {
            hudView.setFocusState(isFollowingPlayer: true)
        }

        // 4. Update tile system with camera focus GPS position
        let focusPos = followCamera.focusPosition
        let refGPS = activeReferenceCoordinate
        let latRad = refGPS.latitude * .pi / 180.0
        let cosLat = max(0.0001, cos(latRad))
        let deltaLon = Double(focusPos.x) / (TileCoordinate.earthEquatorialRadius * cosLat) * 180.0 / .pi
        let deltaLat = Double(-focusPos.z) / TileCoordinate.earthEquatorialRadius * 180.0 / .pi
        let focusGPS = GPSCoordinate(
            latitude: refGPS.latitude + deltaLat,
            longitude: refGPS.longitude + deltaLon,
            altitude: refGPS.altitude + Double(focusPos.y)
        )

        let distFromRef = distanceInMeters(from: activeReferenceCoordinate, to: playerCharacter.currentGPS)
        if distFromRef > 2000.0 {
            teleport(to: playerCharacter.currentGPS)
        }

        if currentTileMode == .h3Hexagonal {
            h3MapTileSystem.cameraCoordinate = focusGPS
            h3MapTileSystem.update(world: engine.world, deltaTime: deltaTime)
        } else {
            classicMapTileSystem.cameraCoordinate = focusGPS
            classicMapTileSystem.update(world: engine.world, deltaTime: deltaTime)
        }

        // 5. Tick engine ECS systems
        engine.tick(deltaTime: deltaTime)

        // 6. Update HUD metrics
        hudView.updateGPS(playerCharacter.currentGPS)
        if currentTileMode == .h3Hexagonal {
            let centerH3 = H3Index(coordinate: focusGPS, resolution: h3MapTileSystem.h3Resolution)
            let partsCount = h3MapTileSystem.totalGeometryPartCount(world: engine.world)
            hudView.updateH3(
                index: centerH3,
                activeHexes: h3MapTileSystem.activeH3Entities.count,
                loadedParts: partsCount,
                sourceTiles: h3MapTileSystem.sourceTileCache.count
            )
        } else {
            let currentTile = TileCoordinate(coordinate: focusGPS, zoom: classicMapTileSystem.zoomLevel)
            hudView.updateTile(coordinate: currentTile, loadedCount: classicMapTileSystem.activeTileEntities.count)
        }

        // 7. Render 3D scene (Pass 1: Offscreen Scene Pass & Pass 2: Post-Process Pass)
        let camPos = engine.world.component(ofType: TransformComponent.self, for: followCamera.entity)?.position ?? SIMD3<Float>(0, 30, 60)
        let camera = engine.world.component(ofType: CameraComponent.self, for: followCamera.entity) ?? CameraComponent(fovY: .pi / 3.0, nearZ: 0.5, farZ: 3000.0)
        let viewMatrix = engine.world.worldMatrix(for: followCamera.entity).inverse
        let projMatrix = camera.projectionMatrix()
        let viewProj = projMatrix * viewMatrix

        if let pp = postProcess, let sceneContext = pp.beginScenePass(commandBuffer: commandBuffer) {
            _ = sceneContext.getOrCreateEncoder()
            engine.render(context: sceneContext)
            sceneContext.endEncoding()

            // Pass 2: Fullscreen Post-Process Pass (Moss & Post-Apocalyptic Atmosphere)
            pp.renderPostProcess(
                commandBuffer: commandBuffer,
                destinationDescriptor: descriptor,
                viewProjectionMatrix: viewProj,
                cameraPosition: camPos,
                playerPosition: playerCharacter.worldPosition,
                deltaTime: deltaTime
            )
        } else {
            let context = MetalRenderContext(renderPassDescriptor: descriptor, commandBuffer: commandBuffer)
            _ = context.getOrCreateEncoder()
            engine.render(context: context)
            context.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
