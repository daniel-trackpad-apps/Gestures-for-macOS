import AppKit

/// A basic action that is always offered (a standard macOS keyboard shortcut).
struct BasicAction: Identifiable {
    let title: String
    let symbol: String
    let keyLabel: String
    let keyCode: UInt16
    let flags: UInt64
    var id: String { title }
    var action: GestureAction {
        GestureAction(kind: .shortcut, title: title, keyCode: keyCode, flags: flags)
    }
}

enum BasicActions {
    private static let cmd = CGEventFlags.maskCommand.rawValue
    private static let ctrl = CGEventFlags.maskControl.rawValue
    private static let shift = CGEventFlags.maskShift.rawValue
    /// In right-to-left languages (e.g. Hebrew), Safari arranges its tabs right to left
    private static let rtl = Locale.Language(identifier: Locale.preferredLanguages.first ?? "en").characterDirection == .rightToLeft

    static let all: [BasicAction] = [
        BasicAction(title: "Back", symbol: "chevron.backward", keyLabel: "⌘[", keyCode: 33, flags: cmd),
        BasicAction(title: "Forward", symbol: "chevron.forward", keyLabel: "⌘]", keyCode: 30, flags: cmd),
        BasicAction(title: "Close Window", symbol: "xmark.circle", keyLabel: "⌘W", keyCode: 13, flags: cmd),
        BasicAction(title: "New Window", symbol: "plus.rectangle", keyLabel: "⌘N", keyCode: 45, flags: cmd),
        BasicAction(title: "New Tab", symbol: "plus.square.on.square", keyLabel: "⌘T", keyCode: 17, flags: cmd),
        BasicAction(title: "Tab to the Left", symbol: "arrow.left.to.line", keyLabel: rtl ? "⇧⌘]" : "⇧⌘[", keyCode: rtl ? 30 : 33, flags: cmd | shift),
        BasicAction(title: "Tab to the Right", symbol: "arrow.right.to.line", keyLabel: rtl ? "⇧⌘[" : "⇧⌘]", keyCode: rtl ? 33 : 30, flags: cmd | shift),
        BasicAction(title: "Reload", symbol: "arrow.clockwise", keyLabel: "⌘R", keyCode: 15, flags: cmd),
        BasicAction(title: "Copy", symbol: "doc.on.doc", keyLabel: "⌘C", keyCode: 8, flags: cmd),
        BasicAction(title: "Paste", symbol: "doc.on.clipboard", keyLabel: "⌘V", keyCode: 9, flags: cmd),
    ]
}
