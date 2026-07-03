import Observation
import SwiftUI

enum AppFormControlMetrics {
    static let height: CGFloat = 30
    static let cornerRadius: CGFloat = AppControlMetrics.buttonCornerRadius
    static let horizontalPadding: CGFloat = 10
}

struct AppFormMenuItem<SelectionValue: Hashable>: Identifiable {
    let title: String
    let value: SelectionValue

    var id: SelectionValue {
        value
    }
}

struct AppFormMenuPicker<SelectionValue: Hashable>: View {
    @Binding var selection: SelectionValue

    let items: [AppFormMenuItem<SelectionValue>]
    var help: String?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(items) { item in
                Button {
                    selection = item.value
                } label: {
                    if selection == item.value {
                        Label(item.title, systemImage: "checkmark")
                    } else {
                        Text(item.title)
                    }
                }
            }
        } label: {
            AppFormMenuControlLabel(title: selectedTitle, isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = isEnabled && hovering
        }
        .animation(AppControlMetrics.stateAnimation, value: isHovered)
        .help(help ?? "")
    }

    private var selectedTitle: String {
        items.first { $0.value == selection }?.title ?? String(describing: selection)
    }
}

struct AppFormMenuButton<SelectionValue: Hashable>: View {
    let title: String
    let systemImage: String?
    let items: [AppFormMenuItem<SelectionValue>]
    var help: String?
    let onSelect: (SelectionValue) -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(items) { item in
                Button {
                    onSelect(item.value)
                } label: {
                    Text(item.title)
                }
            }
        } label: {
            AppFormMenuControlLabel(
                title: title,
                systemImage: systemImage,
                isHovered: isHovered
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = isEnabled && hovering
        }
        .animation(AppControlMetrics.stateAnimation, value: isHovered)
        .help(help ?? "")
        .accessibilityLabel(help ?? title)
    }
}

struct AppFormIconMenuButton<SelectionValue: Hashable>: View {
    let leadingSystemImage: String
    let items: [AppFormMenuItem<SelectionValue>]
    var help: String?
    let onSelect: (SelectionValue) -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(items) { item in
                Button {
                    onSelect(item.value)
                } label: {
                    Text(item.title)
                }
            }
        } label: {
            AppFormIconMenuControlLabel(
                leadingSystemImage: leadingSystemImage,
                isHovered: isHovered
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = isEnabled && hovering
        }
        .animation(AppControlMetrics.stateAnimation, value: isHovered)
        .help(help ?? "")
        .accessibilityLabel(help ?? leadingSystemImage)
    }
}

struct AppFormIconButton: View {
    let systemImage: String
    var help: String?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            AppFormIconControlLabel(
                systemImage: systemImage,
                isHovered: isHovered
            )
        }
        .buttonStyle(AppToolbarButtonStyle())
        .onHover { hovering in
            isHovered = isEnabled && hovering
        }
        .animation(AppControlMetrics.stateAnimation, value: isHovered)
        .help(help ?? "")
        .accessibilityLabel(help ?? systemImage)
    }
}

@Observable
@MainActor
final class AsyncActionController {
    var errorMessage: String?
    var isPerforming = false

    @ObservationIgnored private var task: Task<Void, Never>?

