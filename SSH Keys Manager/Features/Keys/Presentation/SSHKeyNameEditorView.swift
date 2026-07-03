import SwiftUI

struct SSHKeyNameEditorView: View {
    let mode: SSHKeyNameEditMode
    let key: SSHKeyItem
    let onSave: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var submitController = AsyncActionController()

    init(mode: SSHKeyNameEditMode, key: SSHKeyItem, onSave: @escaping (String) async throws -> Void) {
        self.mode = mode
        self.key = key
        self.onSave = onSave
        _name = State(initialValue: mode.initialName(for: key))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailTitle(
                title: mode.title,
                subtitle: key.name,
                systemImage: mode.systemImage
            )

            AppFormTextField(mode.textFieldPrompt, text: $name)

            Text(mode.description(for: key))
                .appSheetSupportingText()
                .foregroundStyle(.secondary)

            if let errorMessage = submitController.errorMessage {
                Text(errorMessage)
                    .appSheetSupportingText()
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                AppButton("Cancel", action: dismiss.callAsFunction)
                    .disabled(submitController.isPerforming)

                AppButton(mode.actionTitle, tone: .primary, action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 420)
        .disabled(submitController.isPerforming)
        .onDisappear {
            submitController.cancel()
        }
    }

    private var canSave: Bool {
        key.canUseReplacementName(name) && !submitController.isPerforming
    }

    private func save() {
        guard canSave else {
            return
        }

        submitController.run(
            operation: {
                try await onSave(name)
            },
            onSuccess: dismiss.callAsFunction
        )
    }
}

struct EditSSHKeyCommentView: View {
    let keyName: String
    let initialComment: String
    let onSave: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var comment: String
    @State private var submitController = AsyncActionController()

    init(keyName: String, initialComment: String, onSave: @escaping (String) async throws -> Void) {
        self.keyName = keyName
        self.initialComment = initialComment
        self.onSave = onSave
        _comment = State(initialValue: initialComment)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailTitle(
                title: "Edit Comment",
                subtitle: keyName,
                systemImage: "text.cursor"
            )

            AppFormTextField("Comment", text: $comment)

            if let errorMessage = submitController.errorMessage {
                Text(errorMessage)
                    .appSheetSupportingText()
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                AppButton("Cancel", action: dismiss.callAsFunction)
                    .disabled(submitController.isPerforming)

                AppButton("Save", tone: .primary, action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(submitController.isPerforming)
            }
        }
        .padding(24)
        .frame(width: 420)
        .disabled(submitController.isPerforming)
        .onDisappear {
            submitController.cancel()
        }
    }

    private func save() {
        guard !submitController.isPerforming else {
            return
        }

        submitController.run(
            operation: {
                try await onSave(comment)
            },
            onSuccess: dismiss.callAsFunction
        )
    }
}
