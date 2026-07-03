import AppKit
import SwiftUI

struct CopyableDetailValue: View {
    static let rowHeight: CGFloat = 24

    let value: String
    let helpText: String

    private let onCopy: (() -> Void)?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    init(
        value: String,
        helpText: String = "Copy value to clipboard",
        onCopy: (() -> Void)? = nil
    ) {
        self.value = value
        self.helpText = helpText
        self.onCopy = onCopy
    }

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 8) {
                Text(value)
                    .textSelection(.enabled)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(iconColor)
                    .frame(width: 16, height: 16)
                    .opacity(isHovered ? 1 : 0)
            }
            .frame(height: Self.rowHeight)
        }
        .buttonStyle(AppToolbarButtonStyle())
        .help(helpText)
        .accessibilityLabel(helpText)
        .onHover { hovering in
            let isActiveHover = isEnabled && hovering
            isHovered = isActiveHover

            guard isEnabled else { return }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .animation(AppControlMetrics.stateAnimation, value: isHovered)
    }

    private func copy() {
        if let onCopy {
            onCopy()
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var iconColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.48)
            : Color.black.opacity(0.42)
    }

    private var backgroundColor: Color {
        guard isEnabled else {
            return Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.6 : 0.5)
        }

        if isHovered {
            return Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.07)
        }

        return Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.82 : 1)
    }

    private var borderColor: Color {
        let baseOpacity = colorScheme == .dark ? 0.52 : 0.34
        let hoverOpacity = colorScheme == .dark ? 0.72 : 0.58

        return Color(nsColor: .separatorColor).opacity(isHovered ? hoverOpacity : baseOpacity)
    }
}
