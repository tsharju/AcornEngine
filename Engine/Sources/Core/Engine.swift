import Foundation
import Metal

/// The core engine coordinator that manages the game loop, world, and rendering.
@MainActor
public class Engine {
    /// The ECS world.
    public let world: World
    
    /// The forward renderer.
    public let renderer: ForwardRenderer
    
    /// The system responsible for rendering meshes.
    public let renderSystem: RenderSystem
    
    /// Initializes a new engine.
    /// - Parameter device: The Metal device.
    /// - Throws: An error if the renderer cannot be initialized.
    public init(device: any MTLDevice) throws {
        self.world = World()
        self.renderer = try ForwardRenderer(device: device)
        self.renderSystem = RenderSystem(renderer: self.renderer)
    }
    
    /// Ticks the engine, updating the world.
    /// - Parameter deltaTime: The time elapsed since the last tick.
    public func tick(deltaTime: Double) {
        world.update(deltaTime: deltaTime)
    }
    
    /// Renders the current state of the world.
    /// - Parameters:
    ///   - renderPassDescriptor: The render pass descriptor.
    ///   - commandBuffer: The command buffer.
    public func render(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: any MTLCommandBuffer) {
        renderSystem.render(world: world, renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }
}
