import Cocoa
import Metal
import MetalKit
import ImGui
import AcornEngine

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
            renderer = try MetalRenderer(device: device)
        } catch {
            print("Failed to initialize MetalRenderer in editor: \(error)")
        }
        setupWorld()
    }
    
    func setupImGui() {
        ImGui.CreateContext(nil)
        ImGui_ImplOSX_Init(view)
        ImGui_ImplMetal_Init(device)
    }
    
    func setupWorld() {
        world = World()
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
        
        let entities = world.allEntities.sorted(by: { $0.id < $1.id })
        for entity in entities {
            let nodeOpen = ImGui.TreeNode("Entity \(entity.id)")
            

            // To show selection without TreeNodeEx, we can just highlight text or use Selectable
            if selectedEntity == entity {
                ImGui.SameLine(0, -1.0)
                ImGui.TextUnformatted(" <-- Selected", nil)
            }
            
            if ImGui.IsItemClicked(0) {
                selectedEntity = entity
            }
            
            if nodeOpen {
                ImGui.TreePop()
            }
        }
        ImGui.End()
        
        ImGui.SetNextWindowPos(ImVec2(workPos.x, workPos.y + sceneTreeHeight), 0, ImVec2(0, 0))
        ImGui.SetNextWindowSize(ImVec2(leftWidth, inspectorHeight), 0)
        ImGui.Begin("Inspector", nil, windowFlags)
        if let selected = selectedEntity, entities.contains(selected) {
            ImGui.TextUnformatted("Entity \(selected.id)", nil)
            ImGui.Separator()
            
            let components = world.allComponents(for: selected)
            for component in components {
                if ImGui.TreeNode("\(type(of: component))") {
                    if var transform = component as? TransformComponent {
                        var pos: [Float] = [transform.position.x, transform.position.y, transform.position.z]
                        if ImGui.DragFloat3("Position", &pos, 0.1, 0, 0, "%.3f", 0) {
                            transform.position = SIMD3<Float>(pos[0], pos[1], pos[2])
                            world.addComponent(transform, to: selected)
                        }
                        
                        var rot: [Float] = [transform.rotation.x, transform.rotation.y, transform.rotation.z]
                        if ImGui.DragFloat3("Rotation", &rot, 0.1, 0, 0, "%.3f", 0) {
                            transform.rotation = SIMD3<Float>(rot[0], rot[1], rot[2])
                            world.addComponent(transform, to: selected)
                        }
                        
                        var scale: [Float] = [transform.scale.x, transform.scale.y, transform.scale.z]
                        if ImGui.DragFloat3("Scale", &scale, 0.1, 0, 0, "%.3f", 0) {
                            transform.scale = SIMD3<Float>(scale[0], scale[1], scale[2])
                            world.addComponent(transform, to: selected)
                        }
                    } else if var meshComp = component as? MeshComponent {
                        var col: [Float] = [meshComp.color.x, meshComp.color.y, meshComp.color.z, meshComp.color.w]
                        if ImGui.ColorEdit4("Color", &col, 0) {
                            meshComp.color = SIMD4<Float>(col[0], col[1], col[2], col[3])
                            world.addComponent(meshComp, to: selected)
                        }
                    } else if var lightComp = component as? LightComponent {
                        var col: [Float] = [lightComp.color.x, lightComp.color.y, lightComp.color.z]
                        if ImGui.ColorEdit3("Color", &col, 0) {
                            lightComp.color = SIMD3<Float>(col[0], col[1], col[2])
                            world.addComponent(lightComp, to: selected)
                        }
                        var intensity = lightComp.intensity
                        if ImGui.DragFloat("Intensity", &intensity, 0.05, 0.0, 10.0, "%.2f", 0) {
                            lightComp.intensity = intensity
                            world.addComponent(lightComp, to: selected)
                        }
                    } else {
                        // Fallback for components without custom editors
                        ImGui.TextUnformatted("\(component)", nil)
                    }
                    ImGui.TreePop()
                }
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
               let transform = world.component(ofType: TransformComponent.self, for: firstCam.0) {
                let camera = firstCam.1
                // Use simd_inverse or transform.matrix.inverse. transform.matrix.inverse exists in simd
                let view = transform.matrix.inverse
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
        
        let cursorPos = ImGui.GetCursorScreenPos()
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
                guard let transform = world.component(ofType: TransformComponent.self, for: entity) else { continue }
                let mat = transform.matrix
                
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

let app = NSApplication.shared
let delegate = EditorApplicationDelegate()
app.delegate = delegate
app.run()
