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
    public func render(world: World, context: RenderContext) {
        // Find active camera
        var viewProjectionMatrix = simd_float4x4.identity
        if let cameraEntity = world.entities(with: CameraComponent.self).first {
            let camera = cameraEntity.1
            if let transform = world.component(ofType: TransformComponent.self, for: cameraEntity.0) {
                let viewMatrix = transform.matrix.inverse
                let projectionMatrix = camera.projectionMatrix()
                viewProjectionMatrix = matrix_multiply(projectionMatrix, viewMatrix)
            }
        }
        
        // Render mesh components
        let entities = world.entities(with: MeshComponent.self)
        for (entity, meshComponent) in entities {
            if let transform = world.component(ofType: TransformComponent.self, for: entity) {
                let mvp = matrix_multiply(viewProjectionMatrix, transform.matrix)
                let uniforms = GlobalUniforms(modelViewProjectionMatrix: mvp)
                renderer.render(mesh: meshComponent.mesh, uniforms: uniforms, context: context)
            }
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
                
                let modelMatrix = simd_float4x4(
                    position: transform.position,
                    rotation: transform.rotation,
                    scale: finalScale
                )
                
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
        
        // Render sprite components
        let spriteEntities = world.entities(with: SpriteComponent.self)
        for (entity, spriteComponent) in spriteEntities {
            guard let transform = world.component(ofType: TransformComponent.self, for: entity) else {
                continue
            }
            
            var currentComponent = spriteComponent
            if currentComponent.mesh == nil || currentComponent.isDirty {
                let vertices = SpriteMeshGenerator.generateVertices(
                    for: currentComponent.frameName,
                    in: currentComponent.spriteSheet,
                    color: currentComponent.color
                )
                if let newMesh = renderer.createMesh(vertices: vertices) {
                    currentComponent.mesh = newMesh
                    currentComponent.isDirty = false
                    world.addComponent(currentComponent, to: entity)
                }
            }
            
            if let mesh = currentComponent.mesh {
                let modelMatrix = transform.matrix
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
        
        // Render tile map components
        let tileMapEntities = world.entities(with: TileMapComponent.self)
        for (entity, tileMapComponent) in tileMapEntities {
            guard let transform = world.component(ofType: TransformComponent.self, for: entity) else {
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
                let modelMatrix = transform.matrix
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
    }
}
