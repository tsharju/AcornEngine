import Foundation
import Metal

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
        // Render mesh components
        let entities = world.entities(with: MeshComponent.self)
        for (entity, meshComponent) in entities {
            // Query for TransformComponent to fulfill the architecture plan,
            // even though the current ForwardRenderer doesn't use it yet.
            let transform = world.component(ofType: TransformComponent.self, for: entity)
            if transform != nil {
                renderer.render(mesh: meshComponent.mesh, context: context)
            }
        }
        
        // Render text components
        let textEntities = world.entities(with: TextComponent.self)
        for (entity, textComponent) in textEntities {
            guard world.component(ofType: TransformComponent.self, for: entity) != nil else {
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
                let uniforms = SDFUniforms(
                    textColor: currentComponent.textColor,
                    outlineColor: currentComponent.outlineColor,
                    outlineWidth: currentComponent.outlineWidth,
                    edgeWidth: currentComponent.edgeWidth
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
