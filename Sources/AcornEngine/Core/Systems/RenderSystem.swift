import Foundation
import Metal

/// A system that queries the world for renderable entities and submits them to the renderer.
@MainActor
public struct RenderSystem {
    /// The renderer used to draw entities.
    public let renderer: ForwardRenderer
    
    /// Initializes a new render system.
    /// - Parameter renderer: The forward renderer.
    public init(renderer: ForwardRenderer) {
        self.renderer = renderer
    }
    
    /// Renders all entities with a `MeshComponent` and a `TransformComponent`.
    /// - Parameters:
    ///   - world: The ECS world.
    ///   - renderPassDescriptor: The render pass descriptor.
    ///   - commandBuffer: The command buffer.
    public func render(world: World, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: any MTLCommandBuffer) {
        let entities = world.entities(with: MeshComponent.self)
        for (entity, meshComponent) in entities {
            // Query for TransformComponent to fulfill the architecture plan,
            // even though the current ForwardRenderer doesn't use it yet.
            let transform = world.component(ofType: TransformComponent.self, for: entity)
            if transform != nil {
                renderer.render(mesh: meshComponent.mesh, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
            }
        }
    }
}
