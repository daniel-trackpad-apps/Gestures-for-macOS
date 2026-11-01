import SwiftUI

/// Add or edit a gesture, for a specific app or for all apps.
/// A new gesture can be recorded (three repetitions), a known gesture can be detected, or one can be picked from a list.
struct AddMappingSheet: View {
    let model: AppModel
    let app: AppEntry
    let editing: Mapping?
    @Environment(\.dismiss) private var dismiss

    private enum MenuState { case idle, loading, notRunning, empty, loaded }
    private enum RecState { case idle, recording, naming }
    private enum ActionCategory: String, CaseIterable, Identifiable {
        case common, system, shortcuts, appMenu
        var id: String { rawValue }
        var title: String {
            switch self {
            case .common: "Common"
            case .system: "System"
            case .shortcuts: "Shortcuts"
            case .appMenu: "Menu"
            }
        }
        var symbol: String {
            switch self {
            case .common: "sparkles"
            case .system: "slider.horizontal.3"
            case .shortcuts: "command"
            case .appMenu: "list.bullet"
            }
        }
    }
    private struct GesturePickerCategory: Identifiable {
        let id: String
        let title: String
        let symbol: String
    }

    private struct ConflictInfo {
        let system: String?
        let global: GestureAction?
    }

    @State private var gesture: Gesture?
    @State private var capturing = false
    @State private var showGesturePicker = false
    @State private var selectedGestureCategory = "swipe"
    @State private var action: GestureAction?

    @State private var rec: RecState = .idle
    @State private var samples: [Stroke] = []
    @State private var recMessage = ""
    @State private var draft: CustomGesture?
    @State private var newName = ""

    @State private var conflict: ConflictInfo?
    @State private var showConflict = false

    @State private var actionCategory: ActionCategory
    @State private var entries: [MenuEntry] = []
    @State private var menuState: MenuState = .idle
    @State private var query = ""

    @State private var recordingKey = false
    @State private var keyMonitor: Any?
    @State private var shortcutName = ""

    private var isGlobal: Bool { app.bundleID == globalAppID }

