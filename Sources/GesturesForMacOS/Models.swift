import AppKit

/// An action a gesture performs: a keyboard shortcut, or clicking an item in the app's menu.
struct GestureAction: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case shortcut, menu }
    var kind: Kind
    var title: String
    var shortcutName: String? = nil
    var keyCode: UInt16 = 0
    var flags: UInt64 = 0
    var menuPath: [String] = []
}

struct Mapping: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var gestureID: String
    var action: GestureAction
}

struct AppEntry: Codable, Hashable, Identifiable, Sendable {
    var bundleID: String
    var name: String
    var path: String
    var mappings: [Mapping] = []
    var id: String { bundleID }
}

// MARK: Gestures: restoring an id, icons and groups

extension Gesture {
    init?(id: String) {
        let p = id.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard p.count == 3, let f = Int(p[1]) else { return nil }
        self.init(kind: p[0], fingers: f, direction: p[2])
    }

    var symbol: String {
        switch kind {
        case "swipe": return "hand.draw"
        case "pinch": return "arrow.up.left.and.arrow.down.right"
        case "rotate": return "arrow.clockwise"
        case "tap": return "hand.tap"
        case "hold": return "timer"
        case "edge": return "arrow.right.to.line"
        case "corner": return "rectangle.inset.topright.filled"
        default: return "hand.point.up.left"
        }
    }
}

struct GestureKindInfo: Identifiable {
    let id: String
    let title: String
}

enum GestureKinds {
    static let all: [GestureKindInfo] = [
        GestureKindInfo(id: "swipe", title: "Swipes"),
        GestureKindInfo(id: "pinch", title: "Pinches"),
        GestureKindInfo(id: "rotate", title: "Rotations"),
        GestureKindInfo(id: "tap", title: "Taps"),
        GestureKindInfo(id: "hold", title: "Holds"),
        GestureKindInfo(id: "edge", title: "Edge swipes"),
        GestureKindInfo(id: "corner", title: "Corner taps"),
    ]

    static func gestures(of kind: String) -> [Gesture] {
        GestureCatalog.all.filter { $0.gesture.kind == kind }.map { $0.gesture }
    }
}

// MARK: System actions (fixed macOS keyboard shortcuts)

enum SystemActions {
    private static let cmd = CGEventFlags.maskCommand.rawValue
    private static let shift = CGEventFlags.maskShift.rawValue
    private static let ctrl = CGEventFlags.maskControl.rawValue

    private static func key(_ title: String, _ code: UInt16, _ flags: UInt64) -> GestureAction {
        GestureAction(kind: .shortcut, title: title, keyCode: code, flags: flags)
    }

    static let all: [GestureAction] = [
        key("Mission Control", 126, ctrl),
        key("Show Active App Windows", 125, ctrl),
        key("Move to Left Desktop", 123, ctrl),
        key("Move to Right Desktop", 124, ctrl),
        key("Spotlight", 49, cmd),
        key("Full Screenshot", 20, cmd | shift),
        key("Screenshot of Selection", 21, cmd | shift),
        key("Lock Screen", 12, cmd | ctrl),
        key("Switch Window in App", 50, cmd),
    ]
}

// MARK: Shortcut names and suggestions

struct ShortcutSuggestion: Identifiable {
    let name: String
    let keyLabel: String
    let keyCode: UInt16
    let flags: UInt64
    let detail: String
    var id: String { name }
    var action: GestureAction {
        GestureAction(kind: .shortcut, title: name, shortcutName: name, keyCode: keyCode, flags: flags)
    }
}

enum ShortcutSuggestions {
    private static let cmd = CGEventFlags.maskCommand.rawValue
    private static let shift = CGEventFlags.maskShift.rawValue
    private static let option = CGEventFlags.maskAlternate.rawValue

