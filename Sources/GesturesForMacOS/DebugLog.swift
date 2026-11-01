import Foundation

/// Diagnostic log: ~/Library/Application Support/GesturesForMacOS/debug.log
/// Written only when a gesture is detected, so it stays light. Trimmed automatically as it grows.
enum DebugLog {
    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GesturesForMacOS/debug.log")
    }

    static func write(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = "\(stamp) \(line)\n".data(using: .utf8) else { return }
        let u = url
        if let h = try? FileHandle(forWritingTo: u) {
            defer { try? h.close() }
            if let size = try? h.seekToEnd(), size > 200_000 { try? h.truncate(atOffset: 0) }
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: u)
        }
    }
}
