import Foundation

/// A slide along the trackpad edge. A continuous gesture: each step along the edge triggers the action again.
enum SlideGestures {
    static let directions = ["rup", "rdown", "lup", "ldown", "tleft", "tright", "bleft", "bright"]

    static let all: [Gesture] = directions.map { Gesture(kind: "slide", fingers: 1, direction: $0) }

    static func title(_ d: String) -> String {
        switch d {
        case "rup": return "Slide along the right edge, up"
        case "rdown": return "Slide along the right edge, down"
        case "lup": return "Slide along the left edge, up"
        case "ldown": return "Slide along the left edge, down"
        case "tleft": return "Slide along the top edge, left"
        case "tright": return "Slide along the top edge, right"
        case "bleft": return "Slide along the bottom edge, left"
        case "bright": return "Slide along the bottom edge, right"
        default: return d
        }
    }
}

/// Names of custom gestures, accessible from any thread
final class CustomNames: @unchecked Sendable {
    static let shared = CustomNames()
    private let lock = NSLock()
    private var names: [String: String] = [:]

    func update(_ list: [CustomGesture]) {
        lock.lock()
        names = list.reduce(into: [String: String]()) { $0[$1.id] = $1.name }
        lock.unlock()
    }

    func name(for id: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return names[id] ?? "Deleted gesture"
    }
}

extension Gesture {
    /// Display name (including custom gestures and edge slides)
    var displayTitle: String {
        switch kind {
        case "custom": return CustomNames.shared.name(for: direction)
        case "slide": return SlideGestures.title(direction)
        default: return title
        }
    }

    var displaySymbol: String {
        switch kind {
        case "custom": return "scribble"
        case "slide": return "arrow.up.and.down"
        default: return symbol
        }
    }
}
