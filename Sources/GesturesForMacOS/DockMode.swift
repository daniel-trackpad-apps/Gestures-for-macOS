import AppKit

/// Controls whether the app appears in the Dock. When hidden, a menu bar icon appears.
@MainActor
enum DockMode {
    private static let key = "showInDock"
    private static var item: NSStatusItem?
    private static let handler = Handler()

    static var showInDock: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    /// On launch: applies the saved state without popping up windows
    static func applyAtLaunch() {
        configure(showInDock)
    }

    /// When the toggle is clicked
    static func apply(_ show: Bool) {
        UserDefaults.standard.set(show, forKey: key)
        configure(show)
        NSApp.activate()
    }

    private static func configure(_ show: Bool) {
        if show {
            NSApp.setActivationPolicy(.regular)
            if let i = item {
                NSStatusBar.system.removeStatusItem(i)
                item = nil
            }
        } else {
            NSApp.setActivationPolicy(.accessory)
            installStatusItem()
        }
    }

    private static func installStatusItem() {
        guard item == nil else { return }
        let si = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = si.button {
            let img = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "Gestures")
            img?.isTemplate = true
            button.image = img
        }
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Gestures Window", action: #selector(Handler.openWindow), keyEquivalent: "")
        open.target = handler
        menu.addItem(open)
        let dock = NSMenuItem(title: "Show in Dock", action: #selector(Handler.restoreDock), keyEquivalent: "")
        dock.target = handler
        menu.addItem(dock)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(Handler.quit), keyEquivalent: "q")
        quit.target = handler
        menu.addItem(quit)
        si.menu = menu
        item = si
    }

    @MainActor
    final class Handler: NSObject {
        @objc func openWindow() { (NSApp.delegate as? AppDelegate)?.showWindow() }
        @objc func restoreDock() { DockMode.apply(true); (NSApp.delegate as? AppDelegate)?.showWindow() }
        @objc func quit() { NSApp.terminate(nil) }
    }
}
