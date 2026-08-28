import Foundation

/// An event published when a sprite animation advances to a new frame.
public struct SpriteAnimationFrameEvent: Event, Sendable, Equatable {
    /// The entity whose animation advanced.
    public let entity: Entity
    
    /// The name of the active animation clip.
    public let clipName: String
    
    /// The 0-based index of the new frame.
    public let frameIndex: Int
    
    /// The frame identifier in the sprite sheet.
    public let frameName: String
    
    /// Initializes a new sprite animation frame event.
    /// - Parameters:
    ///   - entity: The entity whose animation updated.
    ///   - clipName: The name of the active clip.
    ///   - frameIndex: The index of the active frame.
    ///   - frameName: The frame identifier.
    public init(entity: Entity, clipName: String, frameIndex: Int, frameName: String) {
        self.entity = entity
        self.clipName = clipName
        self.frameIndex = frameIndex
        self.frameName = frameName
    }
}

/// An event published when a non-looping sprite animation clip reaches its end.
public struct SpriteAnimationCompletedEvent: Event, Sendable, Equatable {
    /// The entity whose animation completed.
    public let entity: Entity
    
    /// The name of the completed animation clip.
    public let clipName: String
    
    /// Initializes a new sprite animation completed event.
    /// - Parameters:
    ///   - entity: The entity whose animation completed.
    ///   - clipName: The name of the completed clip.
    public init(entity: Entity, clipName: String) {
        self.entity = entity
        self.clipName = clipName
    }
}

/// An event published when an animation frame containing custom trigger tags is activated.
public struct SpriteAnimationTriggerEvent: Event, Sendable, Equatable {
    /// The entity whose animation triggered the event.
    public let entity: Entity
    
    /// The name of the active animation clip.
    public let clipName: String
    
    /// The 0-based index of the frame containing the trigger.
    public let frameIndex: Int
    
    /// The custom trigger tag identifier (e.g. "footstep_sfx", "melee_hitbox_open").
    public let payload: String
    
    /// Initializes a new sprite animation trigger event.
    /// - Parameters:
    ///   - entity: The entity whose animation triggered the event.
    ///   - clipName: The active clip name.
    ///   - frameIndex: The active frame index.
    ///   - payload: The trigger payload tag.
    public init(entity: Entity, clipName: String, frameIndex: Int, payload: String) {
        self.entity = entity
        self.clipName = clipName
        self.frameIndex = frameIndex
        self.payload = payload
    }
}
