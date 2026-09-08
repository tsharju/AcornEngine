import UIKit
import MetalKit
import AcornEngine
import AcornMath

/// The primary view controller for the 3D Location-Based Map Game.
///
/// Manages the AcornEngine instance, Metal rendering pipeline, real-time Mapbox 3D vector tile
/// streaming via `MapTileSystem` and `MapboxTileService`, 3D player character locomotion,
/// third-person follow camera, and interactive on-screen HUD controls.
class GameViewController: UIViewController, MTKViewDelegate {
    // MARK: - Engine & Rendering
    
    private var engine: Engine!
    private var renderer: MetalRenderer!
    private var postProcess: PostApocalypticPostProcess?
    private var commandQueue: MTLCommandQueue!
    private var lastRenderTime: CFTimeInterval = 0
    
    // MARK: - Map & Location Systems
    
    private var mapTileSystem: MapTileSystem!
    private let mapboxService = MapboxTileService()
    private var locationService: LocationService!
    
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
    private var lastPanTranslation: CGPoint = .zero
    private var isCameraPanning: Bool = false
    
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
        self.commandQueue = queue
        
        do {
            self.renderer = try MetalRenderer(device: defaultDevice)
            self.postProcess = PostApocalypticPostProcess(device: defaultDevice, pixelFormat: mtkView.colorPixelFormat)
            self.engine = Engine(renderer: self.renderer)
            
            // Register engine systems
            self.engine.world.registerSystem(CameraSystem())
            
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
        
        // 1. Configure MapTileSystem with zoom 15 for 3D building extrusions
        let tileSystem = MapTileSystem(
            initialReference: initialGPS,
            zoomLevel: 15,
            loadRadius: 1,
            recenterThresholdMeters: 4000.0,
            renderer: self.renderer
        )
        
        // Wire tile data provider directly to live Mapbox Streets v8 API
        tileSystem.tileDataProvider = { [weak self] coord in
            guard let self = self else { return nil }
            return try await self.mapboxService.fetchTileData(coordinate: coord)
        }
        
        self.mapTileSystem = tileSystem
        
        // 2. Spawn Player Character at the origin
        self.playerCharacter = PlayerCharacter.create(
            in: engine.world,
            renderer: self.renderer,
            initialGPS: initialGPS,
            referenceGPS: initialGPS
        )
        
        // 3. Spawn Third-Person Follow Camera
        self.followCamera = ThirdPersonFollowCamera.create(
            in: engine.world,
            target: playerCharacter.entity,
            distance: 42.0,
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
            Vertex(position: SIMD3<Float>( groundHalfSize, -0.5, -groundHalfSize), color: groundColor, texCoord: .zero, normal: upNormal),
            Vertex(position: SIMD3<Float>( groundHalfSize, -0.5,  groundHalfSize), color: groundColor, texCoord: .zero, normal: upNormal),
            
            Vertex(position: SIMD3<Float>(-groundHalfSize, -0.5, -groundHalfSize), color: groundColor, texCoord: .zero, normal: upNormal),
            Vertex(position: SIMD3<Float>( groundHalfSize, -0.5,  groundHalfSize), color: groundColor, texCoord: .zero, normal: upNormal),
            Vertex(position: SIMD3<Float>(-groundHalfSize, -0.5,  groundHalfSize), color: groundColor, texCoord: .zero, normal: upNormal)
        ]
        
        if let groundMesh = renderer.createMesh(vertices: groundVertices) {
            engine.world.addComponent(MeshComponent(mesh: groundMesh), to: groundEntity)
            engine.world.addComponent(TransformComponent(position: .zero), to: groundEntity)
        }
        self.groundPlaneEntity = groundEntity
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
            hud.trailingAnchor.constraint(equalTo: view.trailingAnchor)
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
        
        hud.onRecenterCamera = { [weak self] in
            guard let self = self else { return }
            self.followCamera.resetBehind(heading: self.playerCharacter.heading)
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
        
        self.hudView = hud
    }
    
    private func setupGestureRecognizers() {
        // Pan gesture for camera orbit
        let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleCameraPan(_:)))
        panRecognizer.maximumNumberOfTouches = 1
        view.addGestureRecognizer(panRecognizer)
        
