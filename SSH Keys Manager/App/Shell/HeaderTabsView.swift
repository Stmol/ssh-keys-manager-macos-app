import SwiftUI

struct HeaderTabsView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            HeaderTabPicker(selectedTab: $model.selectedTab)

            HStack {
                Spacer(minLength: 0)

                if model.isReadOnlyModeEnabled {
                    HeaderReadOnlyModeBadge()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct HeaderTabPicker: View {
    private enum Metrics {
        static let containerPadding: CGFloat = 4
        static let tabHeight: CGFloat = 34
        static let tabCornerRadius: CGFloat = AppControlMetrics.buttonCornerRadius
    }

    @Binding var selectedTab: AppTab
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases) { tab in
                HeaderTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    namespace: selectionNamespace,
                    height: Metrics.tabHeight
                ) {
                    selectedTab = tab
                }
            }
        }
        .padding(Metrics.containerPadding)
        .background {
            RoundedRectangle(cornerRadius: Metrics.tabCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.tabCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
    }
}

private struct HeaderTabButton: View {
    private let buttonWidth: CGFloat = 152

    let tab: AppTab
    let isSelected: Bool
    let namespace: Namespace.ID
    let height: CGFloat
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16, height: 16)

                Text(tab.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 16)
            .frame(width: buttonWidth, height: height)
            .contentShape(
                RoundedRectangle(
                    cornerRadius: AppControlMetrics.buttonCornerRadius,
                    style: .continuous
                )
            )
            .background {
                ZStack {
                    if isSelected {
                        HeaderTabSelectionBackground()
                            .matchedGeometryEffect(id: "header-tab-selection", in: namespace)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: AppControlMetrics.buttonCornerRadius, style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.05))
                    }
                }
            }
        }
        .buttonStyle(AppToolbarButtonStyle())
        .keyboardShortcut(tab.keyboardShortcut, modifiers: .command)
        .accessibilityLabel(tab.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .onHover { hovering in
            isHovered = isEnabled && hovering
        }
        .animation(AppControlMetrics.stateAnimation, value: isHovered)
    }

    private var foregroundStyle: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(.white)
        }

        return AnyShapeStyle(.secondary)
    }
}

private struct HeaderTabSelectionBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: AppControlMetrics.buttonCornerRadius, style: .continuous)
            .fill(Color(nsColor: .controlAccentColor))
            .overlay {
                RoundedRectangle(cornerRadius: AppControlMetrics.buttonCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.24), lineWidth: 1)
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.12),
                radius: 2,
                x: 0,
                y: 1
            )
    }
}

private struct HeaderReadOnlyModeBadge: View {
    var body: some View {
        Label("Read-only", systemImage: "checkmark.circle.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.14), in: Capsule())
            .accessibilityLabel("Read-only mode is enabled")
    }
}
