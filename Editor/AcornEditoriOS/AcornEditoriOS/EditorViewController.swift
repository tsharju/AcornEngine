import UIKit
import Metal
import MetalKit
import ImGui
import AcornEngine
import simd

class EditorViewController: UIViewController {
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    
    // The engine's world instance
    var world: World!
    
    // Editor Camera State
    var editorCameraPos: [Float] = [0, 4, -25]
    var editorCameraPitch: Float = -10.0
    var editorCameraYaw: Float = 0.0
    var useSceneCamera: Bool = false
    
    // Editor State
    var selectedEntity: Entity?
    var boldFont: UnsafeMutablePointer<ImFont>? = nil
    
    // The Metal renderer
    var renderer: MetalRenderer!
    
    // Wireframe setting
    var renderWireframes: Bool = true
    
    // Track frame timing
    var lastRenderTime: CFTimeInterval = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let mtkView = view as? MTKView else {
            print("View of EditorViewController is not an MTKView")
            return
        }
        
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported")
            return
        }
        
        self.device = defaultDevice
        self.commandQueue = defaultDevice.makeCommandQueue()
        
        mtkView.device = defaultDevice
        mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.delegate = self
        
        setupImGui()
        do {
            renderer = try MetalRenderer(device: device, pixelFormat: mtkView.colorPixelFormat)
        } catch {
            print("Failed to initialize MetalRenderer in editor: \(error)")
        }
        setupWorld()
    }
    
    func setupImGui() {
        ImGui.CreateContext(nil)
        ImGui_ImplMetal_Init(device)
        
        let io = ImGui.GetIO()
        // Disable saving/loading of imgui.ini on iOS to avoid sandbox permission warnings
        io.pointee.IniFilename = nil
        
        if let fonts = io.pointee.Fonts {
            let fm = FileManager.default
            var regularPath = Bundle.main.path(forResource: "JetBrainsMono-Regular", ofType: "ttf")
            var boldPath = Bundle.main.path(forResource: "JetBrainsMono-Bold", ofType: "ttf")
            
            // Fallback
            if regularPath == nil || !fm.fileExists(atPath: regularPath!) {
                if fm.fileExists(atPath: "Fonts/JetBrainsMono-Regular.ttf") {
                    regularPath = "Fonts/JetBrainsMono-Regular.ttf"
                    boldPath = "Fonts/JetBrainsMono-Bold.ttf"
                } else if fm.fileExists(atPath: "Editor/Fonts/JetBrainsMono-Regular.ttf") {
                    regularPath = "Editor/Fonts/JetBrainsMono-Regular.ttf"
                    boldPath = "Editor/Fonts/JetBrainsMono-Bold.ttf"
                }
            }
            
            if let rPath = regularPath {
                rPath.withCString { cPath in
                    _ = ImGui_AddFontFromFileTTF(fonts, cPath, 14.0)
                }
            }
            if let bPath = boldPath {
                bPath.withCString { cPath in
                    boldFont = ImGui_AddFontFromFileTTF(fonts, cPath, 14.0)
                }
            }
        }
    }
    
    func setupWorld() {
        world = World()
        registerAllComponents(renderer: renderer)
        // Create some initial entities for testing
        let cubeEntity = world.createEntity()
        world.addComponent(TransformComponent(position: SIMD3<Float>(-5, 0, 0)), to: cubeEntity)
        let cubeVertices = BasicShapeGenerator.generateCube(size: SIMD3<Float>(4, 4, 4))
        if let mesh = renderer.createMesh(vertices: cubeVertices) {
            world.addComponent(MeshComponent(mesh: mesh), to: cubeEntity)
        }
        
        let sphereEntity = world.createEntity()
        world.addComponent(TransformComponent(position: SIMD3<Float>(5, 0, 0)), to: sphereEntity)
        let sphereVertices = BasicShapeGenerator.generateSphere(radius: 2.5)
        if let mesh = renderer.createMesh(vertices: sphereVertices) {
            world.addComponent(MeshComponent(mesh: mesh), to: sphereEntity)
        }
        
        // Add ambient light
        let ambientLight = world.createEntity()
        world.addComponent(LightComponent(type: .ambient, color: SIMD3<Float>(1, 1, 1), intensity: 0.2), to: ambientLight)
        
        // Add directional light
        let directionalLight = world.createEntity()
        world.addComponent(LightComponent(type: .directional, color: SIMD3<Float>(1, 1, 1), intensity: 0.5), to: directionalLight)
        var dirTransform = TransformComponent()
        dirTransform.rotation = SIMD3<Float>(-.pi / 4, -.pi / 4, 0)
        world.addComponent(dirTransform, to: directionalLight)
        
        // Add point light
        let pointLight = world.createEntity()
        world.addComponent(LightComponent(type: .point, color: SIMD3<Float>(1, 0, 0), intensity: 2.0), to: pointLight)
        var pointTransform = TransformComponent()
        pointTransform.position = SIMD3<Float>(0, 2, 0)
        world.addComponent(pointTransform, to: pointLight)
        
        selectedEntity = cubeEntity
    }
    
    // MARK: - Touch Handling for Dear ImGui
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateTouch(touches.first)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateTouch(touches.first)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let io = ImGui.GetIO()
        io.pointee.MouseDown.0 = false
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let io = ImGui.GetIO()
        io.pointee.MouseDown.0 = false
    }
    
    private func updateTouch(_ touch: UITouch?) {
        guard let touch = touch else { return }
        let loc = touch.location(in: view)
        let io = ImGui.GetIO()
        io.pointee.MousePos = ImVec2(Float(loc.x), Float(loc.y))
        io.pointee.MouseDown.0 = true
    }
}

