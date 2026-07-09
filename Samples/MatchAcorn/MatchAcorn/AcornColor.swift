import Foundation

/// Defines the colors of the acorns in the game.
public enum AcornColor: String, Sendable, CaseIterable {
    case red
    case blue
    case green
    case yellow
    case purple
    
    /// The corresponding frame name in the packed sprite sheet.
    public var frameName: String {
        switch self {
        case .red: return "acorn_red"
        case .blue: return "acorn_blue"
        case .green: return "acorn_green"
        case .yellow: return "acorn_yellow"
        case .purple: return "acorn_purple"
        }
    }
}
