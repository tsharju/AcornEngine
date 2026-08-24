import Foundation
import AcornEngine
import ImGui
import simd

@MainActor
protocol Inspectable {
    mutating func drawInspector(world: World, entity: Entity)
}

extension TransformComponent: Inspectable {
    public mutating func drawInspector(world: World, entity: Entity) {
        var pos: [Float] = [position.x, position.y, position.z]
        if ImGui.DragFloat3("Position", &pos, 0.1, 0, 0, "%.3f", 0) {
            position = SIMD3<Float>(pos[0], pos[1], pos[2])
            world.addComponent(self, to: entity)
        }
        
        var rot: [Float] = [rotation.x, rotation.y, rotation.z]
        if ImGui.DragFloat3("Rotation", &rot, 0.1, 0, 0, "%.3f", 0) {
            rotation = SIMD3<Float>(rot[0], rot[1], rot[2])
            world.addComponent(self, to: entity)
        }
        
        var scl: [Float] = [scale.x, scale.y, scale.z]
        if ImGui.DragFloat3("Scale", &scl, 0.1, 0, 0, "%.3f", 0) {
            scale = SIMD3<Float>(scl[0], scl[1], scl[2])
            world.addComponent(self, to: entity)
        }
    }
}

extension MeshComponent: Inspectable {
    public mutating func drawInspector(world: World, entity: Entity) {
        var col: [Float] = [color.x, color.y, color.z, color.w]
        if ImGui.ColorEdit4("Color", &col, 0) {
            color = SIMD4<Float>(col[0], col[1], col[2], col[3])
            world.addComponent(self, to: entity)
        }
    }
}

extension LightComponent: Inspectable {
    public mutating func drawInspector(world: World, entity: Entity) {
        var col: [Float] = [color.x, color.y, color.z]
        if ImGui.ColorEdit3("Color", &col, 0) {
            color = SIMD3<Float>(col[0], col[1], col[2])
            world.addComponent(self, to: entity)
        }
        var currentIntensity = intensity
        if ImGui.DragFloat("Intensity", &currentIntensity, 0.05, 0.0, 10.0, "%.2f", 0) {
            intensity = currentIntensity
            world.addComponent(self, to: entity)
        }
    }
}

extension CameraComponent: Inspectable {
    public mutating func drawInspector(world: World, entity: Entity) {
        var currentFov = fovY
        if ImGui.DragFloat("FOV (Y)", &currentFov, 0.1, 0.1, 3.14, "%.2f", 0) {
            fovY = currentFov
            world.addComponent(self, to: entity)
        }
        var currentNear = nearZ
        if ImGui.DragFloat("Near Z", &currentNear, 0.1, 0.01, 100.0, "%.2f", 0) {
            nearZ = currentNear
            world.addComponent(self, to: entity)
        }
        var currentFar = farZ
        if ImGui.DragFloat("Far Z", &currentFar, 1.0, 10.0, 10000.0, "%.1f", 0) {
            farZ = currentFar
            world.addComponent(self, to: entity)
        }
    }
}

extension CameraOrbitComponent: Inspectable {
    public mutating func drawInspector(world: World, entity: Entity) {
        var currentRadius = radius
        if ImGui.DragFloat("Radius", &currentRadius, 0.5, 0.1, 1000.0, "%.1f", 0) {
            radius = currentRadius
            world.addComponent(self, to: entity)
        }
        var currentSpeed = speed
        if ImGui.DragFloat("Speed", &currentSpeed, 0.1, -10.0, 10.0, "%.2f", 0) {
            speed = currentSpeed
            world.addComponent(self, to: entity)
        }
        var tgt: Int32 = Int32(target.id)
        if ImGui.DragInt("Target ID", &tgt, 1.0, 0, 1000, "%d", 0) {
            target = Entity(id: UInt64(max(0, tgt)))
            world.addComponent(self, to: entity)
        }
    }
}

extension CameraTrackingComponent: Inspectable {
    public mutating func drawInspector(world: World, entity: Entity) {
        var currentSmoothing = smoothing
        if ImGui.DragFloat("Smoothing", &currentSmoothing, 0.01, 0.0, 1.0, "%.2f", 0) {
            smoothing = currentSmoothing
            world.addComponent(self, to: entity)
        }
        var off: [Float] = [offset.x, offset.y, offset.z]
        if ImGui.DragFloat3("Offset", &off, 0.1, 0, 0, "%.1f", 0) {
            offset = SIMD3<Float>(off[0], off[1], off[2])
            world.addComponent(self, to: entity)
        }
    }
}

