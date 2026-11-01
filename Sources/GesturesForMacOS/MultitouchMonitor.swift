import AppKit

private typealias MTCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
private typealias MTCreateListFn = @convention(c) () -> Unmanaged<CFArray>?
private typealias MTRegisterFn = @convention(c) (UnsafeMutableRawPointer, MTCallback) -> Void
private typealias MTStartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
private typealias MTStopFn = @convention(c) (UnsafeMutableRawPointer) -> Void

private var activeMonitor: MultitouchMonitor?

private let touchCallback: MTCallback = { _, data, count, ts, _ in
    activeMonitor?.frame(data, Int(count), ts)
    return 0
}

/// Reads the trackpad directly to detect three/four-finger gestures, taps, holds, edges and corners.
/// Also feeds every frame to the stroke engine (edge slide and custom gestures).
final class MultitouchMonitor {
    var onGesture: (@Sendable (Gesture) -> Void)?

    private var devices: CFArray?
    private var unregisterFn: MTRegisterFn?
    private var stopFn: MTStopFn?

    private typealias Pts = [Int32: (x: Float, y: Float)]

    private var active = false
    private var peak = 0
    private var peakFrames = 0
    private var startTS: Double = 0
    private var lastTS: Double = 0
    private var firstX: Float = 0
    private var firstY: Float = 0
    private var startPts: Pts = [:]
    private var lastPts: Pts = [:]

