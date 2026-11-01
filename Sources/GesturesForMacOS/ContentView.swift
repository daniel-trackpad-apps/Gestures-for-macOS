import SwiftUI

struct ContentView: View {
    let model: AppModel
    @State private var selected: String?
    @State private var showAddApp = false

    var body: some View {
        ZStack {
            if let id = selected, model.store.app(id) != nil {
                AppDetailView(model: model, bundleID: id, back: { selected = nil })
                    .transition(.opacity)
            } else {
                AppsListView(model: model, open: { selected = $0 }, add: { showAddApp = true })
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.25), value: selected)
        .onChange(of: model.addAppRequest) { _, _ in showAddApp = true }
        .padding(.top, 38)   // room for the window buttons
        .ignoresSafeArea()
        .environment(\.layoutDirection, .leftToRight)
        .frame(minWidth: 520, minHeight: 540)
        .sheet(isPresented: $showAddApp) {
            AddAppSheet(model: model) { selected = $0 }
                .environment(\.layoutDirection, .leftToRight)
        }
    }
}
