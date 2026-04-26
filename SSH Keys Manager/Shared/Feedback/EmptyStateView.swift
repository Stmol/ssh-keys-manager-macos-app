import SwiftUI

struct AppEmptyStateAction {
    let title: String
    let systemImage: String?
    let action: () -> Void
}

struct AppEmptyStateContent {
    let title: String
    let message: String
    let systemImage: String
    let primaryAction: AppEmptyStateAction?

    init(
        title: String,
        message: String,
        systemImage: String,
        primaryAction: AppEmptyStateAction? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.primaryAction = primaryAction
    }
}

struct AppEmptyStateView: View {
    let content: AppEmptyStateContent

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: content.systemImage)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(content.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    Text(content.message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if let primaryAction = content.primaryAction {
                        AppButton(
                            primaryAction.title,
                            systemImage: primaryAction.systemImage,
                            tone: .primary,
                            action: primaryAction.action
                        )
                        .padding(.top, 12)
                    }
                }
                .frame(maxWidth: 360)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AppSidebarEmptyStateView: View {
    let title: String
    let hint: String

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    Text(hint)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 240)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