    func run(
        operation: @escaping @MainActor () async throws -> Void,
        onSuccess: @escaping @MainActor () -> Void = {},
        onFailure: @escaping @MainActor (Error) -> Void = { _ in }
    ) {
        isPerforming = true
        errorMessage = nil
        task?.cancel()
        task = Task { @MainActor in
            do {
                try await operation()
                guard !Task.isCancelled else {
                    return
                }

                onSuccess()
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
                isPerforming = false
                onFailure(error)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

struct AppFormPlainIconButton: View {
    let systemImage: String
    var help: String?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: 14, height: 14)
                .frame(width: 18, height: 18)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(AppToolbarButtonStyle())
        .onHover { hovering in
            guard isEnabled else {
                isHovered = false
                return
            }

            isHovered = hovering
        }
        .animation(AppControlMetrics.stateAnimation, value: isHovered)
        .help(help ?? "")
        .accessibilityLabel(help ?? systemImage)
    }

    private var foregroundColor: Color {
        if isEnabled {
            return .primary
        }

        return colorScheme == .light ? Color.black.opacity(0.28) : Color.white.opacity(0.28)
    }

    private var backgroundColor: Color {
        guard isEnabled else {
            return .clear
        }

        guard isHovered else {
            return .clear
        }

        return Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07)
    }
}

private struct AppFormMenuControlLabel: View {
    let title: String
    var systemImage: String?
    let isHovered: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(foregroundColor)
                    .frame(width: 16, height: 16)
            }

            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(chevronColor)
                .frame(width: 16, height: 16)
        }
        .padding(.horizontal, AppFormControlMetrics.horizontalPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: AppFormControlMetrics.height,
            maxHeight: AppFormControlMetrics.height,
            alignment: .leading
        )
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: AppFormControlMetrics.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppFormControlMetrics.cornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: AppFormControlMetrics.cornerRadius, style: .continuous))
    }

    private var foregroundColor: Color {
        isEnabled ? .primary : .secondary
    }

    private var chevronColor: Color {
        isEnabled ? .secondary : Color.secondary.opacity(0.65)
    }

    private var backgroundColor: Color {
        if !isEnabled {
            return Color(nsColor: .controlBackgroundColor).opacity(0.52)
        }

        if isHovered {
            return Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07)
        }

        return Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        Color(nsColor: .separatorColor).opacity(isEnabled && isHovered ? 0.58 : 0.34)
    }
}

private struct AppFormIconControlLabel: View {
    let systemImage: String
    let isHovered: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .frame(width: 16, height: 16)
            .padding(.horizontal, AppFormControlMetrics.horizontalPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: AppFormControlMetrics.height,
                maxHeight: AppFormControlMetrics.height,
                alignment: .center
            )
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: AppFormControlMetrics.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppFormControlMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppFormControlMetrics.cornerRadius, style: .continuous))
    }

    private var backgroundColor: Color {
        if !isEnabled {
            return Color(nsColor: .controlBackgroundColor).opacity(0.52)
        }

        if isHovered {
            return Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07)
        }

        return Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        Color(nsColor: .separatorColor).opacity(isEnabled && isHovered ? 0.58 : 0.34)
    }
}

private struct AppFormIconMenuControlLabel: View {
    let leadingSystemImage: String
    let isHovered: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: leadingSystemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                .frame(width: 16, height: 16)

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.secondary : Color.secondary.opacity(0.65))
                .frame(width: 16, height: 16)
        }
        .padding(.horizontal, AppFormControlMetrics.horizontalPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: AppFormControlMetrics.height,
            maxHeight: AppFormControlMetrics.height,
            alignment: .leading
        )
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: AppFormControlMetrics.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppFormControlMetrics.cornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: AppFormControlMetrics.cornerRadius, style: .continuous))
    }

    private var backgroundColor: Color {
        if !isEnabled {
            return Color(nsColor: .controlBackgroundColor).opacity(0.52)
        }

        if isHovered {
            return Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07)
        }

        return Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        Color(nsColor: .separatorColor).opacity(isEnabled && isHovered ? 0.58 : 0.34)
    }
}

struct AppFormTextField: View {
    enum InputMode {
        case text
        case secure
    }

    private let placeholder: String
    private let inputMode: InputMode
    @Binding private var text: String

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool

    init(_ placeholder: String, text: Binding<String>, inputMode: InputMode = .text) {
        self.placeholder = placeholder
        self.inputMode = inputMode
        self._text = text
    }

    var body: some View {
        inputField
            .textFieldStyle(.plain)
            .focused($isFocused)
            .font(.system(size: 13, weight: .regular))
            .padding(.horizontal, AppFormControlMetrics.horizontalPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: AppFormControlMetrics.height,
                maxHeight: AppFormControlMetrics.height,
                alignment: .leading
            )
            .background(fieldBackground, in: RoundedRectangle(cornerRadius: AppFormControlMetrics.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppFormControlMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(fieldBorder, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.7)
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }

    @ViewBuilder private var inputField: some View {
        switch inputMode {
        case .text:
            TextField(placeholder, text: $text)
        case .secure:
            SecureField(placeholder, text: $text)
        }
    }

    private var fieldBackground: Color {
        colorScheme == .light ? .white : Color(nsColor: .textBackgroundColor)
    }

    private var fieldBorder: Color {
        if isFocused {
            return Color(nsColor: .controlAccentColor)
        }

        return colorScheme == .light ? Color.black.opacity(0.12) : Color.white.opacity(0.14)
    }
}
