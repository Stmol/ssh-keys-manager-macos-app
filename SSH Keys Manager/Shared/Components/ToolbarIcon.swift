import SwiftUI

struct AppToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && isEnabled ? 0.96 : 1)
            .opacity(configuration.isPressed && isEnabled ? 0.86 : 1)
            .animation(AppControlMetrics.stateAnimation, value: configuration.isPressed)
    }
}

struct ToolbarIcon: View {
    let systemName: String
    let isHovered: Bool
    var isPressed: Bool = false
    var size: CGFloat = 28
    var iconSize: CGFloat = 16
    var cornerRadius: CGFloat = AppControlMetrics.iconButtonCornerRadius

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: iconSize, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(foregroundColor)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(isPressed && isEnabled ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.48)
            .animation(AppControlMetrics.stateAnimation, value: isPressed)
    }

    private var foregroundColor: Color {
        guard isEnabled else {
            return .secondary
        }

        return isHovered || isPressed ? .primary : .secondary
    }

    private var backgroundColor: Color {
        guard isEnabled else {
            return Color(nsColor: .controlBackgroundColor).opacity(0.5)
        }

        if isPressed {
            return Color(nsColor: .controlAccentColor).opacity(colorScheme == .dark ? 0.22 : 0.14)
        }

        if isHovered {
            return Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07)
        }

        return Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        guard isEnabled else {
            return Color(nsColor: .separatorColor).opacity(0.2)
        }

        return Color(nsColor: .separatorColor).opacity(isHovered || isPressed ? 0.58 : 0.34)
    }
}
