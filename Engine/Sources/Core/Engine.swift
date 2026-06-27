import Foundation
import Metal

/// The core engine coordinator that manages the game loop, world, and rendering.
@MainActor
public class Engine {
    /// The ECS world.
    public let world: World
    
    /// The renderer.
    public let renderer: any Renderer
    
    /// The system responsible for rendering meshes.
    public let renderSystem: RenderSystem
    
    /// Initializes a new engine.
    /// - Parameter renderer: The renderer.
    public init(renderer: any Renderer) {
        self.world = World()
        self.renderer = renderer
        self.renderSystem = RenderSystem(renderer: self.renderer)
    }
    
    /// Ticks the engine, updating the world.
    /// - Parameter deltaTime: The time elapsed since the last tick.
    public func tick(deltaTime: Double) {
        world.update(deltaTime: deltaTime)
    }
    
    /// Renders the current state of the world.
    /// - Parameter context: The render context for the current frame.
    public func render(context: RenderContext) {
        renderSystem.render(world: world, context: context)
    }
}
