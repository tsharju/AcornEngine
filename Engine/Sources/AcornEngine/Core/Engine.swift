import Foundation
import Metal

/// The core engine coordinator that manages the game loop, world, and rendering.
@MainActor
public class Engine {
    /// The ECS world.
    public let world: World
    
    /// The renderer.
    public let renderer: any Renderer
    
    /// The system responsible for input handling.
    public let inputSystem: InputSystem
    
    /// The system responsible for rendering meshes.
    public let renderSystem: RenderSystem
    
    /// Initializes a new engine.
    /// - Parameters:
    ///   - renderer: The renderer.
    ///   - inputSystem: The input system (defaults to standard InputSystem).
    public init(renderer: any Renderer, inputSystem: InputSystem = InputSystem()) {
        self.world = World()
        self.renderer = renderer
        self.inputSystem = inputSystem
        self.renderSystem = RenderSystem(renderer: self.renderer)
        
        self.world.registerSystem(self.inputSystem)
    }
    
    /// Ticks the engine, updating the world.
    /// - Parameter deltaTime: The time elapsed since the last tick.
    public func tick(deltaTime: Double) {
        world.update(deltaTime: deltaTime)
        inputSystem.advanceFrame()
    }
    
    /// Renders the current state of the world.
    /// - Parameter context: The render context for the current frame.
    public func render(context: RenderContext) {
        renderSystem.render(world: world, context: context)
    }
}
