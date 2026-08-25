import Foundation
import Metal
import simd

/// A system that queries the world for renderable entities and submits them to the renderer.
@MainActor
public struct RenderSystem {
    /// The renderer used to draw entities.
    public let renderer: any Renderer
    
    /// Initializes a new render system.
    /// - Parameter renderer: The renderer.
    public init(renderer: any Renderer) {
        self.renderer = renderer
    }
    
    /// Renders all entities with a `MeshComponent` or `TextComponent`, along with a `TransformComponent`.
    /// - Parameters:
    ///   - world: The ECS world.
    ///   - context: The render context for the current frame.
    ///   - overrideViewProjection: Optional override for the camera matrix.
    public func render(world: World, context: RenderContext, overrideViewProjection: simd_float4x4? = nil) {
        // Find active camera
        var viewProjectionMatrix = simd_float4x4.identity
        
        if let override = overrideViewProjection {
            viewProjectionMatrix = override
        } else if let cameraEntity = world.entities(with: CameraComponent.self).first {
            let camera = cameraEntity.1
            if world.component(ofType: TransformComponent.self, for: cameraEntity.0) != nil {
                let viewMatrix = world.worldMatrix(for: cameraEntity.0).inverse
                let projectionMatrix = camera.projectionMatrix()
                viewProjectionMatrix = matrix_multiply(projectionMatrix, viewMatrix)
            }
        }
        
        // Find lights
        var ambientColor = SIMD4<Float>(0, 0, 0, 1)
        var directionalColor = SIMD4<Float>(0, 0, 0, 1)
        var directionalDirection = SIMD4<Float>(0, -1, 0, 0)
        var pointColor = SIMD4<Float>(0, 0, 0, 1)
        var pointPosition = SIMD4<Float>(0, 0, 0, 1)
        
        for (entity, light) in world.entities(with: LightComponent.self) {
            if light.type == .ambient {
                let c = light.color * light.intensity
                ambientColor = SIMD4<Float>(c.x, c.y, c.z, 1.0)
            } else if light.type == .directional {
                let c = light.color * light.intensity
                directionalColor = SIMD4<Float>(c.x, c.y, c.z, 1.0)
                if world.component(ofType: TransformComponent.self, for: entity) != nil {
                    let dir = world.worldMatrix(for: entity) * SIMD4<Float>(0, 0, -1, 0)
                    let len = simd_length(SIMD3<Float>(dir.x, dir.y, dir.z))
                    if len > 0.0001 {
                        directionalDirection = SIMD4<Float>(dir.x / len, dir.y / len, dir.z / len, 0)
                    }
                }
            } else if light.type == .point {
                let c = light.color * light.intensity
                pointColor = SIMD4<Float>(c.x, c.y, c.z, 1.0)
                if world.component(ofType: TransformComponent.self, for: entity) != nil {
                    let pos = world.worldMatrix(for: entity) * SIMD4<Float>(0, 0, 0, 1)
                    pointPosition = pos
                }
            }
        }
        
        let frameUniforms = FrameUniforms(
            viewProjectionMatrix: viewProjectionMatrix,
            ambientLightColor: ambientColor,
            directionalLightColor: directionalColor,
            directionalLightDirection: directionalDirection,
            pointLightColor: pointColor,
            pointLightPosition: pointPosition
        )
        
        // Render mesh components (batched instanced draw calls)
        let meshEntities = world.entities(with: MeshComponent.self)
        if !meshEntities.isEmpty {
            struct MeshBatchKey: Hashable {
                let meshID: ObjectIdentifier
                let textureID: ObjectIdentifier?
            }
            
            struct MeshBatch {
                let mesh: any Mesh
                let texture: (any Texture)?
                var instances: [MeshInstanceData]
            }
            
            var batches: [MeshBatchKey: MeshBatch] = [:]
            var batchOrder: [MeshBatchKey] = []
            
            for (entity, meshComponent) in meshEntities {
                guard world.component(ofType: TransformComponent.self, for: entity) != nil else {
                    continue
                }
                
                let modelMatrix = world.worldMatrix(for: entity)
                let normalMatrix = modelMatrix.inverse.transpose
                let instanceData = MeshInstanceData(
                    modelMatrix: modelMatrix,
                    normalMatrix: normalMatrix,
                    color: meshComponent.color
                )
                
                let meshKey = ObjectIdentifier(meshComponent.mesh as AnyObject)
                let textureKey = meshComponent.texture.map { ObjectIdentifier($0 as AnyObject) }
                let key = MeshBatchKey(meshID: meshKey, textureID: textureKey)
                
                if batches[key] == nil {
                    batchOrder.append(key)
                    batches[key] = MeshBatch(mesh: meshComponent.mesh, texture: meshComponent.texture, instances: [])
                }
                batches[key]?.instances.append(instanceData)
            }
            
            for key in batchOrder {
                if let batch = batches[key], !batch.instances.isEmpty {
                    renderer.renderInstanced(
                        mesh: batch.mesh,
                        texture: batch.texture,
                        instances: batch.instances,
                        uniforms: frameUniforms,
                        context: context
                    )
                }
            }
        }
        
        // Render tile map components
        let tileMapEntities = world.entities(with: TileMapComponent.self)
        for (entity, tileMapComponent) in tileMapEntities {
            guard world.component(ofType: TransformComponent.self, for: entity) != nil else {
                continue
            }
            
            var currentComponent = tileMapComponent
            if currentComponent.mesh == nil || currentComponent.isDirty {
                let vertices = SpriteMeshGenerator.generateVertices(for: currentComponent)
                if let newMesh = renderer.createMesh(vertices: vertices) {
                    currentComponent.mesh = newMesh
                    currentComponent.isDirty = false
                    world.addComponent(currentComponent, to: entity)
                }
            }
            
            if let mesh = currentComponent.mesh {
                let modelMatrix = world.worldMatrix(for: entity)
                let mvp = matrix_multiply(viewProjectionMatrix, modelMatrix)
                let uniforms = SpriteUniforms(modelViewProjectionMatrix: mvp, colorTint: SIMD4<Float>(1, 1, 1, 1))
                
                renderer.renderSprite(
                    mesh: mesh,
                    texture: currentComponent.spriteSheet.texture,
                    uniforms: uniforms,
                    context: context
                )
            }
        }
        
        // Render sprite components sorted by Z position (ascending, batched instanced draw calls)
        var spriteEntities = world.entities(with: SpriteComponent.self)
        if !spriteEntities.isEmpty, let unitQuadMesh = renderer.unitQuadMesh {
            spriteEntities.sort { a, b in
                let posA = world.component(ofType: TransformComponent.self, for: a.0)?.position.z ?? 0.0
                let posB = world.component(ofType: TransformComponent.self, for: b.0)?.position.z ?? 0.0
                return posA < posB
            }
            
            var currentTexture: (any Texture)? = nil
            var currentBatch: [SpriteInstanceData] = []
            let spriteUniforms = SpriteFrameUniforms(viewProjectionMatrix: viewProjectionMatrix)
            
            func flushSpriteBatch() {
                guard let texture = currentTexture, !currentBatch.isEmpty else { return }
                renderer.renderSpritesInstanced(
                    mesh: unitQuadMesh,
                    texture: texture,
                    instances: currentBatch,
                    uniforms: spriteUniforms,
                    context: context
                )
                currentBatch.removeAll(keepingCapacity: true)
            }
            
            for (entity, spriteComponent) in spriteEntities {
                guard world.component(ofType: TransformComponent.self, for: entity) != nil else {
                    continue
                }
                
                let texture = spriteComponent.spriteSheet.texture
                if let current = currentTexture {
                    if ObjectIdentifier(current as AnyObject) != ObjectIdentifier(texture as AnyObject) {
                        flushSpriteBatch()
                        currentTexture = texture
                    }
                } else {
                    currentTexture = texture
                }
                
                let frame = spriteComponent.spriteSheet.frame(named: spriteComponent.frameName)
                let width = Float(frame?.sourceSize.w ?? 1)
                let height = Float(frame?.sourceSize.h ?? 1)
                let sizeScale = simd_float4x4(diagonal: SIMD4<Float>(width, height, 1.0, 1.0))
                let modelMatrix = matrix_multiply(world.worldMatrix(for: entity), sizeScale)
                
                let uvRect = SpriteMeshGenerator.uvRect(for: spriteComponent.frameName, in: spriteComponent.spriteSheet)
                let instance = SpriteInstanceData(
                    modelMatrix: modelMatrix,
                    colorTint: spriteComponent.color,
                    uvRect: uvRect
                )
                currentBatch.append(instance)
            }
            
            flushSpriteBatch()
        }
        
        // Render text components
        let textEntities = world.entities(with: TextComponent.self)
        for (entity, textComponent) in textEntities {
            guard let transform = world.component(ofType: TransformComponent.self, for: entity) else {
                continue
            }
            
            var currentComponent = textComponent
            if currentComponent.mesh == nil || currentComponent.isDirty {
                let vertices = TextMeshGenerator.generateVertices(
                    for: currentComponent.text,
                    in: currentComponent.fontAtlas,
                    color: SIMD4<Float>(1, 1, 1, 1)
                )
                if let newMesh = renderer.createMesh(vertices: vertices) {
                    currentComponent.mesh = newMesh
                    currentComponent.isDirty = false
                    world.addComponent(currentComponent, to: entity)
                }
            }
            
            if let mesh = currentComponent.mesh {
                // Scale text down to a sensible size
                let baseScale: Float = 0.003
                let finalScale = transform.scale * SIMD3<Float>(repeating: baseScale)
                
                let localMatrix = simd_float4x4(
                    position: transform.position,
                    rotation: transform.rotation,
                    scale: finalScale
                )
                
                let parentMatrix: simd_float4x4
                if let parentComp = world.component(ofType: ParentComponent.self, for: entity) {
                    parentMatrix = world.worldMatrix(for: parentComp.parent)
                } else {
                    parentMatrix = .identity
                }
                
                let modelMatrix = matrix_multiply(parentMatrix, localMatrix)
                let mvp = matrix_multiply(viewProjectionMatrix, modelMatrix)
                
                let uniforms = SDFUniforms(
                    textColor: currentComponent.textColor,
                    outlineColor: currentComponent.outlineColor,
                    outlineWidth: currentComponent.outlineWidth,
                    edgeWidth: currentComponent.edgeWidth,
                    modelViewProjectionMatrix: mvp
                )
                renderer.renderText(
                    mesh: mesh,
                    texture: currentComponent.fontAtlas.texture,
                    uniforms: uniforms,
                    context: context
                )
            }
        }
    }
}
