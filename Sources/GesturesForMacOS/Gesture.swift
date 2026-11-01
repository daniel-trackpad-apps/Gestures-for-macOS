import Foundation

/// Description of a gesture. A simple structure so it is easy to store as JSON later.
struct Gesture: Hashable, Sendable {
    let kind: String       // swipe / pinch / rotate / tap / hold / edge / corner
    let fingers: Int
    let direction: String

    var id: String { "\(kind)-\(fingers)-\(direction)" }

    private var n: String {
        switch fingers {
        case 1: return "with 1 finger"
        case 2: return "with 2 fingers"
        case 3: return "with 3 fingers"
        default: return "with 4 fingers"
        }
    }

    var title: String {
        let dirs = ["left": "left", "right": "right", "up": "up", "down": "down"]
        let edges = ["left": "left", "right": "right", "top": "top", "bottom": "bottom"]
        let corners = ["tl": "top-left", "tr": "top-right", "bl": "bottom-left", "br": "bottom-right"]
        switch kind {
        case "swipe":  return "Swipe \(dirs[direction] ?? direction) \(n)"
        case "pinch":  return (direction == "in" ? "Pinch in" : "Pinch out") + (fingers > 2 ? " \(n)" : "")
        case "rotate": return (direction == "cw" ? "Rotate clockwise" : "Rotate counterclockwise") + (fingers > 2 ? " \(n)" : "")
        case "tap":    return "Tap \(n)"
        case "hold":   return "Hold \(n)"
        case "edge":   return "Swipe from the \(edges[direction] ?? direction) edge"
        case "corner": return "Tap the \(corners[direction] ?? direction) corner"
        default:       return "\(kind) \(direction)"
        }
    }
}

enum GestureCatalog {
    struct Info {
        let gesture: Gesture
        let defaultOn: Bool
    }

    /// All gestures the app knows. defaultOn = enabled by default (does not clash with the system).
    static let all: [Info] = {
        var l: [Info] = []
        func add(_ k: String, _ f: Int, _ d: String, _ on: Bool = false) {
            l.append(Info(gesture: Gesture(kind: k, fingers: f, direction: d), defaultOn: on))
        }
        for d in ["left", "right"] { add("swipe", 2, d, true) }
        for f in [3, 4] { for d in ["left", "right", "up", "down"] { add("swipe", f, d) } }
        for f in [2, 3, 4] { for d in ["in", "out"] { add("pinch", f, d, f == 3) } }
        for f in [2, 3] { for d in ["cw", "ccw"] { add("rotate", f, d, f == 3) } }
        for f in [2, 3, 4] { add("tap", f, "", f == 4) }
        add("hold", 3, "", true)
        for d in ["left", "right", "top", "bottom"] { add("edge", 1, d) }
        for d in ["tl", "tr", "bl", "br"] { add("corner", 1, d) }
        return l
    }()
}

/// Which gestures are enabled. Stored in UserDefaults.
@MainActor
enum GestureSettings {
    private static let key = "enabledGestures"

    static var enabled: Set<String> = {
        if let a = UserDefaults.standard.array(forKey: key) as? [String] { return Set(a) }
        return defaults()
    }()

    private static func defaults() -> Set<String> {
        Set(GestureCatalog.all.filter { $0.defaultOn }.map { $0.gesture.id })
    }

    static func isEnabled(_ g: Gesture) -> Bool { enabled.contains(g.id) }

    static func toggle(_ id: String) {
        if enabled.contains(id) { enabled.remove(id) } else { enabled.insert(id) }
        UserDefaults.standard.set(Array(enabled), forKey: key)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        enabled = defaults()
    }
}