    func start() {
        guard devices == nil else { return }
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let h = dlopen(path, RTLD_NOW),
              let c = dlsym(h, "MTDeviceCreateList"),
              let r = dlsym(h, "MTRegisterContactFrameCallback"),
              let u = dlsym(h, "MTUnregisterContactFrameCallback"),
              let s = dlsym(h, "MTDeviceStart"),
              let t = dlsym(h, "MTDeviceStop") else { return }

        let create = unsafeBitCast(c, to: MTCreateListFn.self)
        let register = unsafeBitCast(r, to: MTRegisterFn.self)
        let startDev = unsafeBitCast(s, to: MTStartFn.self)
        unregisterFn = unsafeBitCast(u, to: MTRegisterFn.self)
        stopFn = unsafeBitCast(t, to: MTStopFn.self)

        guard let list = create()?.takeRetainedValue() else { return }
        devices = list
        activeMonitor = self
        for i in 0..<CFArrayGetCount(list) {
            guard let p = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: p)
            register(dev, touchCallback)
            startDev(dev, 0)
        }
    }

    func stop() {
        guard let list = devices else { return }
        for i in 0..<CFArrayGetCount(list) {
            guard let p = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: p)
            unregisterFn?(dev, touchCallback)
            stopFn?(dev)
        }
        devices = nil
        activeMonitor = nil
        active = false
    }

    fileprivate func frame(_ data: UnsafeMutableRawPointer?, _ count: Int, _ ts: Double) {
        var pts: Pts = [:]
        if let data {
            for i in 0..<count {
                let base = data + i * 96
                // state 4 = finger touching the trackpad
                guard base.load(fromByteOffset: 20, as: Int32.self) == 4 else { continue }
                let id = base.load(fromByteOffset: 24, as: Int32.self)
                let x = base.load(fromByteOffset: 32, as: Float.self)
                let y = base.load(fromByteOffset: 36, as: Float.self)
                pts[id] = (x, y)
            }
        }
        let n = pts.count

        // The stroke engine runs first, so it can mark the gesture as already handled
        StrokeEngine.shared.frame(pts.values.map { (x: $0.x, y: $0.y) }, ts)

        if n > 0 {
            if !active {
                active = true; peak = 0; peakFrames = 0; startTS = ts
                firstX = pts.values.map { $0.x }.reduce(0, +) / Float(n)
                firstY = pts.values.map { $0.y }.reduce(0, +) / Float(n)
            }
            lastTS = ts
            if n > peak { peak = n; peakFrames = 0 }
            if n == peak {
                peakFrames += 1
                if peakFrames == 1 || peakFrames == 4 { startPts = pts }
                lastPts = pts
            }
        } else if active {
            active = false
            finish()
        }
    }

    private func centroid(_ p: Pts, _ ids: [Int32]) -> (x: Float, y: Float) {
        let c = Float(ids.count)
        return (ids.map { p[$0]!.x }.reduce(0, +) / c, ids.map { p[$0]!.y }.reduce(0, +) / c)
    }

    private func finish() {
        let k = peak
        guard k >= 1, k <= 4 else { return }
        let ids = startPts.keys.filter { lastPts[$0] != nil }
        guard !ids.isEmpty else { return }

        let dur = lastTS - startTS
        let sc = centroid(startPts, ids)
        let lc = centroid(lastPts, ids)
        let dx = lc.x - sc.x
        let dy = lc.y - sc.y
        let moved = hypot(dx, dy)

        var s0: Float = 0, s1: Float = 0, rot: Float = 0
        for id in ids {
            let a = startPts[id]!, b = lastPts[id]!
            s0 += hypot(a.x - sc.x, a.y - sc.y)
            s1 += hypot(b.x - lc.x, b.y - lc.y)
            var d = atan2(b.y - lc.y, b.x - lc.x) - atan2(a.y - sc.y, a.x - sc.x)
            if d > .pi { d -= 2 * .pi }
            if d < -.pi { d += 2 * .pi }
            rot += d
        }
        s0 /= Float(ids.count); s1 /= Float(ids.count); rot /= Float(ids.count)
        let ratio = s0 > 0.01 ? s1 / s0 : 1

        var g: Gesture?
        if k >= 3 {
            if moved < 0.12, ratio < 0.75 || ratio > 1.35 {
                g = Gesture(kind: "pinch", fingers: k, direction: ratio < 1 ? "in" : "out")
            } else if moved < 0.12, abs(rot) > 0.35 {
                g = Gesture(kind: "rotate", fingers: k, direction: rot > 0 ? "ccw" : "cw")
            } else if moved >= 0.15, dur < 0.9 {
                let d = abs(dx) > abs(dy) ? (dx > 0 ? "right" : "left") : (dy > 0 ? "up" : "down")
                g = Gesture(kind: "swipe", fingers: k, direction: d)
            } else if moved < 0.04, dur < 0.25 {
                g = Gesture(kind: "tap", fingers: k, direction: "")
            } else if moved < 0.04, dur > 0.8 {
                g = Gesture(kind: "hold", fingers: k, direction: "")
            }
        } else if k == 2 {
            if moved < 0.03, dur < 0.25 { g = Gesture(kind: "tap", fingers: 2, direction: "") }
        } else {
            if moved < 0.03, dur < 0.25 {
                let xs = firstX < 0.2, xl = firstX > 0.8, yb = firstY < 0.2, yt = firstY > 0.8
                if (xs || xl) && (yb || yt) {
                    let d = (yt ? "t" : "b") + (xs ? "l" : "r")
                    g = Gesture(kind: "corner", fingers: 1, direction: d)
                }
            } else if dur < 0.6 {
                if firstX < 0.06, dx > 0.25, abs(dx) > 2 * abs(dy) { g = Gesture(kind: "edge", fingers: 1, direction: "left") }
                else if firstX > 0.94, dx < -0.25, abs(dx) > 2 * abs(dy) { g = Gesture(kind: "edge", fingers: 1, direction: "right") }
                else if firstY > 0.94, dy < -0.25, abs(dy) > 2 * abs(dx) { g = Gesture(kind: "edge", fingers: 1, direction: "top") }
                else if firstY < 0.06, dy > 0.25, abs(dy) > 2 * abs(dx) { g = Gesture(kind: "edge", fingers: 1, direction: "bottom") }
            }
        }

        // A gesture that was already handled (edge slide, custom gesture or recording) is not detected again as a regular gesture
        if let g, !StrokeEngine.shared.consumed {
            let cb = onGesture
            DispatchQueue.main.async { cb?(g) }
        }
    }
}
