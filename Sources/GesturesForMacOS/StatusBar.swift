import SwiftUI

/// A line showing whether the app is really listening for gestures.
struct StatusBar: View {
    let model: AppModel

    private var title: String {
        if model.paused { return "Listening is paused" }
        return model.listening ? "Listening is active" : "Listening is not active"
    }

    private var detail: String {
        if model.paused { return "Turn on the switch below to start" }
        if model.listening { return "Gestures detected since launch: \(model.detectedCount)" }
        return "Input Monitoring permission may be missing, or the app needs a restart after granting it"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.listening ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(model.listening ? Color.green : Color.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !model.listening && !model.paused {
                Button("Restart") { model.relaunch() }
            }
        }
        .padding(12)
        .glassCard(radius: 14)
    }
}