    init(model: AppModel, app: AppEntry, editing: Mapping? = nil) {
        self.model = model
        self.app = app
        self.editing = editing
        _gesture = State(initialValue: editing.flatMap { Gesture(id: $0.gestureID) })
        _action = State(initialValue: editing?.action)
        _shortcutName = State(initialValue: editing?.action.shortcutName ?? "")
        let oldAction = editing?.action
        if oldAction?.mediaKey != nil {
            _actionCategory = State(initialValue: .system)
        } else if oldAction?.kind == .menu {
            _actionCategory = State(initialValue: .appMenu)
        } else if oldAction?.shortcutName != nil {
            _actionCategory = State(initialValue: .shortcuts)
        } else if let oldAction,
                  BasicActions.all.dropFirst(5).contains(where: { $0.keyCode == oldAction.keyCode && $0.flags == oldAction.flags }) {
            _actionCategory = State(initialValue: .shortcuts)
        } else {
            _actionCategory = State(initialValue: .common)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(editing == nil
                 ? (isGlobal ? "Add a Gesture for All Apps" : "Add a Gesture for \(app.name)")
                 : (isGlobal ? "Edit Global Gesture" : "Edit Gesture in \(app.name)"))
                .font(.title2.bold())

            gestureSection
            actionSection

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(gesture == nil || action == nil)
            }
        }
        .padding(18)
        // The sheet stays smaller than the main window frame, even at its minimum size.
        .frame(width: 480, height: 460)
        .onAppear { if actionCategory == .appMenu && !isGlobal { loadMenu() } }
        .onChange(of: actionCategory) { _, category in
            if category == .appMenu && !isGlobal && menuState == .idle { loadMenu() }
        }
        .onDisappear {
            model.cancelCapture()
            model.cancelStrokeCapture()
            stopKeyRecord()
        }
        .onChange(of: gesture) { _, new in
            if let g = new { checkConflicts(g) }
        }
        .alert("This gesture is already in use", isPresented: $showConflict, presenting: conflict) { c in
            Button("Keep It Anyway") { }
            if c.system != nil {
                Button("Open System Settings") { openTrackpadSettings() }
            }
            Button("Discard Gesture", role: .cancel) { gesture = nil }
        } message: { c in
            Text(conflictMessage(c))
        }
    }

    // MARK: Conflicts

    private func checkConflicts(_ g: Gesture) {
        let sys = SystemGestures.conflict(for: g)
        let glob: GestureAction? = isGlobal ? nil : model.store.action(bundleID: globalAppID, gestureID: g.id)
        guard sys != nil || glob != nil else { return }
        conflict = ConflictInfo(system: sys, global: glob)
        showConflict = true
    }

    private func conflictMessage(_ c: ConflictInfo) -> String {
        var parts: [String] = []
        if let s = c.system {
            parts.append("macOS already uses this gesture: \(s). If you keep it, both the system and this app will respond, which can be confusing. You can turn off the system gesture in System Settings → Trackpad.")
        }
        if let g = c.global {
            parts.append("In the global setting (all apps), this gesture is set to \"\(g.title)\". In \(app.name), the action you choose here will run instead of the global one.")
        }
        return parts.joined(separator: "\n\n")
    }

    private func openTrackpadSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Gesture

    /// The action already defined for the selected gesture (excluding the one being edited)
    private var conflictingAction: GestureAction? {
        guard let g = gesture,
              let m = app.mappings.first(where: { $0.gestureID == g.id && $0.id != editing?.id })
        else { return nil }
        return m.action
    }

    private var gestureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("1. Which gesture?").font(.headline)
            if let g = gesture {
                selectedGestureView(g)
            } else {
                switch rec {
                case .idle: pickerView
                case .recording: recordingView
                case .naming: namingView
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private func selectedGestureView(_ g: Gesture) -> some View {
        HStack {
            Image(systemName: g.displaySymbol).foregroundStyle(.tint)
            Text(g.displayTitle).fontWeight(.semibold)
            Spacer()
            Button("Change") { gesture = nil }
        }
        if let old = conflictingAction {
            Text("This gesture already has the action \"\(old.title)\". Saving will replace it.")
                .font(.callout)
                .foregroundStyle(.orange)
        } else if !isGlobal, let ga = model.store.action(bundleID: globalAppID, gestureID: g.id) {
            Text("This gesture also has a global action (\"\(ga.title)\"). The action you choose here will override it in \(app.name).")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if g.kind == "slide" {
            Text("Continuous gesture: each step along the edge triggers the action again. To make it work in the opposite direction too, set that direction up separately.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var pickerView: some View {
        HStack(spacing: 8) {
            gestureActionButton("Custom Gesture", symbol: "scribble", action: startNewGesture)
            gestureActionButton(
                capturing ? "Perform Gesture" : "Detect Gesture",
                symbol: "record.circle",
                action: startCapture
            )
            Button { showGesturePicker = true } label: {
                Label("Choose Gesture", systemImage: "hand.tap")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .glassCard(radius: 12)
        }
        .popover(isPresented: $showGesturePicker, arrowEdge: .bottom) {
            gesturePickerPopover
                .frame(width: 420, height: 300)
                .environment(\.layoutDirection, .leftToRight)
        }
    }

    private func gestureActionButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassCard(radius: 12)
    }

    private var gesturePickerCategories: [GesturePickerCategory] {
        var categories = GestureKinds.all.map {
            GesturePickerCategory(id: $0.id, title: $0.title, symbol: gestureCategorySymbol($0.id))
        }
        categories.append(GesturePickerCategory(id: "slide", title: "Edge Slide", symbol: "arrow.up.and.down"))
        if !model.customStore.items.isEmpty {
            categories.append(GesturePickerCategory(id: "custom", title: "Custom", symbol: "scribble"))
        }
        return categories
    }

    private func gestureCategorySymbol(_ id: String) -> String {
        switch id {
        case "swipe": "hand.draw"
        case "pinch": "arrow.up.left.and.arrow.down.right"
        case "rotate": "arrow.clockwise"
        case "tap": "hand.tap"
        case "hold": "timer"
        case "edge": "arrow.right.to.line"
        case "corner": "rectangle.inset.topright.filled"
        default: "hand.point.up.left"
        }
    }

    private var gesturePickerOptions: [Gesture] {
        switch selectedGestureCategory {
        case "slide": SlideGestures.all
        case "custom": model.customStore.items.map(\.gesture)
        default: GestureKinds.gestures(of: selectedGestureCategory)
        }
    }

    private var gesturePickerPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Gesture")
                .font(.title3.weight(.semibold))

            LazyVGrid(columns: gestureCategoryColumns, spacing: 7) {
                ForEach(gesturePickerCategories) { category in
                    let selected = selectedGestureCategory == category.id
                    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedGestureCategory = category.id }
                    } label: {
                        Label(category.title, systemImage: category.symbol)
                            .font(.callout.weight(selected ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .contentShape(shape)
                    }
                    .buttonStyle(.plain)
                    .glassCard(radius: 10)
                    .overlay {
                        if selected { shape.strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.3) }
                    }
                }
            }

            ScrollView {
                LazyVGrid(columns: tileColumns, spacing: 8) {
                    ForEach(gesturePickerOptions, id: \.id) { option in
                        Button {
                            gesture = option
                            showGesturePicker = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: option.displaySymbol)
                                    .foregroundStyle(.tint)
                                    .frame(width: 20)
                                Text(option.displayTitle)
                                    .font(.callout.weight(.medium))
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .glassCard(radius: 12)
                        .contextMenu {
                            if selectedGestureCategory == "custom",
                               let custom = model.customStore.items.first(where: { $0.gesture == option }) {
                                Button("Delete Custom Gesture", systemImage: "trash", role: .destructive) {
                                    deleteCustom(custom)
                                }
                            }
                        }
                    }
                }
                .padding(1)
            }
        }
        .padding(18)
    }

    private var recordingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Perform the gesture on the trackpad three times, in roughly the same way. Any number of fingers works, including drawing a shape.")
                .font(.callout)
            ProgressView(value: Double(samples.count), total: 3)
            Text("Captured \(samples.count) of 3").font(.callout).foregroundStyle(.secondary)
            if !recMessage.isEmpty {
                Text(recMessage).font(.callout).foregroundStyle(.orange)
            }
            Button("Cancel") { cancelRecording() }
        }
    }

    private var namingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let d = draft {
                Text(draftSummary(d)).font(.callout).foregroundStyle(.secondary)
            }
            TextField("Gesture name", text: $newName).textFieldStyle(.roundedBorder)
            HStack {
                Button("Try Again") { startNewGesture() }
                Spacer()
                Button("Save Gesture") { saveDraft() }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func draftSummary(_ d: CustomGesture) -> String {
        let fingers = d.fingers == 1 ? "1 finger" : "\(d.fingers) fingers"
        let place = d.positional ? "in a fixed spot on the trackpad (edge or corner)" : "anywhere on the trackpad"
        return "New gesture captured: \(fingers), \(place)."
    }

    private func startCapture() {
        capturing = true
        model.captureNextGesture { g in
            gesture = g
            capturing = false
        }
    }

    // MARK: Creating a new gesture by recording

    private func startNewGesture() {
        model.cancelCapture()
        capturing = false
        samples = []
        recMessage = ""
        draft = nil
        rec = .recording
        model.captureStrokes { s in handleStroke(s) }
    }

    private func handleStroke(_ s: Stroke) {
        if let first = samples.first, first.fingers != s.fingers {
            samples = []
            recMessage = "The number of fingers differed between repetitions. Starting over."
        } else {
            recMessage = ""
        }
        samples.append(s)
        if samples.count >= 3 { finishRecording() }
    }

    private func finishRecording() {
        model.cancelStrokeCapture()
        switch StrokeMath.train(samples) {
        case .failed(let message):
            recMessage = message
            samples = []
            model.captureStrokes { s in handleStroke(s) }
        case .ok(let g):
            draft = g
            newName = "Custom Gesture \(model.customStore.items.count + 1)"
            rec = .naming
        }
    }

    private func saveDraft() {
        guard var g = draft else { return }
        let name = newName.trimmingCharacters(in: .whitespaces)
        let base = name.isEmpty ? "Custom Gesture" : name
        var candidate = base
        var suffix = 2
        while model.customStore.items.contains(where: { $0.name.localizedCaseInsensitiveCompare(candidate) == .orderedSame }) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }
        g.name = candidate
        model.customStore.add(g)
        model.refreshEngine()
        draft = nil
        rec = .idle
        gesture = g.gesture
    }

    private func cancelRecording() {
        model.cancelStrokeCapture()
        samples = []
        recMessage = ""
        draft = nil
        rec = .idle
    }

    private func deleteCustom(_ c: CustomGesture) {
        model.customStore.remove(c.id)
        model.store.removeMappings(gestureID: c.gesture.id)
        model.refreshEngine()
        if gesture == c.gesture { gesture = nil }
    }

    // MARK: Action

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isGlobal ? "2. What should it do?" : "2. What should it do in \(app.name)?").font(.headline)
                Spacer()
                if let action { Chip(text: action.title) }
            }
            HStack(spacing: 8) {
                ForEach(ActionCategory.allCases.filter { $0 != .appMenu || !isGlobal }) { category in
                    actionCategoryButton(category)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if action?.shortcutName != nil { shortcutNamingField }
                    switch actionCategory {
                    case .common:
                        basicList(Array(BasicActions.all.prefix(5)), title: "Common actions")
                    case .system:
                        systemList
                    case .shortcuts:
                        basicList(Array(BasicActions.all.dropFirst(5)), title: "More shortcuts")
                        suggestionList
                        Button(recordingKey ? "Press the shortcut… (Esc to cancel)" : "Record Keyboard Shortcut") {
                            recordingKey ? stopKeyRecord() : startKeyRecord()
                        }
                        .controlSize(.small)
                    case .appMenu:
                        moreSection
                    }
                    if isGlobal && actionCategory != .system {
                        Text("The action runs in the active app if it supports the shortcut.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: actionScrollHeight)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassCard()
    }

    private func actionCategoryButton(_ category: ActionCategory) -> some View {
        let selected = actionCategory == category
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) { actionCategory = category }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: category.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(category.title)
                    .font(.subheadline.weight(selected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .glassCard(radius: 11)
        .overlay {
            if selected {
                shape.strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.4)
            }
        }
        .background {
            if selected {
                shape.fill(Color.accentColor.opacity(0.1))
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var actionScrollHeight: CGFloat {
        switch actionCategory {
        case .common: 150
        case .system: 170
        case .shortcuts, .appMenu: 180
        }
    }

    private var shortcutNamingField: some View {
        HStack(spacing: 8) {
            Text("Shortcut name")
                .foregroundStyle(.secondary)
            TextField("For example: Save the document", text: $shortcutName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: shortcutName) { _, value in
                    guard var current = action, current.shortcutName != nil else { return }
                    current.shortcutName = value
                    current.title = value.isEmpty ? "Custom keyboard shortcut" : value
                    action = current
                }
        }
    }

    private let tileColumns = [GridItem(.flexible()), GridItem(.flexible())]
    private let gestureCategoryColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func tile(symbol: String, title: String, label: String?, selected: Bool,
                      pick: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button(action: pick) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 20)
                Text(title)
                Spacer()
                if let label {
                    Text(label).font(.callout.monospaced()).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(radius: 12)
        .overlay {
            if selected {
                shape.strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 1.5)
            }
        }
        .background {
            if selected {
                shape.fill(Color.accentColor.opacity(0.09))
            }
        }
        .contentShape(shape)
    }

    private func basicList(_ actions: [BasicAction], title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title)
            LazyVGrid(columns: tileColumns, spacing: 8) {
                ForEach(actions) { b in
                    tile(symbol: b.symbol, title: b.title, label: b.keyLabel,
                         selected: action?.kind == .shortcut && action?.keyCode == b.keyCode && action?.flags == b.flags) {
                        action = b.action
                    }
                }
            }
        }
    }

    private var systemList: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("System & Media")
            Text("Change volume and brightness, and control playback.")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: tileColumns, spacing: 8) {
                ForEach(MediaKey.allCases, id: \.rawValue) { k in
                    tile(symbol: k.symbol, title: k.title, label: nil, selected: action?.mediaKey == k) {
                        action = k.action
                    }
                }
            }
        }
    }

    private var suggestionList: some View {
        let suggestions = ShortcutSuggestions.common + ShortcutSuggestions.appSpecific(bundleID: app.bundleID)
        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Useful shortcuts")
            Text(isGlobal ? "Shortcuts are sent to the active app, if it supports them." : "Suggestions for this app. You can also pick any action from its menu below.")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: tileColumns, spacing: 8) {
                ForEach(suggestions) { item in
                    Button { action = item.action; shortcutName = item.name } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(item.name).fontWeight(.medium); Spacer(); Text(item.keyLabel).font(.callout.monospaced()).foregroundStyle(.secondary) }
                            Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .padding(9)
                    }
                    .buttonStyle(.bordered)
                    .tint(action?.shortcutName == item.name ? .accentColor : .secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isGlobal {
                Text("Actions from the \(app.name) menu")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                menuContent
            }
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        switch menuState {
        case .idle, .loading:
            HStack { ProgressView().controlSize(.small); Text("Reading the app's menus…") }
        case .notRunning:
            VStack(alignment: .leading, spacing: 8) {
                Text("The app isn't running right now. Launch it to read its actions.")
                    .foregroundStyle(.secondary)
                Button("Launch and Read Actions") { launchAndLoad() }
            }
        case .empty:
            VStack(alignment: .leading, spacing: 8) {
                Text("No actions found. Make sure Accessibility permission is granted and the app is open.")
                    .foregroundStyle(.secondary)
                Button("Try Again") { loadMenu() }
            }
        case .loaded:
            TextField("Search the app's actions", text: $query)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredEntries) { e in
                        let selected = action?.kind == .menu && action?.menuPath == e.path
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.title)
                                Text(e.section).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !e.shortcut.isEmpty {
                                Text(e.shortcut).font(.callout.monospaced()).foregroundStyle(.secondary)
                            }
                            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(selected ? Color.accentColor.opacity(0.15) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .glassCard(radius: 10)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let tail = e.path.suffix(2).joined(separator: " › ")
                            action = GestureAction(kind: .menu, title: tail, menuPath: e.path)
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
        }
    }

    private var filteredEntries: [MenuEntry] {
        let list = query.isEmpty ? entries : entries.filter { $0.id.localizedCaseInsensitiveContains(query) }
        return Array(list.prefix(300))
    }

    private func loadMenu() {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first else {
            menuState = .notRunning
            return
        }
        menuState = .loading
        let pid = running.processIdentifier
        Task { @MainActor in
            let list = await Task.detached(priority: .userInitiated) { MenuReader.read(pid: pid) }.value
            entries = list
            menuState = list.isEmpty ? .empty : .loaded
        }
    }

    private func launchAndLoad() {
        menuState = .loading
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path),
                                           configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            loadMenu()
        }
    }

    // MARK: Manual keyboard shortcut

    private func startKeyRecord() {
        stopKeyRecord()
        recordingKey = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 {   // Esc
                stopKeyRecord()
                return nil
            }
            let m = event.modifierFlags
            var flags: UInt64 = 0
            if m.contains(.command) { flags |= CGEventFlags.maskCommand.rawValue }
            if m.contains(.shift) { flags |= CGEventFlags.maskShift.rawValue }
            if m.contains(.option) { flags |= CGEventFlags.maskAlternate.rawValue }
            if m.contains(.control) { flags |= CGEventFlags.maskControl.rawValue }
            shortcutName = action?.shortcutName ?? ""
            action = GestureAction(kind: .shortcut, title: "Custom keyboard shortcut", shortcutName: shortcutName, keyCode: event.keyCode, flags: flags)
            shortcutName = ""
            stopKeyRecord()
            return nil
        }
    }

    private func stopKeyRecord() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
        recordingKey = false
    }

    // MARK: Saving

    private func save() {
        guard let g = gesture, let a = action else { return }
        if a.shortcutName != nil {
            var named = a
            let clean = (a.shortcutName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            named.shortcutName = clean.isEmpty ? "Shortcut · \(ShortcutFormat.symbols(flags: a.flags))\(keyName(a.keyCode))" : clean
            named.title = named.shortcutName!
            persist(g, named)
            return
        }
        persist(g, a)
    }

    private func keyName(_ code: UInt16) -> String {
        // Create a display fallback for a recorded shortcut without relying on keyboard layout state.
        let names: [UInt16: String] = [36:"↩",48:"⇥",49:"Space",51:"⌫",53:"⎋",123:"←",124:"→",125:"↓",126:"↑"]
        if let name = names[code] { return name }
        let chars: [UInt16: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",31:"O",32:"U",34:"I",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M"]
        return chars[code] ?? "Key \(code)"
    }

    private func persist(_ g: Gesture, _ a: GestureAction) {
        if let editing {
            model.store.updateMapping(app.bundleID, id: editing.id, gestureID: g.id, action: a)
        } else {
            model.store.setMapping(app.bundleID, gestureID: g.id, action: a)
        }
        model.refreshEngine()
        dismiss()
    }
}
