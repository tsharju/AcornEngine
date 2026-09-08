import Foundation

/// An event published when the application is paused (e.g., Android `APP_CMD_PAUSE` or iOS `sceneWillResignActive`).
public struct AppPauseEvent: Event, Equatable {
    public init() {}
}

/// An event published when the application resumes execution (e.g., Android `APP_CMD_RESUME` or iOS `sceneDidBecomeActive`).
public struct AppResumeEvent: Event, Equatable {
    public init() {}
}

/// An event published when the native window or rendering surface is created (e.g., Android `APP_CMD_INIT_WINDOW`).
public struct SurfaceCreatedEvent: Event, Equatable {
    public init() {}
}

/// An event published when the native window or rendering surface is destroyed (e.g., Android `APP_CMD_TERM_WINDOW`).
/// Rendering must cease immediately when this event occurs to prevent fatal OS signals (such as SIGSEGV on Android).
public struct SurfaceDestroyedEvent: Event, Equatable {
    public init() {}
}
