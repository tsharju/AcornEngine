import Foundation

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
    
    /// The maximum allowable delta time per tick, preventing large spikes upon app resume.
    public var maxDeltaTime: Double = 0.1
    
    /// Indicates whether a valid render surface is currently attached and available for drawing.
    public private(set) var isSurfaceAvailable: Bool = true
    
    /// Indicates whether the engine is currently paused.
    public private(set) var isPaused: Bool = false
    
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
    
    /// Ticks the engine, updating the world if not paused.
    /// Clamps `deltaTime` to `maxDeltaTime` to avoid physics and rendering explosion upon resume.
    /// - Parameter deltaTime: The time elapsed since the last tick.
    public func tick(deltaTime: Double) {
        guard !isPaused else { return }
        let clampedDeltaTime = min(deltaTime, maxDeltaTime)
        world.update(deltaTime: clampedDeltaTime)
        inputSystem.advanceFrame()
    }
    
    /// Renders the current state of the world if a native surface is available.
    /// - Parameter context: The render context for the current frame.
    public func render(context: RenderContext) {
        guard isSurfaceAvailable else { return }
        renderSystem.render(world: world, context: context)
    }
    
    /// Pauses the engine, stopping tick updates, resetting active inputs, and dispatching `AppPauseEvent`.
    public func pause() {
        guard !isPaused else { return }
        isPaused = true
        inputSystem.reset()
        world.eventBus.publish(AppPauseEvent())
    }
    
    /// Resumes the engine, resuming tick updates and dispatching `AppResumeEvent`.
    public func resume() {
        guard isPaused else { return }
        isPaused = false
        world.eventBus.publish(AppResumeEvent())
    }
    
    /// Notifies the engine that the native rendering surface has been created or resumed.
    public func surfaceCreated() {
        isSurfaceAvailable = true
        world.eventBus.publish(SurfaceCreatedEvent())
    }
    
    /// Notifies the engine that the native rendering surface has been destroyed.
    /// Halts any subsequent render calls until a new surface is created.
    public func surfaceDestroyed() {
        isSurfaceAvailable = false
        world.eventBus.publish(SurfaceDestroyedEvent())
    }
}
