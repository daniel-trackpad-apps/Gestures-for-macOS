import AppKit
import ApplicationServices
import Observation

/// App state: listening for gestures, the active app, permissions and running actions.
@MainActor
@Observable
final class AppModel {
    var addAppRequest = 0
    var frontAppName = "—"
    var lastGesture = "No gesture detected yet"
    var detectedCount = 0
    var listening = false
    var paused = false
    var accessibilityOK = false
    var inputMonitoringOK = false

    let store = AppStore()
    let customStore = CustomGestureStore()

    @ObservationIgnored private let detector = GestureDetector()
    @ObservationIgnored private var frontApp: NSRunningApplication?
    @ObservationIgnored private var captureHandler: ((Gesture) -> Void)?
    @ObservationIgnored private var strokeHandler: ((Stroke) -> Void)?
    @ObservationIgnored private var lastCustomTime: TimeInterval = 0
    @ObservationIgnored private var started = false

    enum PermissionPane { case accessibility, input }

    func start() {
        guard !started else { return }
        started = true

        // A global entry ("All Apps") always exists
        store.ensureGlobal()

        // Do not show a permission prompt automatically on every launch. The user opens settings
        // through the UI, and the check refreshes when returning to the app.
        refreshPermissions()

        frontApp = NSWorkspace.shared.frontmostApplication
        if frontApp?.bundleIdentifier == Bundle.main.bundleIdentifier { frontApp = nil }
        frontAppName = frontApp?.localizedName ?? "—"

        detector.onGesture = { [weak self] gesture in
            MainActor.assumeIsolated { self?.gestureDetected(gesture) }
        }

        // Edge slides and custom gestures come from the stroke engine
        StrokeEngine.shared.onGesture = { [weak self] gesture in
            MainActor.assumeIsolated { self?.gestureDetected(gesture) }
        }
        StrokeEngine.shared.onStroke = { [weak self] stroke in
            MainActor.assumeIsolated { self?.strokeHandler?(stroke) }
        }
        refreshEngine()

        // Updates only when switching apps, with no background polling
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.activeAppChanged(app) }
        }

        // When returning to the window (e.g. after granting permission in System Settings), re-check permissions and try to start again
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.becameActive() }
        }

        // When leaving the settings window, update the engine with the current setup
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshEngine() }
        }

        detector.start()
        listening = detector.isListening
    }

    /// Updates the stroke engine: which custom gestures exist, and whether an edge slide is set up
    func refreshEngine() {
        let slides = store.apps.contains { app in
            app.mappings.contains { Gesture(id: $0.gestureID)?.kind == "slide" }
        }
        StrokeEngine.shared.configure(customs: customStore.items, slides: slides)
    }

    private func activeAppChanged(_ app: NSRunningApplication?) {
        guard let app else { return }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            frontApp = nil
            frontAppName = "—"
            return
        }
        frontApp = app
        frontAppName = app.localizedName ?? "—"
    }

    private func becameActive() {
        refreshPermissions()
        if !paused { detector.start() }
        listening = !paused && detector.isListening
    }

    private func refreshPermissions() {
        accessibilityOK = AXIsProcessTrusted() && CGPreflightPostEventAccess()
        inputMonitoringOK = CGPreflightListenEventAccess()
    }

    /// A custom gesture or edge slide runs immediately. A regular gesture waits a moment,
    /// to avoid clashing with a custom gesture that claimed the same motion.
    private func gestureDetected(_ g: Gesture) {
        if g.kind == "custom" || g.kind == "slide" {
            lastCustomTime = ProcessInfo.processInfo.systemUptime
            process(g)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if ProcessInfo.processInfo.systemUptime - self.lastCustomTime < 0.4 { return }
                    self.process(g)
                }
            }
        }
    }

    private func process(_ g: Gesture) {
        detectedCount += 1

        // While creating a new gesture, no action is run
        if strokeHandler != nil { return }

        // Recording a known gesture from the setup window
        if let handler = captureHandler {
            captureHandler = nil
            handler(g)
            return
        }
        // When this app's window is frontmost, no actions run, but the detected gesture is shown
        if NSApp.isActive {
            lastGesture = "\(g.displayTitle) · detected (not run while the Gestures window is frontmost)"
            DebugLog.write("\(g.id) · Gestures window is frontmost, not run")
            return
        }
        guard let app = frontApp, let id = app.bundleIdentifier else {
            lastGesture = "\(g.displayTitle) · frontmost app not recognized"
            DebugLog.write("\(g.id) · frontmost app not recognized")
            return
        }
        // First the app's own setup, otherwise the global one
        guard let action = store.effectiveAction(bundleID: id, gestureID: g.id) else {
            lastGesture = "\(g.displayTitle) · \(frontAppName) · no action set up"
            DebugLog.write("\(g.id) · \(id) · no action set up")
            return
        }
        lastGesture = "\(g.displayTitle) · \(frontAppName) ← \(action.title)"
        DebugLog.write("\(g.id) · \(id) · \(action.kind.rawValue) \"\(action.title)\" key=\(action.keyCode) flags=\(action.flags) accessibility=\(AXIsProcessTrusted()) post=\(CGPreflightPostEventAccess())")

        // System actions: volume, brightness, music
        if let key = action.mediaKey {
            MediaKeys.post(key)
            return
        }

        switch action.kind {
        case .menu:
            let ok = MenuReader.press(pid: app.processIdentifier, path: action.menuPath)
            DebugLog.write("Menu item click: \(ok ? "succeeded" : "failed")")
        case .shortcut:
            ActionRunner.run(action, bundleID: id)
        }
    }

    // MARK: Actions from the window

    func setPaused(_ value: Bool) {
        guard value != paused else { return }
        paused = value
        if paused {
            detector.stop()
            captureHandler = nil
        } else {
            detector.start()
        }
        listening = !paused && detector.isListening
    }

    func captureNextGesture(_ handler: @escaping (Gesture) -> Void) {
        if paused { setPaused(false) }
        captureHandler = handler
    }

    func cancelCapture() { captureHandler = nil }

    /// Creating a new gesture: every gesture performed on the trackpad is routed to the recorder
    func captureStrokes(_ handler: @escaping (Stroke) -> Void) {
        if paused { setPaused(false) }
        strokeHandler = handler
        StrokeEngine.shared.setRecording(true)
    }

    func cancelStrokeCapture() {
        strokeHandler = nil
        StrokeEngine.shared.setRecording(false)
    }

    func removeApp(_ bundleID: String) {
        store.removeApp(bundleID)
        refreshEngine()
    }

    func openSettings(_ pane: PermissionPane) {
        let name = pane == .accessibility ? "Privacy_Accessibility" : "Privacy_ListenEvent"
        // The permission request happens only after an explicit user click, not on every launch.
        if pane == .accessibility {
            if !AXIsProcessTrusted() {
                let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
            if !CGPreflightPostEventAccess() { _ = CGRequestPostEventAccess() }
        } else if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(name)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Restarts the app (sometimes required after granting Input Monitoring)
    func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
        }
    }
}