        // Pinch gesture for camera zoom
        let pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handleCameraPinch(_:)))
        view.addGestureRecognizer(pinchRecognizer)
    }
    
    private func setupLocationTracking() {
        locationService = LocationService(defaultCoordinate: LocationService.defaultSenateSquare)
        
        locationService.onLocationUpdated = { [weak self] newGPS in
            guard let self = self else { return }
            if self.isManualCitySelected { return }
            
            let dist = self.distanceInMeters(from: self.mapTileSystem.referenceCoordinate, to: newGPS)
            if self.isFirstLocationUpdate || dist > 500.0 {
                self.isFirstLocationUpdate = false
                self.teleport(to: newGPS)
            } else {
                self.playerCharacter.setGPSCoordinate(
                    newGPS,
                    referenceGPS: self.mapTileSystem.referenceCoordinate,
                    world: self.engine.world
                )
            }
        }
    }
    
    // MARK: - Teleportation & Coordinate Conversion
    
    private func teleport(to targetGPS: GPSCoordinate) {
        mapTileSystem.recenterOrigin(to: targetGPS, world: engine.world)
        playerCharacter.setGPSCoordinate(
            targetGPS,
            referenceGPS: mapTileSystem.referenceCoordinate,
            world: engine.world
        )
        followCamera.resetBehind(heading: playerCharacter.heading)
        followCamera.update(world: engine.world)
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
    
    @objc private func handleCameraPan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: view)
        
        switch recognizer.state {
        case .began:
            isCameraPanning = true
            lastPanTranslation = translation
        case .changed:
            isCameraPanning = true
            let dx = Float(translation.x - lastPanTranslation.x)
            let dy = Float(translation.y - lastPanTranslation.y)
            lastPanTranslation = translation
            
            let sensitivity: Float = 0.006
            followCamera.orbit(deltaYaw: -dx * sensitivity, deltaPitch: -dy * sensitivity)
        case .ended, .cancelled:
            isCameraPanning = false
            lastPanTranslation = .zero
        default:
            break
        }
    }
    
    @objc private func handleCameraPinch(_ recognizer: UIPinchGestureRecognizer) {
        if recognizer.state == .changed {
            let scale = Float(recognizer.scale)
            followCamera.zoom(scale: scale)
            recognizer.scale = 1.0
        }
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
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
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
              let commandBuffer = commandQueue.makeCommandBuffer() else {
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
            referenceGPS: mapTileSystem.referenceCoordinate
        )
        playerCharacter.updateWorld(world: engine.world)
        
        // 3. Update third-person follow camera (smoothly follow movement direction with lerp)
        if !isCameraPanning && (abs(activeInput.x) > 0.05 || abs(activeInput.y) > 0.05) {
            followCamera.followHeading(playerCharacter.heading, deltaTime: deltaTime, lerpRate: 2.2)
        }
        followCamera.update(world: engine.world)
        
        // 4. Update MapTileSystem with player's GPS position
        mapTileSystem.cameraCoordinate = playerCharacter.currentGPS
        
        let distFromRef = distanceInMeters(from: mapTileSystem.referenceCoordinate, to: playerCharacter.currentGPS)
        if distFromRef > 2000.0 {
            teleport(to: playerCharacter.currentGPS)
        }
        
        mapTileSystem.update(world: engine.world, deltaTime: deltaTime)
        
        // 5. Tick engine ECS systems
        engine.tick(deltaTime: deltaTime)
        
        // 6. Update HUD metrics
        let currentTile = TileCoordinate(coordinate: playerCharacter.currentGPS, zoom: mapTileSystem.zoomLevel)
        hudView.updateGPS(playerCharacter.currentGPS)
        hudView.updateTile(coordinate: currentTile, loadedCount: mapTileSystem.activeTileEntities.count)
        
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
