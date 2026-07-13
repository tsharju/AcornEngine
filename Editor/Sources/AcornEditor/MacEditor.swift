#if os(macOS)
import Cocoa
import Metal
import MetalKit
import ImGui
import AcornEngine
import UniformTypeIdentifiers

@MainActor
class EditorApplicationDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var view: MTKView!
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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device.makeCommandQueue()
        
        let rect = NSRect(x: 100, y: 100, width: 1280, height: 720)
        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered,
                          defer: false)
        window.title = "Acorn Editor"
        
        view = MTKView(frame: rect, device: device)
        view.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.delegate = self
        
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        
        setupImGui()
        do {
            renderer = try MetalRenderer(device: device, pixelFormat: view.colorPixelFormat)
        } catch {
            print("Failed to initialize MetalRenderer in editor: \(error)")
        }
        setupWorld()
    }
    
    func setupImGui() {
        ImGui.CreateContext(nil)
        ImGui_ImplOSX_Init(view)
        ImGui_ImplMetal_Init(device)
        
        let io = ImGui.GetIO()
        if let fonts = io.pointee.Fonts {
            let fm = FileManager.default
            var regularPath = Bundle.main.path(forResource: "JetBrainsMono-Regular", ofType: "ttf")
            var boldPath = Bundle.main.path(forResource: "JetBrainsMono-Bold", ofType: "ttf")
            
            // Fallback for command line run
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
    
    func importGLTF() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Import glTF / GLB Model"
        if let gltfType = UTType(filenameExtension: "gltf"),
           let glbType = UTType(filenameExtension: "glb") {
            openPanel.allowedContentTypes = [gltfType, glbType]
        } else {
            openPanel.allowedFileTypes = ["gltf", "glb"]
        }
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        
        openPanel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK, let url = openPanel.url {
                Task {
                    do {
                        let loader = GLTFModelLoader(device: self.device)
                        let loaded = try loader.load(from: url)
                        
                        var texture: (any Texture)? = nil
                        if let texData = loaded.textureData {
                            let textureLoader = TextureLoader(device: self.device)
                            texture = try await textureLoader.loadTexture(from: texData)
                        }
                        
                        await MainActor.run {
                            let modelName = url.deletingPathExtension().lastPathComponent
                            
                            // Calculate bounding box across all loaded meshes to auto-scale/center
                            var minPos = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
                            var maxPos = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
                            var hasVertices = false
                            
                            for mesh in loaded.meshes {
                                #if DEBUG
                                for vertex in mesh.vertices {
                                    minPos = simd_min(minPos, vertex.position)
                                    maxPos = simd_max(maxPos, vertex.position)
                                    hasVertices = true
                                }
                                #endif
                            }
                            
                            var targetScale = SIMD3<Float>(1, 1, 1)
                            var targetPosition = SIMD3<Float>(0, 0, 0)
                            
                            if hasVertices && minPos.x < maxPos.x {
                                let center = (minPos + maxPos) * 0.5
                                let size = maxPos - minPos
                                let maxDim = max(size.x, max(size.y, size.z))
                                if maxDim > 0 {
                                    // Normalize model size to a standard scale (e.g. 5.0 units)
                                    let targetSize: Float = 5.0
                                    let scaleFactor = targetSize / maxDim
                                    targetScale = SIMD3<Float>(repeating: scaleFactor)
                                    targetPosition = -center * scaleFactor
                                    print("Auto-scaled glTF model '\(modelName)' (bounds: \(size), maxDim: \(maxDim)) with factor \(scaleFactor) and center \(center)")
                                }
                            }
                            
                            var entities: [Entity] = []
                            entities.reserveCapacity(loaded.nodes.count)
                            
                            for node in loaded.nodes {
                                let entity = self.world.createEntity()
                                self.world.setName(node.name, for: entity)
                                
                                let localTransform = TransformComponent(
                                    position: node.translation,
                                    rotation: quaternionToEuler(node.rotation),
                                    scale: node.scale
                                )
                                self.world.addComponent(localTransform, to: entity)
                                
                                if let meshIdx = node.meshIndex, meshIdx < loaded.meshes.count {
                                    let meshComponent = MeshComponent(mesh: loaded.meshes[meshIdx], texture: texture)
                                    self.world.addComponent(meshComponent, to: entity)
                                }
                                
                                entities.append(entity)
                            }
                            
                            var rootEntities: [Entity] = []
                            for (index, node) in loaded.nodes.enumerated() {
                                if let parentIdx = node.parentIndex, parentIdx < entities.count {
                                    let childEntity = entities[index]
                                    let parentEntity = entities[parentIdx]
                                    self.world.addComponent(ParentComponent(parent: parentEntity), to: childEntity)
                                } else {
                                    rootEntities.append(entities[index])
                                }
                            }
                            
                            let modelRoot = self.world.createEntity()
                            self.world.setName(modelName, for: modelRoot)
                            self.world.addComponent(TransformComponent(position: targetPosition, scale: targetScale), to: modelRoot)
                            
                            for rootEntity in rootEntities {
                                self.world.addComponent(ParentComponent(parent: modelRoot), to: rootEntity)
                            }
                            
                            self.selectedEntity = modelRoot
                        }
                    } catch {
                        print("Failed to load glTF: \(error)")
                    }
                }
            }
        }
    }
}

