import AppKit
import ApplicationServices

struct MenuEntry: Identifiable, Hashable, Sendable {
    let path: [String]
    let shortcut: String
    var id: String { path.joined(separator: " › ") }
    var title: String { path.last ?? "" }
    var section: String { path.dropLast().joined(separator: " › ") }
}

/// Reads the menus of the running app (via Accessibility) and triggers items from them.
enum MenuReader {
    static func read(pid: pid_t) -> [MenuEntry] {
        let app = AXUIElementCreateApplication(pid)
        guard let bar = element(app, "AXMenuBar") else { return [] }
        var out: [MenuEntry] = []
        for (i, barItem) in children(bar).enumerated() where i > 0 {   // skip the Apple menu
            let title = string(barItem, "AXTitle") ?? ""
            guard !title.isEmpty, let menu = children(barItem).first else { continue }
            walk(menu, [title], &out)
        }
        return out
    }

    private static func walk(_ menu: AXUIElement, _ prefix: [String], _ out: inout [MenuEntry]) {
        guard out.count < 800 else { return }
        for item in children(menu) {
            let title = string(item, "AXTitle") ?? ""
            guard !title.isEmpty else { continue }   // separators
            if let sub = children(item).first, prefix.count < 4 {
                walk(sub, prefix + [title], &out)
            } else {
                out.append(MenuEntry(path: prefix + [title], shortcut: shortcut(of: item)))
            }
        }
    }

    static func press(pid: pid_t, path: [String]) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        guard !path.isEmpty, var container = element(app, "AXMenuBar") else { return false }
        for (i, title) in path.enumerated() {
            guard let item = children(container).first(where: { string($0, "AXTitle") == title }) else { return false }
            if i == path.count - 1 {
                return AXUIElementPerformAction(item, "AXPress" as CFString) == .success
            }
            guard let next = children(item).first else { return false }
            container = next
        }
        return false
    }

    private static func shortcut(of item: AXUIElement) -> String {
        guard let ch = string(item, "AXMenuItemCmdChar"), !ch.isEmpty else { return "" }
        let m = int(item, "AXMenuItemCmdModifiers") ?? 0
        var s = ""
        if m & 4 != 0 { s += "⌃" }
        if m & 2 != 0 { s += "⌥" }
        if m & 1 != 0 { s += "⇧" }
        if m & 8 == 0 { s += "⌘" }
        return s + ch.uppercased()
    }

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXChildren" as CFString, &v) == .success,
              let arr = v as? [AXUIElement] else { return [] }
        return arr
    }

    private static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private static func int(_ el: AXUIElement, _ attr: String) -> Int? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? Int
    }

    private static func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success,
              let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }
}

/// Performs an action that was set up for a gesture.
enum ActionRunner {
    static func run(_ action: GestureAction, bundleID: String) {
        switch action.kind {
        case .shortcut:
            postKey(action.keyCode, flags: CGEventFlags(rawValue: action.flags))
        case .menu:
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                _ = MenuReader.press(pid: app.processIdentifier, path: action.menuPath)
            }
        }
    }

    private static func postKey(_ code: UInt16, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        // Real modifier keys: press them, press the key, and release in reverse order
        let all: [(CGEventFlags, CGKeyCode)] = [
            (.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55)
        ]
        let active = all.filter { flags.contains($0.0) }

        func send(_ key: CGKeyCode, down: Bool, flags f: CGEventFlags) {
            let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
            e?.flags = f
            e?.post(tap: .cghidEventTap)
            usleep(3000)
        }

        var current = CGEventFlags()
        for m in active {
            current.insert(m.0)
            send(m.1, down: true, flags: current)
        }
        send(CGKeyCode(code), down: true, flags: flags)
        send(CGKeyCode(code), down: false, flags: flags)
        for m in active.reversed() {
            current.remove(m.0)
            send(m.1, down: false, flags: current)
        }
    }
}
