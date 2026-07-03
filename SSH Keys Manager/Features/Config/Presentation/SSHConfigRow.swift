import SwiftUI

struct SSHConfigRow: View {
    let entry: SSHConfigEntry
    let status: SSHConfigHostReachabilityStatus?
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            ConfigRowIcon(isSelected: isSelected)
            ConfigRowText(entry: entry, isSelected: isSelected)
                .layoutPriority(1)
            Spacer()
            if let user = entry.user {
                ConfigUserBadge(user: user, isSelected: isSelected)
            }
            if let status {
                ConfigHostReachabilityIndicator(status: status, isSelected: isSelected)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            rowBackground
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            Color(nsColor: .controlAccentColor)
        } else if isHovered {
            Color(nsColor: .controlAccentColor).opacity(0.14)
        } else {
            Color.clear
        }
    }
}

private struct ConfigHostReachabilityIndicator: View {
    let status: SSHConfigHostReachabilityStatus
    let isSelected: Bool

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(indicatorColor)
            .frame(width: 10, height: 10)
            .overlay {
                Circle()
                    .strokeBorder(borderColor, lineWidth: 0.8)
            }
            .opacity(status == .checking ? (isPulsing ? 0.45 : 0.95) : 1)
            .animation(
                status == .checking
                    ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear {
                if status == .checking {
                    isPulsing = true
                }
            }
            .onChange(of: status) { _, newStatus in
                isPulsing = newStatus == .checking
            }
            .help(helpText)
            .accessibilityLabel(helpText)
    }

    private var indicatorColor: Color {
        switch status {
        case .checking:
            return isSelected ? Color.white.opacity(0.72) : Color.gray
        case .reachable:
            return isSelected ? Color.white.opacity(0.95) : Color.green
        case .unreachable:
            return isSelected ? Color.white.opacity(0.95) : Color.red
        case .error:
            return isSelected ? Color.white.opacity(0.95) : Color.orange
        }
    }

    private var borderColor: Color {
        isSelected ? Color.white.opacity(0.28) : Color.primary.opacity(0.12)
    }

    private var helpText: String {
        switch status {
        case .checking:
            return "Checking host reachability"
        case .reachable:
            return "Host is reachable"
        case .unreachable:
            return "Host is unreachable"
        case .error:
            return "Host check failed"
        }
    }
}

private struct ConfigUserBadge: View {
    let user: String
    let isSelected: Bool

    private var maximumTextWidth: CGFloat? {
        user.count > 16 ? 92 : nil
    }

    var body: some View {
        Text(user)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: maximumTextWidth)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.white.opacity(0.16) : Color.primary.opacity(0.08), in: Capsule())
    }
}

private struct ConfigRowIcon: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: "server.rack")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSelected ? Color.white : Color.accentColor)
            .frame(width: 24, height: 18, alignment: .center)
    }
}

private struct ConfigRowText: View {
    let entry: SSHConfigEntry
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.host)
                .font(.headline)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
            Text(entry.hostName)
                .font(.caption)
                .foregroundStyle(isSelected ? Color.white.opacity(0.82) : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
