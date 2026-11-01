import Foundation

/// Checks whether a gesture clashes with gestures set in the macOS trackpad settings.
/// If a setting is not found, no conflict is reported.
enum SystemGestures {
    private static let domains = [
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad",
    ]

    private static func values(_ key: String) -> [Int] {
        domains.compactMap { domain in
            guard let v = CFPreferencesCopyAppValue(key as CFString, domain as CFString) else { return nil }
            return (v as? NSNumber)?.intValue
        }
    }

    private static func isOn(_ key: String) -> Bool { values(key).contains { $0 != 0 } }
    private static func has(_ key: String, _ value: Int) -> Bool { values(key).contains(value) }

    /// "Swipe between pages" with two fingers (default: on)
    private static var swipeBetweenPagesTwoFingers: Bool {
        guard let n = UserDefaults.standard.object(forKey: "AppleEnableSwipeNavigateWithScrolls") as? NSNumber else {
            return true
        }
        return n.boolValue
    }

    /// A short description of what the system does with the gesture, or nil if there is no conflict.
    static func conflict(for g: Gesture) -> String? {
        switch g.kind {
        case "swipe":
            let horizontal = g.direction == "left" || g.direction == "right"
            switch g.fingers {
            case 2:
                if horizontal && swipeBetweenPagesTwoFingers {
                    return "Swipe between pages (Back and Forward in Safari, Finder and other apps)"
                }
                return nil
            case 3:
                if isOn("TrackpadThreeFingerDrag") { return "Three-finger drag" }
                if horizontal {
                    if has("TrackpadThreeFingerHorizSwipeGesture", 2) { return "Switch between full-screen apps (three fingers)" }
                    if has("TrackpadThreeFingerHorizSwipeGesture", 1) { return "Swipe between pages (three fingers)" }
                } else if isOn("TrackpadThreeFingerVertSwipeGesture") {
                    return "Mission Control and App Exposé (three fingers)"
                }
                return nil
            case 4:
                if horizontal {
                    return isOn("TrackpadFourFingerHorizSwipeGesture") ? "Switch between full-screen apps (four fingers)" : nil
                }
                return isOn("TrackpadFourFingerVertSwipeGesture") ? "Mission Control and App Exposé (four fingers)" : nil
            default:
                return nil
            }
        case "pinch":
            if g.fingers == 2 { return isOn("TrackpadPinch") ? "Zoom in and out (two fingers)" : nil }
            if g.fingers == 4 {
                if g.direction == "in" {
                    return isOn("TrackpadFourFingerPinchGesture") ? "Launchpad (four-finger pinch)" : nil
                }
                return isOn("TrackpadFiveFingerPinchGesture") ? "Show Desktop (four-finger spread)" : nil
            }
            return nil
        case "rotate":
            if g.fingers == 2 { return isOn("TrackpadRotate") ? "Rotate (two fingers)" : nil }
            return nil
        case "tap":
            if g.fingers == 3 {
                return isOn("TrackpadThreeFingerTapGesture") ? "Look Up (three-finger tap)" : nil
            }
            if g.fingers == 2 {
                return (isOn("Clicking") && isOn("TrackpadRightClick")) ? "Secondary click (two-finger tap)" : nil
            }
            return nil
        case "hold":
            if g.fingers == 3 { return isOn("TrackpadThreeFingerDrag") ? "Three-finger drag" : nil }
            return nil
        case "corner":
            let v = values("TrackpadCornerSecondaryClick")
            if g.direction == "br", v.contains(2) { return "Secondary click in the bottom-right corner" }
            if g.direction == "bl", v.contains(1) { return "Secondary click in the bottom-left corner" }
            return nil
        default:
            return nil
        }
    }
}
