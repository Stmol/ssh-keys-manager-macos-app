import SwiftUI

enum AppButtonTone {
    case secondary
    case primary
    case destructive
}

struct AppButton: View {
    private let buttonHeight: CGFloat = AppControlMetrics.buttonHeight

    private let title: String
    private let systemImage: String?
    private let tone: AppButtonTone
    private let expands: Bool
    private let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    init(
        _ title: String,
        systemImage: String? = nil,
        tone: AppButtonTone = .secondary,
        expands: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.expands = expands
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 16, height: 16)
                }

                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .frame(
                maxWidth: expands ? .infinity : nil,
                minHeight: buttonHeight,
                maxHeight: buttonHeight,
                alignment: .center
            )
        }
        .buttonStyle(AppButtonStyle(tone: tone, isHovered: isHovered))
        .onHover { hovering in
            isHovered = isEnabled && hovering
        }
        .animation(AppControlMetrics.stateAnimation, value: isHovered)
        .accessibilityLabel(title)
    }

    private var role: ButtonRole? {
        tone == .destructive ? .destructive : nil
    }
}

enum AppControlMetrics {
    static let buttonHeight: CGFloat = 32
    static let buttonCornerRadius: CGFloat = 7
    static let iconButtonSize: CGFloat = 28
    static let iconButtonCornerRadius: CGFloat = 7
    static let stateAnimation = Animation.easeOut(duration: 0.12)
}

struct AppPopoverOptionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 12)
                    .opacity(isSelected ? 1 : 0)

                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(AppToolbarButtonStyle())
        .padding(.horizontal, 6)
        .onHover { hovering in
            isHovered = isEnabled && hovering
        }
        .animation(AppControlMetrics.stateAnimation, value: isHovered)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var foregroundStyle: Color {
        guard isEnabled else {
            return .secondary
        }

        return isSelected ? Color(nsColor: .controlAccentColor) : .primary
    }

    private var backgroundColor: Color {
        guard isEnabled else {
            return .clear
        }

        if isHovered {
            return Color(nsColor: .controlAccentColor).opacity(colorScheme == .dark ? 0.22 : 0.14)
        }

        if isSelected {
            return Color(nsColor: .controlAccentColor).opacity(colorScheme == .dark ? 0.14 : 0.08)
        }

        return .clear
    }
}

struct AppInlineButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(foregroundStyle)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(backgroundColor, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(AppToolbarButtonStyle())
        .onHover { hovering in
            isHovered = isEnabled && hovering
        }
        .animation(AppControlMetrics.stateAnimation, value: isHovered)
        .accessibilityLabel(title)
    }

    private var foregroundStyle: Color {
        if isEnabled {
            return Color(nsColor: .controlAccentColor)
        }

        return .secondary
    }

    private var backgroundColor: Color {
        guard isEnabled, isHovered else {
            return .clear
        }

        return Color(nsColor: .controlAccentColor).opacity(0.12)
    }
}

struct AppPopupPickerItem<SelectionValue: Hashable>: Identifiable {
    let title: String
    let value: SelectionValue

    var id: SelectionValue {
        value
    }
}

struct AppPopupPicker<SelectionValue: Hashable, Content: View>: View {
    private enum Presentation {
        case picker
        case lazyMenu
    }

    private let title: String
    private let selection: Binding<SelectionValue>
    private let width: CGFloat?
    private let hidesLabel: Bool
    private let expands: Bool
    private let presentation: Presentation
    private let menuItems: [AppPopupPickerItem<SelectionValue>]
    @ViewBuilder private let content: Content

    init(
        _ title: String,
        selection: Binding<SelectionValue>,
        width: CGFloat? = nil,
        hidesLabel: Bool = false,
        expands: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.selection = selection
        self.width = width
        self.hidesLabel = hidesLabel
        self.expands = expands
        self.presentation = .picker
        self.menuItems = []
        self.content = content()
    }

