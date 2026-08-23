import Foundation

/// Represents a standard keyboard key.
public enum Key: String, Sendable, CaseIterable, Hashable {
    // Letters
    case a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
    
    // Numbers (Top Row)
    case num0, num1, num2, num3, num4, num5, num6, num7, num8, num9
    
    // Function Keys
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    
    // Directional Arrows
    case upArrow, downArrow, leftArrow, rightArrow
    
    // Whitespace & Editing
    case space
    case returnKey
    case tab
    case escape
    case backspace
    case deleteKey
    case insert
    case home
    case end
    case pageUp
    case pageDown
    
    // Modifiers
    case leftShift
    case rightShift
    case leftControl
    case rightControl
    case leftOption
    case rightOption
    case leftCommand
    case rightCommand
    case capsLock
    
    // Punctuation & Symbols
    case minus
    case equal
    case leftBracket
    case rightBracket
    case semicolon
    case quote
    case comma
    case period
    case slash
    case backslash
    case graveAccent
    
    /// Maps a standard macOS virtual key code to a `Key`.
    public static func from(macOSKeyCode keyCode: UInt16) -> Key? {
        switch keyCode {
        case 0x00: return .a
        case 0x01: return .s
        case 0x02: return .d
        case 0x03: return .f
        case 0x04: return .h
        case 0x05: return .g
        case 0x06: return .z
        case 0x07: return .x
        case 0x08: return .c
        case 0x09: return .v
        case 0x0B: return .b
        case 0x0C: return .q
        case 0x0D: return .w
        case 0x0E: return .e
        case 0x0F: return .r
        case 0x10: return .y
        case 0x11: return .t
        case 0x12: return .num1
        case 0x13: return .num2
        case 0x14: return .num3
        case 0x15: return .num4
        case 0x16: return .num6
        case 0x17: return .num5
        case 0x18: return .equal
        case 0x19: return .num9
        case 0x1A: return .num7
        case 0x1B: return .minus
        case 0x1C: return .num8
        case 0x1D: return .num0
        case 0x1E: return .rightBracket
        case 0x1F: return .o
        case 0x20: return .u
        case 0x21: return .leftBracket
        case 0x22: return .i
        case 0x23: return .p
        case 0x24: return .returnKey
        case 0x25: return .l
        case 0x26: return .j
        case 0x27: return .quote
        case 0x28: return .k
        case 0x29: return .semicolon
        case 0x2A: return .backslash
        case 0x2B: return .comma
        case 0x2C: return .slash
        case 0x2D: return .n
        case 0x2E: return .m
        case 0x2F: return .period
        case 0x30: return .tab
        case 0x31: return .space
        case 0x32: return .graveAccent
        case 0x33: return .backspace
        case 0x35: return .escape
        case 0x37: return .leftCommand
        case 0x38: return .leftShift
        case 0x39: return .capsLock
        case 0x3A: return .leftOption
        case 0x3B: return .leftControl
        case 0x3C: return .rightShift
        case 0x3D: return .rightOption
        case 0x3E: return .rightControl
        case 0x73: return .home
        case 0x74: return .pageUp
        case 0x75: return .deleteKey
        case 0x77: return .end
        case 0x79: return .pageDown
        case 0x7A: return .f1
        case 0x78: return .f2
        case 0x63: return .f3
        case 0x76: return .f4
        case 0x60: return .f5
        case 0x61: return .f6
        case 0x62: return .f7
        case 0x64: return .f8
        case 0x65: return .f9
        case 0x6D: return .f10
        case 0x67: return .f11
        case 0x6F: return .f12
        case 0x7B: return .leftArrow
        case 0x7C: return .rightArrow
        case 0x7D: return .downArrow
        case 0x7E: return .upArrow
        default: return nil
        }
    }
}

/// Represents active modifier flags on a keyboard.
public struct KeyModifierFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt
    
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
    
    public static let shift    = KeyModifierFlags(rawValue: 1 << 0)
    public static let control  = KeyModifierFlags(rawValue: 1 << 1)
    public static let option   = KeyModifierFlags(rawValue: 1 << 2)
    public static let command  = KeyModifierFlags(rawValue: 1 << 3)
    public static let capsLock = KeyModifierFlags(rawValue: 1 << 4)
}
