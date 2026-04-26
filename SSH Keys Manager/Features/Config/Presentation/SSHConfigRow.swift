import SwiftUI

struct SSHConfigRow: View {
    let entry: SSHConfigEntry
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