extension ParticleComponent: Inspectable {
    public mutating func drawInspector(world: World, entity: Entity) {
        ImGui.TextUnformatted("Lifetime: \(lifetime)", nil)
        ImGui.TextUnformatted("Age: \(age)", nil)
    }
}

extension ParticleEmitterComponent: Inspectable {
    public mutating func drawInspector(world: World, entity: Entity) {
        var rate = Float(emitRate)
        if ImGui.DragFloat("Emission Rate", &rate, 1.0, 0.0, 1000.0, "%.1f", 0) {
            emitRate = Double(rate)
            world.addComponent(self, to: entity)
        }
    }
}

extension SpriteComponent: Inspectable {
    public mutating func drawInspector(world: World, entity: Entity) {
        var col: [Float] = [color.x, color.y, color.z, color.w]
        if ImGui.ColorEdit4("Color", &col, 0) {
            color = SIMD4<Float>(col[0], col[1], col[2], col[3])
            world.addComponent(self, to: entity)
        }
        ImGui.TextUnformatted("Frame: \(frameName)", nil)
    }
}

extension TextComponent: Inspectable {
    public mutating func drawInspector(world: World, entity: Entity) {
        var col: [Float] = [textColor.x, textColor.y, textColor.z, textColor.w]
        if ImGui.ColorEdit4("Color", &col, 0) {
            textColor = SIMD4<Float>(col[0], col[1], col[2], col[3])
            world.addComponent(self, to: entity)
        }
    }
}

extension TileMapComponent: Inspectable {
    public mutating func drawInspector(world: World, entity: Entity) {
        var col: [Float] = [color.x, color.y, color.z, color.w]
        if ImGui.ColorEdit4("Color", &col, 0) {
            color = SIMD4<Float>(col[0], col[1], col[2], col[3])
            world.addComponent(self, to: entity)
        }
        ImGui.TextUnformatted("Columns: \(columns), Rows: \(rows)", nil)
    }
}

extension PhysicsBodyComponent: Inspectable {
    public mutating func drawInspector(world: World, entity: Entity) {
        var g = gravityScale
        if ImGui.DragFloat("Gravity Scale", &g, 0.1, -10.0, 10.0, "%.2f", 0) {
            gravityScale = g
            world.addComponent(self, to: entity)
        }
        var awake = isAwake
        if ImGui.Checkbox("Is Awake", &awake) {
            isAwake = awake
            world.addComponent(self, to: entity)
        }
    }
}

extension PhysicsColliderComponent: Inspectable {
    public mutating func drawInspector(world: World, entity: Entity) {
        var f = friction
        if ImGui.DragFloat("Friction", &f, 0.05, 0.0, 1.0, "%.2f", 0) {
            friction = f
            world.addComponent(self, to: entity)
        }
        var r = restitution
        if ImGui.DragFloat("Restitution", &r, 0.05, 0.0, 1.0, "%.2f", 0) {
            restitution = r
            world.addComponent(self, to: entity)
        }
    }
}

extension AudioSourceComponent: Inspectable {
    public mutating func drawInspector(world: World, entity: Entity) {
        var currentVolume = volume
        if ImGui.SliderFloat("Volume", &currentVolume, 0.0, 1.0, "%.2f", 0) {
            volume = currentVolume
            world.addComponent(self, to: entity)
        }
        
        var currentPitch = pitch
        if ImGui.SliderFloat("Pitch", &currentPitch, 0.5, 2.0, "%.2f", 0) {
            pitch = currentPitch
            world.addComponent(self, to: entity)
        }
        
        var looping = isLooping
        if ImGui.Checkbox("Is Looping", &looping) {
            isLooping = looping
            world.addComponent(self, to: entity)
        }
        
        var spatial = isSpatial
        if ImGui.Checkbox("Is Spatial", &spatial) {
            isSpatial = spatial
            world.addComponent(self, to: entity)
        }
        
        var awake = playOnAwake
        if ImGui.Checkbox("Play On Awake", &awake) {
            playOnAwake = awake
            world.addComponent(self, to: entity)
        }
        
        var currentReverb = reverbBlend
        if ImGui.SliderFloat("Reverb Blend", &currentReverb, 0.0, 1.0, "%.2f", 0) {
            reverbBlend = currentReverb
            world.addComponent(self, to: entity)
        }
        
        if ImGui.Button("Play", ImVec2(0, 0)) {
            play()
            world.addComponent(self, to: entity)
        }
        ImGui.SameLine(0, -1)
        if ImGui.Button("Pause", ImVec2(0, 0)) {
            pause()
            world.addComponent(self, to: entity)
        }
        ImGui.SameLine(0, -1)
        if ImGui.Button("Stop", ImVec2(0, 0)) {
            stop()
            world.addComponent(self, to: entity)
        }
    }
}

