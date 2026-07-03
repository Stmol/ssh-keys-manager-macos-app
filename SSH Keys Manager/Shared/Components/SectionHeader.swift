import AppKit
import SwiftUI

struct SectionHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AppSidebarPanel<TrailingActions: View, Content: View, Footer: View>: View {
    let title: String
    let path: String
    let canRevealPath: Bool
    let revealHelp: String
    let onRevealPath: () -> Void
    @ViewBuilder let trailingActions: TrailingActions
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    init(
        title: String,
        path: String,
        canRevealPath: Bool,
        revealHelp: String,
        onRevealPath: @escaping () -> Void,
        @ViewBuilder trailingActions: () -> TrailingActions,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.path = path
        self.canRevealPath = canRevealPath
        self.revealHelp = revealHelp
        self.onRevealPath = onRevealPath
        self.trailingActions = trailingActions()
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    RevealPathLabel(
                        path: path,
                        canRevealPath: canRevealPath,
                        helpText: revealHelp,
                        onRevealPath: onRevealPath
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
                trailingActions
            }
            .frame(height: 32)

            content

            HStack {
                Spacer()
                footer
                Spacer()
            }
        }
        .frame(width: 320)
        .padding(20)
        .background {
            SecondarySurfaceBackground()
        }
    }
}

private struct RevealPathLabel: View {
    let path: String
    let canRevealPath: Bool
    let helpText: String
    let onRevealPath: () -> Void

    @State private var isHovered = false

    var body: some View {
        Text(path)
            .font(.caption)
            .foregroundStyle(isHovered && canRevealPath ? .primary : .secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 1)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovered && canRevealPath ? 0.08 : 0))
            }
            .onTapGesture {
                guard canRevealPath else {
                    return
                }

                onRevealPath()
            }
            .onHover { hovering in
                isHovered = hovering

                guard canRevealPath else {
                    return
                }

                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .help(helpText)
            .accessibilityLabel(helpText)
    }
}

struct SidebarRefreshButton: View {
    let isLoading: Bool
    let helpText: String
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ToolbarIcon(
                systemName: "arrow.clockwise",
                isHovered: isHovered && !isLoading
            )
        }
        .buttonStyle(AppToolbarButtonStyle())
        .frame(width: 28, height: 28)
        .onHover { isHovered = isEnabled && !isLoading && $0 }
        .opacity(isLoading ? 0.45 : 1)
        .disabled(isLoading)
        .help(helpText)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct SidebarPrimaryActionButton: View {
    let title: String
    let systemImage: String
    let helpText: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        AppButton(
            title,
            systemImage: systemImage,
            tone: .primary,
            action: action
        )
        .disabled(isDisabled)
        .help(helpText)
    }
}

private struct AppSheetSupportingTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    func appSheetSupportingText() -> some View {
        modifier(AppSheetSupportingTextModifier())
    }
}
