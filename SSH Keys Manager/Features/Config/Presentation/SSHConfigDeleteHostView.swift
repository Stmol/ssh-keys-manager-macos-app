import SwiftUI

struct DeleteSSHConfigHostView: View {
    let entry: SSHConfigEntry
    let onDelete: () async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var deleteController = AsyncActionController()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailTitle(
                title: "Delete Host Entry",
                subtitle: entry.host,
                systemImage: "trash"
            )

            Text("Only the selected Host block will be removed from the SSH config file.")
                .appSheetSupportingText()
                .foregroundStyle(.secondary)

            if let errorMessage = deleteController.errorMessage {
                Text(errorMessage)
                    .appSheetSupportingText()
                    .foregroundStyle(.red)
            }

            HStack {
                if deleteController.isPerforming {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                AppButton("Cancel", action: dismiss.callAsFunction)
                    .disabled(deleteController.isPerforming)

                AppButton("Delete Entry", systemImage: "trash", tone: .destructive, action: delete)
                    .keyboardShortcut(.defaultAction)
                    .disabled(deleteController.isPerforming)
            }
        }
        .padding(24)
        .frame(width: 420)
        .disabled(deleteController.isPerforming)
        .onDisappear {
            deleteController.cancel()
        }
    }

    private func delete() {
        guard !deleteController.isPerforming else {
            return
        }

        deleteController.run(
            operation: {
                try await onDelete()
            },
            onSuccess: dismiss.callAsFunction
        )
    }
}