extension AudioListenerComponent: Inspectable {
    public mutating func drawInspector(world: World, entity: Entity) {
        var primary = isPrimary
        if ImGui.Checkbox("Is Primary", &primary) {
            isPrimary = primary
            world.addComponent(self, to: entity)
        }
        
        var master = masterVolume
        if ImGui.SliderFloat("Master Volume", &master, 0.0, 1.0, "%.2f", 0) {
            masterVolume = master
            world.addComponent(self, to: entity)
        }
    }
}

@MainActor
public func registerDefaultComponents() {
    ComponentRegistry.register(name: "AudioSource", type: AudioSourceComponent.self) {
        AudioSourceComponent()
    }
    
    ComponentRegistry.register(name: "AudioListener", type: AudioListenerComponent.self) {
        AudioListenerComponent()
    }
}

@MainActor
func registerAllComponents(renderer: MetalRenderer, dummySpriteSheet: SpriteSheet? = nil, defaultFont: FontAtlas? = nil) {
    ComponentRegistry.register(name: "Transform", type: TransformComponent.self) {
        TransformComponent()
    }
    
    ComponentRegistry.register(name: "Mesh", type: MeshComponent.self) {
        let vertices = BasicShapeGenerator.generateCube(size: SIMD3<Float>(1, 1, 1))
        let mesh = renderer.createMesh(vertices: vertices)!
        return MeshComponent(mesh: mesh)
    }
    
    ComponentRegistry.register(name: "Light", type: LightComponent.self) {
        LightComponent(type: .point, color: SIMD3<Float>(1, 1, 1), intensity: 1.0)
    }
    
    ComponentRegistry.register(name: "Camera", type: CameraComponent.self) {
        CameraComponent()
    }
    
    ComponentRegistry.register(name: "CameraOrbit", type: CameraOrbitComponent.self) {
        CameraOrbitComponent(target: Entity(id: 0), radius: 10, speed: 1.0)
    }
    
    ComponentRegistry.register(name: "CameraTracking", type: CameraTrackingComponent.self) {
        CameraTrackingComponent(target: Entity(id: 0), offset: SIMD3<Float>(0, 5, -10))
    }
    
    ComponentRegistry.register(name: "Particle", type: ParticleComponent.self) {
        ParticleComponent(lifetime: 1.0)
    }
    
    ComponentRegistry.register(name: "ParticleEmitter", type: ParticleEmitterComponent.self) {
        ParticleEmitterComponent(meshes: [])
    }
    
    ComponentRegistry.register(name: "PhysicsBody", type: PhysicsBodyComponent.self) {
        PhysicsBodyComponent()
    }
    
    ComponentRegistry.register(name: "PhysicsCollider", type: PhysicsColliderComponent.self) {
        PhysicsColliderComponent(shapeType: .box(width: 1, height: 1))
    }
    
    registerDefaultComponents()
    
    if let sheet = dummySpriteSheet {
        ComponentRegistry.register(name: "Sprite", type: SpriteComponent.self) {
            SpriteComponent(spriteSheet: sheet, frameName: "")
        }
        
        ComponentRegistry.register(name: "TileMap", type: TileMapComponent.self) {
            TileMapComponent(spriteSheet: sheet, columns: 1, rows: 1, tileSize: SIMD2<Float>(1, 1), tiles: [""])
        }
    }
    
    if let font = defaultFont {
        ComponentRegistry.register(name: "Text", type: TextComponent.self) {
            TextComponent(text: "Text", fontAtlas: font)
        }
    }
}