    var body: some View {
        Group {
            switch presentation {
            case .picker:
                if hidesLabel {
                    picker.labelsHidden()
                } else {
                    picker
                }
            case .lazyMenu:
                lazyMenu
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private var picker: some View {
        Picker(title, selection: selection) {
            content
        }
    }

    private var lazyMenu: some View {
        Menu {
            ForEach(menuItems) { item in
                Button {
                    selection.wrappedValue = item.value
                } label: {
                    if selection.wrappedValue == item.value {
                        Label(item.title, systemImage: "checkmark")
                    } else {
                        Text(item.title)
                    }
                }
            }
        } label: {
            menuLabel
        }
        .menuStyle(.button)
        .frame(maxWidth: expands ? .infinity : nil, alignment: .leading)
    }

    private var menuLabel: some View {
        HStack(spacing: 10) {
            if !hidesLabel {
                Text(title)
                    .foregroundStyle(.secondary)
            }

            Text(selectedMenuTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: expands ? .infinity : nil, alignment: .leading)
    }

    private var selectedMenuTitle: String {
        menuItems.first { $0.value == selection.wrappedValue }?.title ?? String(describing: selection.wrappedValue)
    }
}

extension AppPopupPicker where Content == EmptyView {
    init(
        _ title: String,
        selection: Binding<SelectionValue>,
        width: CGFloat? = nil,
        hidesLabel: Bool = false,
        expands: Bool = false,
        menuItems: [AppPopupPickerItem<SelectionValue>]
    ) {
        self.title = title
        self.selection = selection
        self.width = width
        self.hidesLabel = hidesLabel
        self.expands = expands
        self.presentation = .lazyMenu
        self.menuItems = menuItems
        self.content = EmptyView()
    }
}

private struct AppButtonStyle: ButtonStyle {
    let tone: AppButtonTone
    let isHovered: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    private var accentColor: Color {
        Color(nsColor: .controlAccentColor)
    }

    private var hoveredAccentColor: Color {
        let accent = NSColor.controlAccentColor.usingColorSpace(.deviceRGB) ?? .controlAccentColor
        let target = colorScheme == .dark ? NSColor.white : NSColor.black
        let fraction = colorScheme == .dark ? 0.12 : 0.10
        return Color(nsColor: accent.blended(withFraction: fraction, of: target) ?? accent)
    }

    private var destructiveColor: Color {
        Color(nsColor: .systemRed)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(foregroundColor(isPressed: configuration.isPressed))
            .padding(.horizontal, 14)
            .frame(height: AppControlMetrics.buttonHeight)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: AppControlMetrics.buttonCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppControlMetrics.buttonCornerRadius, style: .continuous)
                    .strokeBorder(borderColor(isPressed: configuration.isPressed), lineWidth: 1)
            }
            .shadow(color: shadowColor(isPressed: configuration.isPressed), radius: 1, x: 0, y: 0.5)
            .opacity(controlOpacity)
            .scaleEffect(scaleEffect(isPressed: configuration.isPressed))
            .animation(AppControlMetrics.stateAnimation, value: configuration.isPressed)
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        if !isEnabled {
            return tone == .primary ? .white.opacity(0.82) : .secondary
        }

        switch tone {
        case .secondary:
            return .primary
        case .primary:
            return .white.opacity(isPressed ? 0.92 : 1)
        case .destructive:
            return destructiveColor
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch tone {
        case .secondary:
            if isPressed {
                return Color(nsColor: .controlAccentColor).opacity(colorScheme == .dark ? 0.22 : 0.14)
            }

            if isHovered {
                return Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07)
            }

            return Color(nsColor: .controlBackgroundColor)
        case .primary:
            if !isEnabled {
                return accentColor.opacity(0.42)
            }

            if isPressed {
                return accentColor.opacity(colorScheme == .light ? 0.78 : 0.82)
            }

            if isHovered {
                return hoveredAccentColor
            }

            return accentColor
        case .destructive:
            if isPressed {
                return destructiveColor.opacity(colorScheme == .dark ? 0.22 : 0.14)
            }

            if isHovered {
                return destructiveColor.opacity(colorScheme == .dark ? 0.16 : 0.09)
            }

            return Color(nsColor: .controlBackgroundColor)
        }
    }

    private func borderColor(isPressed: Bool) -> Color {
        switch tone {
        case .secondary:
            if !isEnabled {
                return Color(nsColor: .separatorColor).opacity(0.24)
            }

            if colorScheme == .dark {
                return Color.white.opacity(isPressed || isHovered ? 0.30 : 0.20)
            }

            return Color.black.opacity(isPressed || isHovered ? 0.18 : 0.12)
        case .primary:
            guard isEnabled else {
                return Color.white.opacity(0.16)
            }

            return Color.white.opacity(isPressed ? 0.16 : isHovered ? 0.36 : 0.24)
        case .destructive:
            guard isEnabled else {
                return Color(nsColor: .separatorColor).opacity(0.24)
            }

            return destructiveColor.opacity(isPressed || isHovered ? 0.44 : 0.28)
        }
    }

    private func shadowColor(isPressed: Bool) -> Color {
        guard isEnabled, !isPressed else {
            return .clear
        }

        if colorScheme == .dark {
            return .clear
        }

        return tone == .primary ? Color.black.opacity(0.12) : .clear
    }

    private var controlOpacity: Double {
        isEnabled ? 1 : 0.62
    }

    private func scaleEffect(isPressed: Bool) -> CGFloat {
        guard isEnabled else {
            return 1
        }

        if isPressed {
            return 0.985
        }

        return 1
    }
}
