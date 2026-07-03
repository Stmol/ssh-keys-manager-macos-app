import SwiftUI

struct SSHKeyRow: View {
    let key: SSHKeyItem
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            KeyRowIcon(isPassphraseProtected: key.isPassphraseProtected, isSelected: isSelected)
            KeyRowText(key: key, isSelected: isSelected)
            Spacer()
            KeyTypeBadge(type: key.type, isSelected: isSelected)
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

private struct KeyRowIcon: View {
    let isPassphraseProtected: Bool
    let isSelected: Bool

    var body: some View {
        Image(systemName: isPassphraseProtected ? "lock.fill" : "key.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSelected ? Color.white : Color.accentColor)
            .frame(width: 24, height: 18, alignment: .center)
    }
}

private struct KeyRowText: View {
    let key: SSHKeyItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key.name)
                .font(.headline)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
            Text(key.comment)
                .font(.caption)
                .foregroundStyle(isSelected ? Color.white.opacity(0.82) : Color.secondary)
        }
    }
}

private struct KeyTypeBadge: View {
    let type: String
    let isSelected: Bool

    var body: some View {
        Text(type)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.white.opacity(0.16) : Color.primary.opacity(0.08), in: Capsule())
    }
}
