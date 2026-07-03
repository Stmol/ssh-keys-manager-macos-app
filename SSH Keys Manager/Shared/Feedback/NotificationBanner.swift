import SwiftUI

enum AppNotificationKind {
    case success
    case warning
    case danger

    var systemImage: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .danger:
            return "xmark.circle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .success:
            return .green
        case .warning:
            return .yellow
        case .danger:
            return .red
        }
    }
}

struct AppNotification: Identifiable, Equatable {
    let id: UUID
    let message: String
    let kind: AppNotificationKind

    init(id: UUID = UUID(), message: String, kind: AppNotificationKind) {
        self.id = id
        self.message = message
        self.kind = kind
    }
}

struct NotificationBannerView: View {
    let notification: AppNotification

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: notification.kind.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(notification.kind.tintColor)
                .frame(width: 18, height: 18)

            Text(notification.message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: 420, alignment: .center)
        .background(backgroundColor, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.14), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
    }

    private var backgroundColor: Color {
        switch notification.kind {
        case .success:
            return colorScheme == .dark
                ? Color(red: 0.08, green: 0.32, blue: 0.16)
                : Color(red: 0.88, green: 0.98, blue: 0.9)
        case .warning:
            return colorScheme == .dark
                ? Color(red: 0.34, green: 0.24, blue: 0.06)
                : Color(red: 1, green: 0.96, blue: 0.83)
        case .danger:
            return colorScheme == .dark
                ? Color(red: 0.38, green: 0.08, blue: 0.08)
                : Color(red: 1, green: 0.9, blue: 0.9)
        }
    }

    private var borderColor: Color {
        switch notification.kind {
        case .success:
            return colorScheme == .dark
                ? Color(red: 0.18, green: 0.58, blue: 0.28)
                : Color(red: 0.52, green: 0.82, blue: 0.58)
        case .warning:
            return colorScheme == .dark
                ? Color(red: 0.86, green: 0.68, blue: 0.18)
                : Color(red: 0.94, green: 0.78, blue: 0.34)
        case .danger:
            return colorScheme == .dark
                ? Color(red: 0.72, green: 0.18, blue: 0.16)
                : Color(red: 0.9, green: 0.54, blue: 0.52)
        }
    }
}

struct NotificationOverlayModifier: ViewModifier {
    private let duration: Duration

    @Binding private var notification: AppNotification?
    @State private var dismissTask: Task<Void, Never>?

    init(notification: Binding<AppNotification?>, duration: Duration = .seconds(2.5)) {
        _notification = notification
        self.duration = duration
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let notification {
                    NotificationBannerView(notification: notification)
                        .id(notification.id)
                        .padding(.top, 12)
                        .padding(.horizontal, 24)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.9), value: notification?.id)
            .onAppear(perform: scheduleAutoDismiss)
            .onChange(of: notification?.id) { _, _ in
                scheduleAutoDismiss()
            }
            .onDisappear {
                dismissTask?.cancel()
                dismissTask = nil
            }
    }

    private func scheduleAutoDismiss() {
        dismissTask?.cancel()

        guard let notification else {
            dismissTask = nil
            return
        }

        let notificationID = notification.id
        dismissTask = Task { @MainActor in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }

            guard self.notification?.id == notificationID else {
                return
            }

            withAnimation(.spring(response: 0.3, dampingFraction: 0.92)) {
                self.notification = nil
            }
        }
    }
}

extension View {
    func notificationOverlay(
        _ notification: Binding<AppNotification?>,
        duration: Duration = .seconds(2.5)
    ) -> some View {
        modifier(NotificationOverlayModifier(notification: notification, duration: duration))
    }
}

#Preview("Success Notification") {
    NotificationPreviewHost(
        notification: AppNotification(
            message: "Copied public key",
            kind: .success
        )
    )
}

#Preview("Danger Notification") {
    NotificationPreviewHost(
        notification: AppNotification(
            message: "Unable to delete key: permission denied",
            kind: .danger
        )
    )
}

#Preview("Warning Notification") {
    NotificationPreviewHost(
        notification: AppNotification(
            message: "Operation is unavailable.",
            kind: .warning
        )
    )
}

#Preview("Long Notification") {
    NotificationPreviewHost(
        notification: AppNotification(
            message: "Duplicated key, but could not refresh SSH keys: the selected directory is unavailable.",
            kind: .danger
        )
    )
}

private struct NotificationPreviewHost: View {
    @State private var notification: AppNotification?

    init(notification: AppNotification) {
        _notification = State(initialValue: notification)
    }

    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .frame(width: 520, height: 220)
            .notificationOverlay($notification)
    }
}
