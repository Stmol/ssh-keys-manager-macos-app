import SwiftUI

struct ChangeSSHKeyPassphraseView: View {
    let keyName: String
    let onSave: (String, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var oldPassphrase = ""
    @State private var newPassphrase = ""
    @State private var confirmNewPassphrase = ""
    @State private var submitController = AsyncActionController()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailTitle(
                title: "Change Passphrase",
                subtitle: keyName,
                systemImage: "key.horizontal"
            )

            VStack(alignment: .leading, spacing: 12) {
                AppFormTextField("Current passphrase", text: $oldPassphrase, inputMode: .secure)
                AppFormTextField("New passphrase", text: $newPassphrase, inputMode: .secure)
                AppFormTextField("Confirm new passphrase", text: $confirmNewPassphrase, inputMode: .secure)

                if !newPassphrasesMatch {
                    Text("Passphrases do not match.")
                        .appSheetSupportingText()
                        .foregroundStyle(.red)
                }

                if let errorMessage = submitController.errorMessage {
                    Text(errorMessage)
                        .appSheetSupportingText()
                        .foregroundStyle(.red)
                }
            }

            HStack {
                if submitController.isPerforming {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                AppButton("Cancel", action: dismiss.callAsFunction)
                    .disabled(submitController.isPerforming)

                AppButton("Change", tone: .primary, action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 460)
        .disabled(submitController.isPerforming)
        .onDisappear {
            submitController.cancel()
        }
    }

    private var newPassphrasesMatch: Bool {
        newPassphrase == confirmNewPassphrase
    }

    private var canSave: Bool {
        !oldPassphrase.isEmpty
            && !newPassphrase.isEmpty
            && newPassphrasesMatch
            && !submitController.isPerforming
    }

    private func save() {
        guard canSave else {
            return
        }

        submitController.run(
            operation: {
                try await onSave(oldPassphrase, newPassphrase)
            },
            onSuccess: dismiss.callAsFunction
        )
    }
}

struct AddSSHKeyPassphraseView: View {
    let keyName: String
    let onSave: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var confirmPassphrase = ""
    @State private var submitController = AsyncActionController()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailTitle(
                title: "Add Passphrase",
                subtitle: keyName,
                systemImage: "lock"
            )

            VStack(alignment: .leading, spacing: 12) {
                AppFormTextField("Passphrase", text: $passphrase, inputMode: .secure)
                AppFormTextField("Confirm passphrase", text: $confirmPassphrase, inputMode: .secure)

                if !passphrasesMatch {
                    Text("Passphrases do not match.")
                        .appSheetSupportingText()
                        .foregroundStyle(.red)
                }

                if let errorMessage = submitController.errorMessage {
                    Text(errorMessage)
                        .appSheetSupportingText()
                        .foregroundStyle(.red)
                }
            }

            HStack {
                if submitController.isPerforming {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                AppButton("Cancel", action: dismiss.callAsFunction)
                    .disabled(submitController.isPerforming)

                AppButton("Add", tone: .primary, action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 460)
        .disabled(submitController.isPerforming)
        .onDisappear {
            submitController.cancel()
        }
    }

    private var passphrasesMatch: Bool {
        passphrase == confirmPassphrase
    }

    private var canSave: Bool {
        !passphrase.isEmpty
            && passphrasesMatch
            && !submitController.isPerforming
    }

    private func save() {
        guard canSave else {
            return
        }

        submitController.run(
            operation: {
                try await onSave(passphrase)
            },
            onSuccess: dismiss.callAsFunction
        )
    }
}
