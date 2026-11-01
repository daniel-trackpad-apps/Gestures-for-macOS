import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let model = AppModel()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DockMode.applyAtLaunch()
        NSApp.applicationIconImage = makeIcon()
        buildMainMenu()
        model.start()
        showWindow()
    }

    // Closing the window does not quit the app: gestures keep working
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // Clicking the Dock icon reopens the window
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func showWindow() {
        if window == nil { window = makeWindow() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        w.title = "Gestures for macOS"
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 540, height: 560)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true

        // Translucent macOS-style (glass) background behind the content
        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState

        let host = NSHostingView(rootView: ContentView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        w.contentView = effect

        w.center()
        w.setFrameAutosaveName("MainWindow2")
        return w
    }

    // MARK: Main menu

    private func mi(_ title: String, _ action: Selector?, _ key: String = "",
                    mods: NSEvent.ModifierFlags = [.command], own: Bool = true) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { it.keyEquivalentModifierMask = mods }
        if own { it.target = self }
        return it
    }

    private func buildMainMenu() {
        let main = NSMenu()
        let name = "Gestures for macOS"

        @discardableResult
        func add(_ title: String, _ fill: (NSMenu) -> Void) -> NSMenu {
            let top = NSMenuItem()
            let menu = NSMenu(title: title)
            fill(menu)
            top.submenu = menu
            main.addItem(top)
            return menu
        }

        add(name) { m in
            m.addItem(mi("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), own: false))
            m.addItem(.separator())
            m.addItem(mi("Settings…", #selector(openSettingsWindow), ","))
            m.addItem(.separator())
            m.addItem(mi("Hide \(name)", #selector(NSApplication.hide(_:)), "h", own: false))
            m.addItem(mi("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", mods: [.command, .option], own: false))
            m.addItem(mi("Show All", #selector(NSApplication.unhideAllApplications(_:)), own: false))
            m.addItem(.separator())
            m.addItem(mi("Quit \(name)", #selector(NSApplication.terminate(_:)), "q", own: false))
        }

        add("File") { m in
            m.addItem(mi("Add App", #selector(addApp), "n"))
            m.addItem(.separator())
            m.addItem(mi("Close Window", #selector(NSWindow.performClose(_:)), "w", own: false))
        }

        add("Edit") { m in
            m.addItem(mi("Undo", Selector(("undo:")), "z", own: false))
            m.addItem(mi("Redo", Selector(("redo:")), "z", mods: [.command, .shift], own: false))
            m.addItem(.separator())
            m.addItem(mi("Cut", #selector(NSText.cut(_:)), "x", own: false))
            m.addItem(mi("Copy", #selector(NSText.copy(_:)), "c", own: false))
            m.addItem(mi("Paste", #selector(NSText.paste(_:)), "v", own: false))
            m.addItem(mi("Select All", #selector(NSText.selectAll(_:)), "a", own: false))
        }

        add("Gestures") { m in
            m.addItem(mi("Listen for Gestures", #selector(toggleListening), "l"))
            m.addItem(mi("Show in Dock", #selector(toggleDock)))
            m.addItem(.separator())
            m.addItem(mi("Accessibility Permission", #selector(openAccessibility)))
            m.addItem(mi("Input Monitoring Permission", #selector(openInput)))
            m.addItem(.separator())
            m.addItem(mi("Restart App", #selector(relaunchApp)))
        }

        let windowMenu = add("Window") { m in
            m.addItem(mi("Zoom", #selector(NSWindow.performZoom(_:)), own: false))
            m.addItem(.separator())
            m.addItem(mi("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), own: false))
        }

        let helpMenu = add("Help") { m in
            m.addItem(mi("Open Diagnostic Log", #selector(openDebugLog)))
        }

        NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = helpMenu
        NSApp.mainMenu = main
    }

    @objc func openSettingsWindow() { showWindow() }
    @objc func addApp() { showWindow(); model.addAppRequest += 1 }
    @objc func toggleListening() { model.setPaused(!model.paused) }
    @objc func toggleDock() { DockMode.apply(!DockMode.showInDock) }
    @objc func openAccessibility() { model.openSettings(.accessibility) }
    @objc func openInput() { model.openSettings(.input) }
    @objc func relaunchApp() { model.relaunch() }
    @objc func openDebugLog() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GesturesForMacOS/debug.log")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleListening): menuItem.state = model.paused ? .off : .on
        case #selector(toggleDock): menuItem.state = DockMode.showInDock ? .on : .off
        default: break
        }
        return true
    }

    /// Dock icon: a rounded square with a gradient and the hand
    private func makeIcon() -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: 250, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        let symbol = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        return NSImage(size: NSSize(width: 512, height: 512), flipped: false) { rect in
            let r = rect.insetBy(dx: 40, dy: 40)
            let path = NSBezierPath(roundedRect: r, xRadius: 110, yRadius: 110)
            NSGradient(starting: .systemBlue, ending: .systemIndigo)?.draw(in: path, angle: -90)
            if let s = symbol {
                let w = s.size.width, h = s.size.height
                s.draw(in: NSRect(x: (rect.width - w) / 2, y: (rect.height - h) / 2, width: w, height: h))
            }
            return true
        }
    }
}
