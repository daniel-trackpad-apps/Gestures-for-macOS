import SwiftUI
import UniformTypeIdentifiers

struct AddAppSheet: View {
    let model: AppModel
    let onAdded: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                && $0.bundleURL != nil
                && model.store.app($0.bundleIdentifier ?? "") == nil
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add App").font(.title2.bold())

            Button { browse() } label: {
                Label("Choose from Installed Apps", systemImage: "folder")
            }
            .controlSize(.large)

            Text("Or pick a currently running app").font(.headline).padding(.top, 4)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(runningApps, id: \.processIdentifier) { app in
                        Button { add(app) } label: {
                            HStack(spacing: 10) {
                                Image(nsImage: app.icon ?? NSImage())
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                Text(app.localizedName ?? "—")
                                Spacer()
                                Image(systemName: "plus.circle").foregroundStyle(.tint)
                            }
                            .padding(8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .glassCard(radius: 12)
                    }
                }
            }
            .frame(minHeight: 200)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 440, height: 480)
    }

    private func add(_ app: NSRunningApplication) {
        guard let url = app.bundleURL, let id = model.store.add(url: url) else { return }
        onAdded(id)
        dismiss()
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        if panel.runModal() == .OK, let url = panel.url, let id = model.store.add(url: url) {
            onAdded(id)
            dismiss()
        }
    }
}
