import SwiftUI

struct AppDetailView: View {
    let model: AppModel
    let bundleID: String
    let back: () -> Void

    private struct SheetItem: Identifiable {
        let id = UUID()
        let mapping: Mapping?   // nil = new gesture
    }

    @State private var sheet: SheetItem?
    @State private var confirmRemove = false

    var body: some View {
        if let app = model.store.app(bundleID) {
            content(app)
        }
    }

    private func subtitle(_ app: AppEntry) -> String {
        let n = app.mappings.count
        if app.bundleID == globalAppID {
            return n == 0 ? "No global gestures yet" : "Gestures for all apps: \(n)"
        }
        return n == 0 ? "No gestures yet" : "Gestures: \(n)"
    }

    private func content(_ app: AppEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: back) {
                Label("Apps", systemImage: "chevron.backward")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)

            HStack(spacing: 14) {
                AppIconView(path: app.path, size: 60)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.largeTitle.bold())
                    Text(subtitle(app)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { sheet = SheetItem(mapping: nil) } label: { Label("Add Gesture", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }

            if app.mappings.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "hand.draw")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(app.bundleID == globalAppID
                         ? "Add a global gesture, for example a two-finger swipe for Back, and it will work in every app that supports it"
                         : "Add a gesture and choose what it does in this app")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(app.mappings) { m in mappingRow(m, app) }
                    }
                    .padding(.vertical, 4)
                }
            }

            if app.bundleID != globalAppID {
                HStack {
                    Spacer()
                    Button("Remove App", role: .destructive) { confirmRemove = true }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
        .sheet(item: $sheet) { item in
            AddMappingSheet(model: model, app: app, editing: item.mapping)
                .environment(\.layoutDirection, .leftToRight)
        }
        .confirmationDialog("Remove \(app.name) and all of its gestures?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) {
                model.removeApp(app.bundleID)
                back()
            }
        }
    }

    private func mappingRow(_ m: Mapping, _ app: AppEntry) -> some View {
        let gesture = Gesture(id: m.gestureID)
        return HStack(spacing: 12) {
            Image(systemName: gesture?.displaySymbol ?? "hand.point.up.left")
                .font(.title3)
                .frame(width: 30)
                .foregroundStyle(.tint)
            Text(gesture?.displayTitle ?? m.gestureID).font(.headline)
            Image(systemName: "arrow.forward").foregroundStyle(.tertiary)
            Chip(text: m.action.title)
            if let warn = gesture.flatMap({ SystemGestures.conflict(for: $0) }) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("macOS also uses this gesture: \(warn)")
            }
            Spacer()
            Image(systemName: "pencil").foregroundStyle(.tertiary)
            Button {
                model.store.removeMapping(app.bundleID, m.id)
                model.refreshEngine()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture { sheet = SheetItem(mapping: m) }
        .glassCard()
        .help("Click to edit")
    }
}
