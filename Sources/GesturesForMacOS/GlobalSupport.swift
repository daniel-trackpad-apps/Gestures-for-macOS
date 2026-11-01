import Foundation

/// Special identifier for the "All Apps" entry. Gestures defined in it work in every app.
let globalAppID = "*"

extension AppStore {
    /// Makes sure a global entry is always at the top of the list
    func ensureGlobal() {
        guard app(globalAppID) == nil else { return }
        apps.insert(AppEntry(bundleID: globalAppID, name: "All Apps", path: ""), at: 0)
        save()
    }

    /// The action for a gesture: first the app's own setup, otherwise the global one
    func effectiveAction(bundleID: String, gestureID: String) -> GestureAction? {
        action(bundleID: bundleID, gestureID: gestureID)
            ?? action(bundleID: globalAppID, gestureID: gestureID)
    }

    /// Removes every setup that uses a given gesture (e.g. after deleting a custom gesture)
    func removeMappings(gestureID: String) {
        for i in apps.indices {
            apps[i].mappings.removeAll { $0.gestureID == gestureID }
        }
        save()
    }
}
