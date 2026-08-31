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
    
    /// The system responsible for rendering meshes and sprites.
    public let renderSystem: RenderSystem
    
    /// The system responsible for audio playback and 3D spatial sound.
    public let audioSystem: AudioSystem
    
    /// The system responsible for 2D sprite flipbook animation.
    public let spriteAnimationSystem: SpriteAnimationSystem
    
    /// Initializes a new engine.
    /// - Parameters:
    ///   - renderer: The renderer.
    ///   - inputSystem: The input system (defaults to standard InputSystem).
    ///   - audioSystem: The audio system (defaults to standard AudioSystem).
    ///   - spriteAnimationSystem: The sprite animation system (defaults to standard SpriteAnimationSystem).
    public init(
        renderer: any Renderer,
        inputSystem: InputSystem = InputSystem(),
        audioSystem: AudioSystem = AudioSystem(),
        spriteAnimationSystem: SpriteAnimationSystem = SpriteAnimationSystem()
    ) {
        self.world = World()
        self.renderer = renderer
        self.inputSystem = inputSystem
        self.renderSystem = RenderSystem(renderer: self.renderer)
        self.audioSystem = audioSystem
        self.spriteAnimationSystem = spriteAnimationSystem
        
        self.world.registerSystem(self.inputSystem)
        self.world.registerSystem(self.spriteAnimationSystem)
        self.world.registerSystem(self.audioSystem)
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
