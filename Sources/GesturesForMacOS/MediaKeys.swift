import AppKit

/// System keys: volume, brightness, playback
enum MediaKey: String, CaseIterable, Sendable {
    case volumeUp, volumeDown, mute, brightnessUp, brightnessDown, playPause, next, previous

    var title: String {
        switch self {
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .mute: return "Mute"
        case .brightnessUp: return "Brightness Up"
        case .brightnessDown: return "Brightness Down"
        case .playPause: return "Play / Pause"
        case .next: return "Next Track"
        case .previous: return "Previous Track"
        }
    }

    var symbol: String {
        switch self {
        case .volumeUp: return "speaker.wave.3"
        case .volumeDown: return "speaker.wave.1"
        case .mute: return "speaker.slash"
        case .brightnessUp: return "sun.max"
        case .brightnessDown: return "sun.min"
        case .playPause: return "playpause"
        case .next: return "forward.end"
        case .previous: return "backward.end"
        }
    }

    fileprivate var code: Int {
        switch self {
        case .volumeUp: return 0
        case .volumeDown: return 1
        case .brightnessUp: return 2
        case .brightnessDown: return 3
        case .mute: return 7
        case .playPause: return 16
        case .next: return 17
        case .previous: return 18
        }
    }

    /// The action as stored in a gesture (marked via menuPath so the existing data structure does not change)
    var action: GestureAction {
        GestureAction(kind: .shortcut, title: title, keyCode: 0, flags: 0, menuPath: ["media", rawValue])
    }
}

extension GestureAction {
    var mediaKey: MediaKey? {
        guard menuPath.count == 2, menuPath[0] == "media" else { return nil }
        return MediaKey(rawValue: menuPath[1])
    }
}

enum MediaKeys {
    static func post(_ key: MediaKey) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = (key.code << 16) | ((down ? 0xA : 0xB) << 8)
            let e = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                       timestamp: 0, windowNumber: 0, context: nil,
                                       subtype: 8, data1: data1, data2: -1)
            e?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