extension EditorViewController: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle resize if needed
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        let currentTime = CACurrentMediaTime()
        let deltaTime = lastRenderTime == 0 ? 0.016 : currentTime - lastRenderTime
        lastRenderTime = currentTime
        
        // Update ImGui IO parameters for the frame
        let io = ImGui.GetIO()
        io.pointee.DisplaySize = ImVec2(Float(view.bounds.width), Float(view.bounds.height))
        let scale = Float(view.contentScaleFactor)
        io.pointee.DisplayFramebufferScale = ImVec2(scale, scale)
        io.pointee.DeltaTime = Float(deltaTime)
        
        ImGui_ImplMetal_NewFrame(descriptor)
        ImGui.NewFrame()
        
        // Clear the background
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.1, 0.1, 0.1, 1.0)
        descriptor.depthAttachment.clearDepth = 1.0
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.storeAction = .dontCare
        
        // Layout Constants
        let viewport = ImGui.GetMainViewport()
        var workPos = viewport != nil ? viewport!.pointee.WorkPos : ImVec2(0, 0)
        var workSize = viewport != nil ? viewport!.pointee.WorkSize : ImVec2(Float(view.bounds.width), Float(view.bounds.height))
        
        // Adjust for iOS Safe Area to avoid overlapping with status bar, notch, etc.
        let safeArea = view.safeAreaInsets
        let topInset = Float(safeArea.top)
        let bottomInset = Float(safeArea.bottom)
        let leftInset = Float(safeArea.left)
        let rightInset = Float(safeArea.right)
        
        workPos.x += leftInset
        workPos.y += topInset
        workSize.x -= (leftInset + rightInset)
        workSize.y -= (topInset + bottomInset)
        
        let leftWidth: Float = 300.0
        let leftHeight = workSize.y
        let sceneTreeHeight = leftHeight * 0.5
        let inspectorHeight = leftHeight - sceneTreeHeight
        
        let windowFlags: Int32 = 2 | 4 | 32 // NoResize | NoMove | NoCollapse
        
        // Draw Editor UI
        ImGui.SetNextWindowPos(workPos, 0, ImVec2(0, 0))
        ImGui.SetNextWindowSize(ImVec2(leftWidth, sceneTreeHeight), 0)
        ImGui.Begin("Scene Tree", nil, windowFlags)
        
        if ImGui.Button("Create Empty", ImVec2(0, 0)) {
            let newEntity = world.createEntity()
            world.addComponent(TransformComponent(), to: newEntity)
        }
        ImGui.SameLine(0, -1.0)
        if ImGui.Button("Create Shape...", ImVec2(0, 0)) {
            ImGui.OpenPopup("create_shape_popup", 0)
        }
        
        if ImGui.BeginPopup("create_shape_popup", 0) {
            if ImGui.MenuItem("Cube", nil, false, true) {
                let newEntity = world.createEntity()
                world.addComponent(TransformComponent(), to: newEntity)
                let vertices = BasicShapeGenerator.generateCube()
                if let mesh = renderer.createMesh(vertices: vertices) {
                    world.addComponent(MeshComponent(mesh: mesh), to: newEntity)
                }
            }
            if ImGui.MenuItem("Sphere", nil, false, true) {
                let newEntity = world.createEntity()
                world.addComponent(TransformComponent(), to: newEntity)
                let vertices = BasicShapeGenerator.generateSphere()
                if let mesh = renderer.createMesh(vertices: vertices) {
                    world.addComponent(MeshComponent(mesh: mesh), to: newEntity)
                }
            }
            if ImGui.MenuItem("Cylinder", nil, false, true) {
                let newEntity = world.createEntity()
                world.addComponent(TransformComponent(), to: newEntity)
                let vertices = BasicShapeGenerator.generateCylinder()
                if let mesh = renderer.createMesh(vertices: vertices) {
                    world.addComponent(MeshComponent(mesh: mesh), to: newEntity)
                }
            }
            if ImGui.MenuItem("Cone", nil, false, true) {
                let newEntity = world.createEntity()
                world.addComponent(TransformComponent(), to: newEntity)
                let vertices = BasicShapeGenerator.generateCone()
                if let mesh = renderer.createMesh(vertices: vertices) {
                    world.addComponent(MeshComponent(mesh: mesh), to: newEntity)
                }
            }
            if ImGui.MenuItem("Plane", nil, false, true) {
                let newEntity = world.createEntity()
                world.addComponent(TransformComponent(), to: newEntity)
                let vertices = BasicShapeGenerator.generatePlane()
                if let mesh = renderer.createMesh(vertices: vertices) {
                    world.addComponent(MeshComponent(mesh: mesh), to: newEntity)
                }
            }
            ImGui.EndPopup()
        }
        
        ImGui.Separator()
        
        struct TreeNodeFlags {
            static let none: Int32 = 0
            static let selected: Int32 = 1 << 0
            static let openOnArrow: Int32 = 1 << 7
            static let leaf: Int32 = 1 << 8
            static let spanAvailWidth: Int32 = 1 << 11
        }
        
        let allEntitiesList = world.allEntities; let entities = allEntitiesList
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
        
        rootEntities.sort(by: { $0.id < $1.id })
        for parent in childrenMap.keys {
            childrenMap[parent]?.sort(by: { $0.id < $1.id })
        }
        
        var drawEntityNode: ((Entity) -> Void)! = nil
        drawEntityNode = { entity in
            let isSelected = self.selectedEntity == entity
            if isSelected, let bold = self.boldFont {
                ImGui.PushFont(bold)
            }
            
            let name = world.name(for: entity)
            let children = childrenMap[entity] ?? []
            
            var flags = TreeNodeFlags.openOnArrow | TreeNodeFlags.spanAvailWidth
            if children.isEmpty {
                flags |= TreeNodeFlags.leaf
            }
            if isSelected {
                flags |= TreeNodeFlags.selected
            }
            
            let nodeOpen = "\(name)##\(entity.id)".withCString { cLabel in
                ImGui.TreeNodeEx(cLabel, flags)
            }
            
            if isSelected, self.boldFont != nil {
                ImGui.PopFont()
            }
            
            if ImGui.IsItemClicked(0) {
                self.selectedEntity = entity
            }
            
            if nodeOpen {
                for child in children {
                    drawEntityNode(child)
                }
                ImGui.TreePop()
            }
        }
        
        for rootEntity in rootEntities {
            drawEntityNode(rootEntity)
        }
        ImGui.End()
        
        ImGui.SetNextWindowPos(ImVec2(workPos.x, workPos.y + sceneTreeHeight), 0, ImVec2(0, 0))
        ImGui.SetNextWindowSize(ImVec2(leftWidth, inspectorHeight), 0)
        ImGui.Begin("Inspector", nil, windowFlags)
        if let selected = selectedEntity, entities.contains(selected) {
            var nameBuffer = [CChar](repeating: 0, count: 128)
            let currentName = world.name(for: selected)
            strncpy(&nameBuffer, currentName, nameBuffer.count - 1)
            
            let inputChanged = "Name".withCString { cLabel in
                ImGui.InputText(cLabel, &nameBuffer, nameBuffer.count, 0, nil, nil)
            }
            if inputChanged {
                let newName = nameBuffer.withUnsafeBufferPointer { ptr in
                    String(cString: ptr.baseAddress!)
                }.trimmingCharacters(in: .whitespacesAndNewlines)
                if !newName.isEmpty {
                    world.setName(newName, for: selected)
                }
            }
            ImGui.TextUnformatted("ID: \(selected.id)", nil)
            ImGui.Separator()
            
            let components = world.allComponents(for: selected)
            for component in components {
                if ImGui.TreeNode("\(type(of: component))") {
                    if var inspectable = component as? Inspectable {
                        inspectable.drawInspector(world: world, entity: selected)
                    } else {
                        ImGui.TextUnformatted("\(component)", nil)
                    }
                    ImGui.TreePop()
                }
            }
            
            ImGui.Separator()
            if ImGui.Button("Add Component", ImVec2(-1, 0)) {
                ImGui.OpenPopup("add_component_popup", 0)
            }
            if ImGui.BeginPopup("add_component_popup", 0) {
                for meta in ComponentRegistry.components {
                    if ImGui.MenuItem(meta.name, nil, false, true) {
                        let newComp = meta.factory()
                        // Implicitly opens existential to call generic addComponent
                        world.addComponent(newComp, to: selected)
                    }
                }
                ImGui.EndPopup()
            }
        } else {
            ImGui.TextUnformatted("No entity selected", nil)
        }
        ImGui.End()
        
        // World View Window
        ImGui.SetNextWindowPos(ImVec2(workPos.x + leftWidth, workPos.y), 0, ImVec2(0, 0))
        ImGui.SetNextWindowSize(ImVec2(workSize.x - leftWidth, workSize.y), 0)
        ImGui.SetNextWindowBgAlpha(0.0) // Transparent background to see rendered scene
        ImGui.Begin("World View", nil, windowFlags)
        
        ImGui.Checkbox("Use Scene Camera", &useSceneCamera)
        ImGui.SameLine(0, -1.0)
        ImGui.Checkbox("Render Wireframes", &renderWireframes)
        var viewProj = simd_float4x4()
        var validCamera = true
        
        if useSceneCamera {
            let cameraEntities = world.entities(with: CameraComponent.self)
            if let firstCam = cameraEntities.first,
               world.component(ofType: TransformComponent.self, for: firstCam.0) != nil {
                let camera = firstCam.1
                let view = world.worldMatrix(for: firstCam.0).inverse
                let proj = camera.projectionMatrix()
                viewProj = proj * view
                ImGui.TextUnformatted("Using Entity \(firstCam.0.id) as Scene Camera", nil)
            } else {
                ImGui.TextUnformatted("No CameraComponent found in scene.", nil)
                validCamera = false
            }
        } else {
            ImGui.DragFloat3("Position", &editorCameraPos, 0.5, 0, 0, "%.1f", 0)
            ImGui.DragFloat("Pitch", &editorCameraPitch, 1.0, -90.0, 90.0, "%.1f", 0)
            ImGui.DragFloat("Yaw", &editorCameraYaw, 1.0, -180.0, 180.0, "%.1f", 0)
            
            let fov: Float = 60.0 * .pi / 180.0
            let aspect: Float = workSize.y > 0 ? Float(workSize.x / workSize.y) : (16.0 / 9.0)
            let projection = simd_float4x4(perspectiveFovY: fov, aspect: aspect, nearZ: 0.1, farZ: 1000.0)
            let pitchR = editorCameraPitch * .pi / 180.0
            let yawR = editorCameraYaw * .pi / 180.0
            
            let pos = SIMD3<Float>(editorCameraPos[0], editorCameraPos[1], editorCameraPos[2])
            let rot = SIMD3<Float>(pitchR, yawR, 0)
            let transform = simd_float4x4(position: pos, rotation: rot, scale: SIMD3<Float>(1, 1, 1))
            let view = transform.inverse
            viewProj = projection * view
        }
        
        let currentViewProj = viewProj
        
        #if DEBUG
        if renderWireframes, validCamera {
            let drawList = ImGui.GetWindowDrawList()!
            
            func project(_ pt: SIMD3<Float>) -> ImVec2? {
                let clip = currentViewProj * SIMD4<Float>(pt, 1.0)
                if clip.w <= 0.1 { return nil }
                let ndc = SIMD3<Float>(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w)
                let x = workPos.x + (ndc.x * 0.5 + 0.5) * workSize.x
                let y = workPos.y + (1.0 - (ndc.y * 0.5 + 0.5)) * workSize.y
                return ImVec2(x, y)
            }
            
            // Draw Grid on XZ plane
            let gridColor: UInt32 = 0x44AAAAAA // ABGR format
            let gridSize: Int = 100
            let gridStep: Float = 10.0
            let segStep: Float = 10.0
            
            for i in stride(from: -gridSize, through: gridSize, by: Int(gridStep)) {
                let f = Float(i)
                
                // Lines along Z
                var prevZ: ImVec2? = nil
                for j in stride(from: -gridSize, through: gridSize, by: Int(segStep)) {
                    let currZ = project(SIMD3<Float>(f, 0, Float(j)))
                    if let p1 = prevZ, let p2 = currZ { drawList.pointee.AddLine(p1, p2, gridColor, 1.0) }
                    prevZ = currZ
                }
                
                // Lines along X
                var prevX: ImVec2? = nil
                for j in stride(from: -gridSize, through: gridSize, by: Int(segStep)) {
                    let currX = project(SIMD3<Float>(Float(j), 0, f))
                    if let p1 = prevX, let p2 = currX { drawList.pointee.AddLine(p1, p2, gridColor, 1.0) }
                    prevX = currX
                }
            }
            
            for entity in entities {
                guard world.component(ofType: TransformComponent.self, for: entity) != nil else { continue }
                let mat = world.worldMatrix(for: entity)
                
                if let meshComp = world.component(ofType: MeshComponent.self, for: entity) {
                    let mesh = meshComp.mesh
                    let vertices = mesh.vertices
                    let wireColor: UInt32 = 0xFFCCCCCC
                    
                    for i in stride(from: 0, to: vertices.count, by: 3) {
                        if i + 2 < vertices.count {
                            let v0 = vertices[i].position
                            let v1 = vertices[i + 1].position
                            let v2 = vertices[i + 2].position
                            
                            let w0 = mat * SIMD4<Float>(v0, 1.0)
                            let w1 = mat * SIMD4<Float>(v1, 1.0)
                            let w2 = mat * SIMD4<Float>(v2, 1.0)
                            
                            let p0 = project(SIMD3<Float>(w0.x, w0.y, w0.z))
                            let p1 = project(SIMD3<Float>(w1.x, w1.y, w1.z))
                            let p2 = project(SIMD3<Float>(w2.x, w2.y, w2.z))
                            
                            if let p0 = p0, let p1 = p1 {
                                drawList.pointee.AddLine(p0, p1, wireColor, 1.0)
                            }
                            if let p1 = p1, let p2 = p2 {
                                drawList.pointee.AddLine(p1, p2, wireColor, 1.0)
                            }
                            if let p2 = p2, let p0 = p0 {
                                drawList.pointee.AddLine(p2, p0, wireColor, 1.0)
                            }
                        }
                    }
                }
                
                let oClip = mat * SIMD4<Float>(0, 0, 0, 1)
                let xClip = mat * SIMD4<Float>(5, 0, 0, 1)
                let yClip = mat * SIMD4<Float>(0, 5, 0, 1)
                let zClip = mat * SIMD4<Float>(0, 0, 5, 1)
                
                let origin = SIMD3<Float>(oClip.x, oClip.y, oClip.z)
                let xAxis = SIMD3<Float>(xClip.x, xClip.y, xClip.z)
                let yAxis = SIMD3<Float>(yClip.x, yClip.y, yClip.z)
                let zAxis = SIMD3<Float>(zClip.x, zClip.y, zClip.z)
                
                if let pOrigin = project(origin) {
                    if let pX = project(xAxis) {
                        drawList.pointee.AddLine(pOrigin, pX, 0xFF0000FF, 2.0)
                    }
                    if let pY = project(yAxis) {
                        drawList.pointee.AddLine(pOrigin, pY, 0xFF00FF00, 2.0)
                    }
                    if let pZ = project(zAxis) {
                        drawList.pointee.AddLine(pOrigin, pZ, 0xFFFF0000, 2.0)
                    }
                }
            }
        }
        #endif
        ImGui.End()
        
        ImGui.Render()
        let drawData = ImGui.GetDrawData()
        
        let renderContext = MetalRenderContext(renderPassDescriptor: descriptor, commandBuffer: commandBuffer)
        let renderSystem = RenderSystem(renderer: renderer)
        renderSystem.render(world: world, context: renderContext, overrideViewProjection: viewProj)
        
        if let encoder = renderContext.getOrCreateEncoder() {
            ImGui_ImplMetal_RenderDrawData(drawData, commandBuffer, encoder)
            renderContext.endEncoding()
        }
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
