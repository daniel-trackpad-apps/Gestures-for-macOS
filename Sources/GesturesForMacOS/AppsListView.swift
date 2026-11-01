import SwiftUI

struct AppsListView: View {
    let model: AppModel
    let open: (String) -> Void
    let add: () -> Void
    @AppStorage("showInDock") private var showDock = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gestures for macOS").font(.largeTitle.bold())
                    Text("Set up gestures for all apps, or for a specific app")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: add) { Label("Add App", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }

            if !model.accessibilityOK || !model.inputMonitoringOK { permissionsBanner }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.store.apps) { app in
                        AppRow(app: app, open: { open(app.bundleID) })
                    }
                    if model.store.apps.count <= 1 {
                        Text("Want different gestures for a specific app? Click \"Add App\".")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                }
                .padding(.vertical, 4)
            }

            StatusBar(model: model)
            footer
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }

    private var permissionsBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Permissions needed", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("To detect gestures and run actions, the app needs to be approved in System Settings. After approving, come back here and everything updates by itself.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                if !model.inputMonitoringOK {
                Button("Open Input Monitoring") { model.openSettings(.input) }
                }
                if !model.accessibilityOK {
                Button("Open Accessibility") { model.openSettings(.accessibility) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var footer: some View {
        HStack {
            Toggle("Listen for Gestures", isOn: Binding(
                get: { !model.paused },
                set: { model.setPaused(!$0) }))
                .toggleStyle(.switch)
            Toggle("Show in Dock", isOn: Binding(
                get: { showDock },
                set: { showDock = $0; DockMode.apply($0) }))
                .toggleStyle(.switch)
            Spacer()
            Text(model.lastGesture)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(radius: 14)
    }
}

private struct AppRow: View {
    let app: AppEntry
    let open: () -> Void
    @State private var hovering = false

    private var subtitle: String {
        let n = app.mappings.count
        if app.bundleID == globalAppID {
            return n == 0 ? "Works in all apps · No gestures yet" : "Works in all apps · Gestures: \(n)"
        }
        return n == 0 ? "No gestures set up" : "Gestures: \(n)"
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                AppIconView(path: app.path)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard()
        .scaleEffect(hovering ? 1.01 : 1)
        .animation(.smooth(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }
}
