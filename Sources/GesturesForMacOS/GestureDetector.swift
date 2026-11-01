import AppKit

/// Listens for gestures. When paused there is no listening, so no resources are used.
/// Two-finger gestures (scroll/pinch/rotate) come from system events, the rest from MultitouchMonitor.
final class GestureDetector {
    var onGesture: (@Sendable (Gesture) -> Void)?

    private let multitouch = MultitouchMonitor()
    var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var dx: CGFloat = 0
    private var dy: CGFloat = 0
    private var startTime: TimeInterval = 0
    private var magnification: CGFloat = 0
    private var rotation: Float = 0

    private let swipeDistance: CGFloat = 80
    private let swipeMaxDuration: TimeInterval = 0.9
    private let pinchAmount: CGFloat = 0.15
    private let rotateDegrees: Float = 20

    func start() {
        guard tap == nil else { return }
        // Permission is granted in System Settings. Trying to create a tap without approval
        // may show the system prompt again on every launch.
        guard CGPreflightListenEventAccess() else { return }
        multitouch.onGesture = { [weak self] g in self?.onGesture?(g) }
        multitouch.start()

        // 18 rotate, 22 scroll, 29 gesture, 30 pinch, 31 swipe
        let types: [UInt64] = [18, 22, 29, 30, 31]
        let mask = types.reduce(UInt64(0)) { $0 | (UInt64(1) << $1) }

        let callback: CGEventTapCallBack = { _, type, cgEvent, refcon in
            guard let refcon else { return Unmanaged.passUnretained(cgEvent) }
            let det = Unmanaged<GestureDetector>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = det.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(cgEvent)
            }
            if let ns = NSEvent(cgEvent: cgEvent) { det.handle(ns) }
            return Unmanaged.passUnretained(cgEvent)
        }

        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return
        }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    func stop() {
        multitouch.stop()
        if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
            CFMachPortInvalidate(t)
        }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
    }

    private func fire(_ kind: String, _ fingers: Int, _ direction: String) {
        onGesture?(Gesture(kind: kind, fingers: fingers, direction: direction))
    }

    fileprivate func handle(_ e: NSEvent) {
        switch e.type {

        case .scrollWheel:  // horizontal two-finger swipe
            if !e.momentumPhase.isEmpty { return }
            let natural = e.isDirectionInvertedFromDevice
            if e.phase == .began {
                dx = 0; dy = 0; startTime = e.timestamp
            }
            if e.phase == .began || e.phase == .changed {
                dx += natural ? e.scrollingDeltaX : -e.scrollingDeltaX
                dy += natural ? -e.scrollingDeltaY : e.scrollingDeltaY
            } else if e.phase == .ended {
                let quick = (e.timestamp - startTime) < swipeMaxDuration
                if quick, abs(dx) > swipeDistance, abs(dx) > 2 * abs(dy) {
                    fire("swipe", 2, dx < 0 ? "left" : "right")
                }
                dx = 0; dy = 0
            }

        case .magnify:
            if e.phase == .began { magnification = 0 }
            if e.phase == .began || e.phase == .changed { magnification += e.magnification }
            if e.phase == .ended {
                if magnification > pinchAmount { fire("pinch", 2, "out") }
                else if magnification < -pinchAmount { fire("pinch", 2, "in") }
                magnification = 0
            }

        case .rotate:
            if e.phase == .began { rotation = 0 }
            if e.phase == .began || e.phase == .changed { rotation += e.rotation }
            if e.phase == .ended {
                if rotation > rotateDegrees { fire("rotate", 2, "ccw") }
                else if rotation < -rotateDegrees { fire("rotate", 2, "cw") }
                rotation = 0
            }

        default: break
        }
    }
}
