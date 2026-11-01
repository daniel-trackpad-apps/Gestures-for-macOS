import Foundation

private struct Sample {
    var x: Float
    var y: Float
    var t: Double
}

/// Receives the state of the fingers on the trackpad at every moment, and detects:
/// 1. Edge slide (continuous), only if an action is set up for it
/// 2. Custom gestures learned from recordings
/// 3. In recording mode: hands the path to the setup window
/// Works only while there are fingers on the trackpad.
final class StrokeEngine: @unchecked Sendable {
    static let shared = StrokeEngine()

    /// Called on the main queue
    var onGesture: ((Gesture) -> Void)?
    var onStroke: ((Stroke) -> Void)?

    /// Whether the current gesture was already handled here, so it must not be detected again as a regular gesture
    private(set) var consumed = false

    private let lock = NSLock()
    private var customs: [CustomGesture] = []
    private var slidesOn = false
    private var recordingOn = false

    // State of the current gesture (accessible only from the trackpad thread)
    private var active = false
    private var peak = 0
    private var closed = false
    private var samples: [Sample] = []

    private var slideEdge: Character?
    private var slideDead = false
    private var slideStarted = false
    private var slideAnchor: Float = 0
    private var lastStepTS: Double = 0

    private let edgeZone: Float = 0.10

    func configure(customs: [CustomGesture], slides: Bool) {
        lock.lock()
        self.customs = customs
        slidesOn = slides
        lock.unlock()
    }

    func setRecording(_ on: Bool) {
        lock.lock()
        recordingOn = on
        lock.unlock()
    }

    private func config() -> (customs: [CustomGesture], slides: Bool, recording: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (customs, slidesOn, recordingOn)
    }

    func frame(_ pts: [(x: Float, y: Float)], _ ts: Double) {
        let n = pts.count
        if n == 0 {
            if active {
                active = false
                finalize()
            }
            return
        }
        let cfg = config()
        var cx: Float = 0
        var cy: Float = 0
        for p in pts { cx += p.x; cy += p.y }
        cx /= Float(n)
        cy /= Float(n)

        if !active {
            active = true
            consumed = false
            peak = 0
            closed = false
            samples.removeAll(keepingCapacity: true)
            slideStarted = false
            slideEdge = nil
            slideDead = (n != 1)
            lastStepTS = 0
            if n == 1 {
                let dR = 1 - cx
                let dL = cx
                let dT = 1 - cy
                let dB = cy
                let m = min(min(dR, dL), min(dT, dB))
                if m < edgeZone {
                    if m == dR { slideEdge = "r" }
                    else if m == dL { slideEdge = "l" }
                    else if m == dT { slideEdge = "t" }
                    else { slideEdge = "b" }
                    slideAnchor = (slideEdge == "r" || slideEdge == "l") ? cy : cx
                }
            }
        }

        if cfg.slides && !cfg.recording { trackSlide(n, cx, cy, ts) }

        // Recording the path, only when needed
        guard cfg.recording || !cfg.customs.isEmpty else { return }
        if n > peak {
            peak = n
            samples.removeAll(keepingCapacity: true)
            closed = false
        }
        if n == peak && !closed {
            if samples.count < 600 { samples.append(Sample(x: cx, y: cy, t: ts)) }
        } else if n < peak {
            closed = true
        }
    }

    /// Edge slide: one finger that starts at the edge and moves along it. Each step triggers the action.
    private func trackSlide(_ n: Int, _ cx: Float, _ cy: Float, _ ts: Double) {
        guard let e = slideEdge, !slideDead else { return }
        if n != 1 {
            slideDead = true
            return
        }
        let perp: Float
        let along: Float
        switch e {
        case "r": perp = 1 - cx; along = cy
        case "l": perp = cx; along = cy
        case "t": perp = 1 - cy; along = cx
        default: perp = cy; along = cx
        }
        if perp > edgeZone * 2.4 {   // moved away from the edge
            slideDead = true
            return
        }
        let d = along - slideAnchor
        let need: Float = slideStarted ? 0.045 : 0.08
        guard abs(d) >= need, ts - lastStepTS >= 0.03 else { return }
        slideAnchor = along
        slideStarted = true
        lastStepTS = ts
        consumed = true
        let vertical = (e == "r" || e == "l")
        let dir = vertical ? (d > 0 ? "up" : "down") : (d > 0 ? "right" : "left")
        emit(Gesture(kind: "slide", fingers: 1, direction: String(e) + dir))
    }

    private func finalize() {
        let cfg = config()
        guard cfg.recording || (!cfg.customs.isEmpty && !consumed) else { return }
        guard samples.count >= 4 else { return }
        let raw = samples.map { StrokePoint(x: $0.x, y: $0.y) }
        let len = StrokeMath.length(raw)
        guard len >= 0.06 else { return }
        let stroke = Stroke(fingers: peak,
                            points: StrokeMath.resample(raw, StrokeMath.count),
                            length: len,
                            duration: samples[samples.count - 1].t - samples[0].t)
        if cfg.recording {
            consumed = true
            let cb = onStroke
            DispatchQueue.main.async { cb?(stroke) }
            return
        }
        if let hit = StrokeMath.match(stroke, in: cfg.customs) {
            consumed = true
            emit(hit.gesture)
        }
    }

    private func emit(_ g: Gesture) {
        let cb = onGesture
        DispatchQueue.main.async { cb?(g) }
    }
}