extension EditorApplicationDelegate: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle resize if needed
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        ImGui_ImplMetal_NewFrame(descriptor)
        ImGui_ImplOSX_NewFrame(view)
        ImGui.NewFrame()
        // Clear the background
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.1, 0.1, 0.1, 1.0)
        descriptor.depthAttachment.clearDepth = 1.0
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.storeAction = .dontCare
        
        // Layout Constants
        let viewport = ImGui.GetMainViewport()
        let workPos = viewport != nil ? viewport!.pointee.WorkPos : ImVec2(0, 0)
        let workSize = viewport != nil ? viewport!.pointee.WorkSize : ImVec2(800, 600)
        
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
        ImGui.SameLine(0, -1.0)
        if ImGui.Button("Load glTF...", ImVec2(0, 0)) {
            importGLTF()
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
            
            let name = self.world.name(for: entity)
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
                // Use simd_inverse or transform.matrix.inverse. transform.matrix.inverse exists in simd
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
        
        // let cursorPos = ImGui.GetCursorScreenPos()
        let currentViewProj = viewProj
        
        #if DEBUG
        if renderWireframes, validCamera {
            let drawList = ImGui.GetWindowDrawList()!
            
            // The 3D scene is rendered to the full MTKView, so NDC maps to workSize, not winSize
            func project(_ pt: SIMD3<Float>) -> ImVec2? {
                let clip = currentViewProj * SIMD4<Float>(pt, 1.0)
                if clip.w <= 0.1 { return nil }
                let ndc = SIMD3<Float>(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w)
                let x = workPos.x + (ndc.x * 0.5 + 0.5) * workSize.x
                let y = workPos.y + (1.0 - (ndc.y * 0.5 + 0.5)) * workSize.y
                return ImVec2(x, y)
            }
            
            // Draw Grid on XZ plane using small segments to prevent culling the entire line
            let gridColor: UInt32 = 0x44AAAAAA // ABGR format, semi-transparent light gray
            let gridSize: Int = 100
            let gridStep: Float = 10.0
            let segStep: Float = 10.0 // segmentation length to prevent culling
            
            for i in stride(from: -gridSize, through: gridSize, by: Int(gridStep)) {
                let f = Float(i)
                
                // Lines along Z (constant X)
                var prevZ: ImVec2? = nil
                for j in stride(from: -gridSize, through: gridSize, by: Int(segStep)) {
                    let currZ = project(SIMD3<Float>(f, 0, Float(j)))
                    if let p1 = prevZ, let p2 = currZ { drawList.pointee.AddLine(p1, p2, gridColor, 1.0) }
                    prevZ = currZ
                }
                
                // Lines along X (constant Z)
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
                
                #if DEBUG
                if renderWireframes, let meshComp = world.component(ofType: MeshComponent.self, for: entity) {
                    let mesh = meshComp.mesh
                    let vertices = mesh.vertices
                    let wireColor: UInt32 = 0xFFCCCCCC // Light grey wireframe
                    
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
                #endif
                
                let oClip = mat * SIMD4<Float>(0, 0, 0, 1)
                let xClip = mat * SIMD4<Float>(5, 0, 0, 1)
                let yClip = mat * SIMD4<Float>(0, 5, 0, 1)
                let zClip = mat * SIMD4<Float>(0, 0, 5, 1)
                
                let origin = SIMD3<Float>(oClip.x, oClip.y, oClip.z)
                let xAxis = SIMD3<Float>(xClip.x, xClip.y, xClip.z)
                let yAxis = SIMD3<Float>(yClip.x, yClip.y, yClip.z)
                let zAxis = SIMD3<Float>(zClip.x, zClip.y, zClip.z)
                
                if let pOrigin = project(origin) {
                    // Draw X Axis (Red)
                    if let pX = project(xAxis) {
                        drawList.pointee.AddLine(pOrigin, pX, 0xFF0000FF, 2.0)
                    }
                    // Draw Y Axis (Green)
                    if let pY = project(yAxis) {
                        drawList.pointee.AddLine(pOrigin, pY, 0xFF00FF00, 2.0)
                    }
                    // Draw Z Axis (Blue)
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

@main
struct AcornEditorApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = EditorApplicationDelegate()
        app.delegate = delegate
        app.run()
    }
}
#endif