    static let common: [ShortcutSuggestion] = [
        .init(name: "Save Document", keyLabel: "⌘S", keyCode: 1, flags: cmd, detail: "Saves the current file or document"),
        .init(name: "Undo", keyLabel: "⌘Z", keyCode: 6, flags: cmd, detail: "Reverts the last change"),
        .init(name: "Redo", keyLabel: "⇧⌘Z", keyCode: 6, flags: cmd | shift, detail: "Brings back an undone action"),
        .init(name: "Find", keyLabel: "⌘F", keyCode: 3, flags: cmd, detail: "Searches the document or page"),
        .init(name: "Print", keyLabel: "⌘P", keyCode: 35, flags: cmd, detail: "Opens the print dialog"),
        .init(name: "Minimize Window", keyLabel: "⌘M", keyCode: 46, flags: cmd, detail: "Minimizes the active window"),
        .init(name: "Show Desktop", keyLabel: "F11", keyCode: 103, flags: 0, detail: "Temporarily hides the windows"),
        .init(name: "Paste Without Formatting", keyLabel: "⌥⇧⌘V", keyCode: 9, flags: cmd | shift | option, detail: "Pastes text without its original formatting"),
    ]

    static func appSpecific(bundleID: String) -> [ShortcutSuggestion] {
        let browser = ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.edgemac"]
        guard browser.contains(bundleID) else { return [] }
        return [
            .init(name: "Reopen Last Closed Tab", keyLabel: "⇧⌘T", keyCode: 17, flags: cmd | shift, detail: "Restores a tab that was closed"),
            .init(name: "Downloads", keyLabel: "⌥⌘L", keyCode: 37, flags: cmd | option, detail: "Opens the downloads list"),
        ]
    }
}

// MARK: Keyboard shortcut display

enum ShortcutFormat {
    static func symbols(flags: UInt64) -> String {
        var s = ""
        if flags & CGEventFlags.maskControl.rawValue != 0 { s += "⌃" }
        if flags & CGEventFlags.maskAlternate.rawValue != 0 { s += "⌥" }
        if flags & CGEventFlags.maskShift.rawValue != 0 { s += "⇧" }
        if flags & CGEventFlags.maskCommand.rawValue != 0 { s += "⌘" }
        return s
    }

    static func keyName(_ e: NSEvent) -> String {
        let special: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        if let s = special[e.keyCode] { return s }
        return (e.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

// MARK: Storing apps and their gestures

@MainActor
@Observable
final class AppStore {
    var apps: [AppEntry] = []
    @ObservationIgnored private var fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GesturesForMacOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("apps.json")
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([AppEntry].self, from: data) {
            apps = list
        }
    }

    func app(_ bundleID: String) -> AppEntry? { apps.first { $0.bundleID == bundleID } }

    func action(bundleID: String, gestureID: String) -> GestureAction? {
        app(bundleID)?.mappings.first { $0.gestureID == gestureID }?.action
    }

    /// Adds an app by its file location. Returns the app's identifier.
    @discardableResult
    func add(url: URL) -> String? {
        guard let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        if app(id) == nil {
            var name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            apps.append(AppEntry(bundleID: id, name: name, path: url.path))
            save()
        }
        return id
    }

    func removeApp(_ bundleID: String) {
        apps.removeAll { $0.bundleID == bundleID }
        save()
    }

    func setMapping(_ bundleID: String, gestureID: String, action: GestureAction) {
        guard let i = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        if let j = apps[i].mappings.firstIndex(where: { $0.gestureID == gestureID }) {
            apps[i].mappings[j].action = action
        } else {
            apps[i].mappings.append(Mapping(gestureID: gestureID, action: action))
        }
        save()
    }

    /// Updates an app's name without touching its gestures.
    func renameApp(_ bundleID: String, name: String) {
        guard let i = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        apps[i].name = name
        save()
    }

    /// Editing an existing gesture: replaces the gesture and the action, and keeps the other settings.
    func updateMapping(_ bundleID: String, id: UUID, gestureID: String, action: GestureAction) {
        guard let i = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        // If the new gesture is already defined elsewhere, the old one is removed
        apps[i].mappings.removeAll { $0.gestureID == gestureID && $0.id != id }
        if let j = apps[i].mappings.firstIndex(where: { $0.id == id }) {
            apps[i].mappings[j].gestureID = gestureID
            apps[i].mappings[j].action = action
        } else {
            apps[i].mappings.append(Mapping(gestureID: gestureID, action: action))
        }
        save()
    }

    func removeMapping(_ bundleID: String, _ id: UUID) {
        guard let i = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        apps[i].mappings.removeAll { $0.id == id }
        save()
    }

    func save() {
        if let data = try? JSONEncoder().encode(apps) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
