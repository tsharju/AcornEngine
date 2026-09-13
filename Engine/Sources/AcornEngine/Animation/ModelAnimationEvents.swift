import Foundation

/// Published when a 3D model animation clip begins playback.
public struct ModelAnimationStartedEvent: Event {
    /// The entity owning the animation.
    public let entity: Entity
    
    /// The name of the animation clip that started.
    public let clipName: String
    
    /// Initializes a new start event.
    public init(entity: Entity, clipName: String) {
        self.entity = entity
        self.clipName = clipName
    }
}

/// Published when a 3D model animation completes in `.once` or `.reverseOnce` mode.
public struct ModelAnimationCompletedEvent: Event {
    /// The entity owning the animation.
    public let entity: Entity
    
    /// The name of the animation clip that completed.
    public let clipName: String
    
    /// Initializes a new completion event.
    public init(entity: Entity, clipName: String) {
        self.entity = entity
        self.clipName = clipName
    }
}

/// Published each time a 3D model animation wraps and loops in `.loop` or `.reverseLoop` mode.
public struct ModelAnimationLoopedEvent: Event {
    /// The entity owning the animation.
    public let entity: Entity
    
    /// The name of the animation clip that looped.
    public let clipName: String
    
    /// Initializes a new loop event.
    public init(entity: Entity, clipName: String) {
        self.entity = entity
        self.clipName = clipName
    }
}

/// Published when a crossfade transition begins between two animation clips.
public struct ModelAnimationTransitionStartedEvent: Event {
    /// The entity owning the animation.
    public let entity: Entity
    
    /// The source clip being transitioned from.
    public let fromClipName: String
    
    /// The destination clip being transitioned to.
    public let toClipName: String
    
    /// The total duration of the transition in seconds.
    public let duration: Double
    
    /// Initializes a new transition start event.
    public init(entity: Entity, fromClipName: String, toClipName: String, duration: Double) {
        self.entity = entity
        self.fromClipName = fromClipName
        self.toClipName = toClipName
        self.duration = duration
    }
}

/// Published when a crossfade transition between two animation clips completes.
public struct ModelAnimationTransitionCompletedEvent: Event {
    /// The entity owning the animation.
    public let entity: Entity
    
    /// The active clip after transition completes.
    public let clipName: String
    
    /// Initializes a new transition completion event.
    public init(entity: Entity, clipName: String) {
        self.entity = entity
        self.clipName = clipName
    }
}
