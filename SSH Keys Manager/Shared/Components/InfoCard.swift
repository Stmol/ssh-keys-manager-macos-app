import SwiftUI

struct InfoCard<Content: View>: View {
    let spacing: CGFloat
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(
        spacing: CGFloat = 16,
        padding: CGFloat = 18,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            SecondarySurfaceBackground(cornerRadius: 16)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

struct SecondarySurfaceBackground: View {
    let cornerRadius: CGFloat?

    @Environment(\.colorScheme) private var colorScheme

    init(cornerRadius: CGFloat? = nil) {
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Group {
            if let cornerRadius {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
            } else {
                Rectangle()
                    .fill(backgroundColor)
            }
        }
    }

    private var backgroundColor: Color {
        switch colorScheme {
        case .dark:
            return Color(nsColor: .controlBackgroundColor)
        default:
            return Color(
                nsColor: NSColor(
                    calibratedRed: 0.965,
                    green: 0.971,
                    blue: 0.980,
                    alpha: 1
                )
            )
        }
    }
}
