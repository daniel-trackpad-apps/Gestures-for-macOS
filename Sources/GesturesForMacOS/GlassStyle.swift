import SwiftUI

extension View {
    /// Glass card: Liquid Glass when the system supports it, otherwise a regular translucent material.
    @ViewBuilder
    func glassCard(radius: CGFloat = 18) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        #if compiler(>=6.2) && !NO_LIQUID_GLASS
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.materialCard(shape)
        }
        #else
        self.materialCard(shape)
        #endif
    }

    func materialCard(_ shape: RoundedRectangle) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

/// App icon. With no path (the global entry) a globe is shown.
struct AppIconView: View {
    let path: String
    var size: CGFloat = 44

    var body: some View {
        if path.isEmpty {
            Image(systemName: "globe")
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(LinearGradient(colors: [.blue, .indigo], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        }
    }
}

/// A small capsule showing an action name or shortcut.
struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.white.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
    }
}
