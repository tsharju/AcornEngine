import Foundation

/// Represents a mouse button.
public enum MouseButton: Int, Sendable, Hashable, CaseIterable {
    /// The primary / left mouse button.
    case left = 0
    
    /// The secondary / right mouse button.
    case right = 1
    
    /// The center / middle mouse wheel button.
    case middle = 2
    
    /// Additional auxiliary mouse button 4 (e.g. Back).
    case button4 = 3
    
    /// Additional auxiliary mouse button 5 (e.g. Forward).
    case button5 = 4
}
