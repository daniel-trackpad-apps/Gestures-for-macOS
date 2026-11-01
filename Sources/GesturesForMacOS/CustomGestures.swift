import Foundation

struct StrokePoint: Codable, Hashable, Sendable {
    var x: Float
    var y: Float
}

/// A single recorded gesture: number of fingers and the path (32 equally spaced points)
struct Stroke: Sendable {
    let fingers: Int
    let points: [StrokePoint]
    let length: Float
    let duration: Double
}

/// A custom gesture learned from recordings
struct CustomGesture: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var fingers: Int
    var positional: Bool            // must be in the same place on the trackpad (edge or corner)
    var templates: [[StrokePoint]]  // the recordings themselves
    var shapeTolerance: Float
    var positionTolerance: Float

    var gesture: Gesture { Gesture(kind: "custom", fingers: fingers, direction: id) }
}

enum TrainResult {
    case ok(CustomGesture)
    case failed(String)
}

enum StrokeMath {
    static let count = 32

    static func length(_ p: [StrokePoint]) -> Float {
        var s: Float = 0
        if p.count > 1 {
            for i in 1..<p.count { s += hypot(p[i].x - p[i - 1].x, p[i].y - p[i - 1].y) }
        }
        return s
    }

    /// Splits the path into n equally spaced points
    static func resample(_ p: [StrokePoint], _ n: Int) -> [StrokePoint] {
        let total = length(p)
        guard total > 0, p.count > 1 else {
            return Array(repeating: p.first ?? StrokePoint(x: 0, y: 0), count: n)
        }
        let step = total / Float(n - 1)
        var out = [p[0]]
        var acc: Float = 0
        var prev = p[0]
        var i = 1
        while i < p.count && out.count < n {
            let cur = p[i]
            let d = hypot(cur.x - prev.x, cur.y - prev.y)
            if d > 0 && acc + d >= step {
                let t = (step - acc) / d
                let q = StrokePoint(x: prev.x + t * (cur.x - prev.x), y: prev.y + t * (cur.y - prev.y))
                out.append(q)
                prev = q
                acc = 0
            } else {
                acc += d
                prev = cur
                i += 1
            }
        }
        while out.count < n { out.append(p[p.count - 1]) }
        return out
    }

    /// Centers and scales, to compare shape regardless of position and size
    static func normalized(_ p: [StrokePoint]) -> [StrokePoint] {
        guard !p.isEmpty else { return p }
        let n = Float(p.count)
        let cx = p.map { $0.x }.reduce(0, +) / n
        let cy = p.map { $0.y }.reduce(0, +) / n
        let minX = p.map { $0.x }.min() ?? 0
        let maxX = p.map { $0.x }.max() ?? 0
        let minY = p.map { $0.y }.min() ?? 0
        let maxY = p.map { $0.y }.max() ?? 0
        let size = max(maxX - minX, maxY - minY, 0.0001)
        return p.map { StrokePoint(x: ($0.x - cx) / size, y: ($0.y - cy) / size) }
    }

    static func meanDistance(_ a: [StrokePoint], _ b: [StrokePoint]) -> Float {
        let n = min(a.count, b.count)
        guard n > 0 else { return .infinity }
        var s: Float = 0
        for i in 0..<n { s += hypot(a[i].x - b[i].x, a[i].y - b[i].y) }
        return s / Float(n)
    }

    /// Finds the custom gesture most similar to the path, if any
    static func match(_ s: Stroke, in list: [CustomGesture]) -> CustomGesture? {
        var best: CustomGesture?
        var bestScore = Float.infinity
        let sn = normalized(s.points)
        for g in list where g.fingers == s.fingers {
            var d = Float.infinity
            var dAbs = Float.infinity
            for t in g.templates {
                d = min(d, meanDistance(sn, normalized(t)))
                dAbs = min(dAbs, meanDistance(s.points, t))
            }
            guard d <= g.shapeTolerance else { continue }
            if g.positional && dAbs > g.positionTolerance { continue }
            let score = d / g.shapeTolerance
            if score < bestScore {
                bestScore = score
                best = g
            }
        }
        return best
    }

    static func token() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
    }

    /// Builds a custom gesture from several recordings
    static func train(_ strokes: [Stroke]) -> TrainResult {
        guard strokes.count >= 2, let fingers = strokes.first?.fingers else {
            return .failed("Not enough recordings were captured. Try again.")
        }
        let norm = strokes.map { normalized($0.points) }
        var maxShape: Float = 0
        var maxAbs: Float = 0
        for i in 0..<strokes.count {
            for j in (i + 1)..<strokes.count {
                maxShape = max(maxShape, meanDistance(norm[i], norm[j]))
                maxAbs = max(maxAbs, meanDistance(strokes[i].points, strokes[j].points))
            }
        }
        if maxShape > 0.30 {
            return .failed("The recordings differ too much from each other. Try to perform the gesture the same way each time.")
        }
        let nearEdge = strokes.allSatisfy { s in
            s.points.contains { $0.x < 0.1 || $0.x > 0.9 || $0.y < 0.1 || $0.y > 0.9 }
        }
        let positional = maxAbs < 0.12 && nearEdge
        if fingers == 1 && !positional {
            return .failed("A one-finger gesture must be at the edge or in a corner of the trackpad, in the same place each time. Otherwise it gets confused with normal cursor movement. Try again.")
        }
        let g = CustomGesture(
            id: token(),
            name: "",
            fingers: fingers,
            positional: positional,
            templates: strokes.map { $0.points },
            shapeTolerance: min(max(0.16, maxShape * 1.8), 0.40),
            positionTolerance: min(max(0.12, maxAbs * 1.8), 0.30))
        return .ok(g)
    }
}

/// Storage for custom gestures
@MainActor
@Observable
final class CustomGestureStore {
    private(set) var items: [CustomGesture] = []
    @ObservationIgnored private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GesturesForMacOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("custom-gestures.json")
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([CustomGesture].self, from: data) {
            items = list
        }
        CustomNames.shared.update(items)
    }

    func add(_ g: CustomGesture) {
        guard !items.contains(where: { $0.id == g.id }) else { return }
        items.append(g)
        persist()
    }

    func rename(_ id: String, to name: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        items[i].name = clean
        persist()
    }

    func remove(_ id: String) {
        items.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
        CustomNames.shared.update(items)
    }
}
