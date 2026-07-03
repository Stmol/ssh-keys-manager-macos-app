import SwiftUI

struct DeleteSSHKeyConfirmationView: View {
    let key: SSHKeyItem
    let onDelete: () async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var deleteController = AsyncActionController()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailTitle(
                title: deleteTitle,
                subtitle: key.name,
                systemImage: "trash"
            )

            Text(deleteDescription)
                .appSheetSupportingText()
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(pathsToDelete, id: \.self) { path in
                    Text(path)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
            }

            if let errorMessage = deleteController.errorMessage {
                Text(errorMessage)
                    .appSheetSupportingText()
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                AppButton("Cancel", action: dismiss.callAsFunction)
                    .disabled(deleteController.isPerforming)

                AppButton(deleteActionTitle, tone: .destructive, action: delete)
                    .keyboardShortcut(.defaultAction)
                    .disabled(deleteController.isPerforming)
            }
        }
        .padding(24)
        .frame(width: 460)
        .disabled(deleteController.isPerforming)
        .onDisappear {
            deleteController.cancel()
        }
    }

    private var deleteTitle: String {
        switch key.kind {
        case .completePair:
            return "Delete Keys"
        case .privateKey, .publicKey:
            return "Delete Key"
        }
    }

    private var deleteActionTitle: String {
        switch key.kind {
        case .completePair:
            return "Delete Both"
        case .privateKey, .publicKey:
            return "Delete"
        }
    }

    private var deleteDescription: String {
        switch key.kind {
        case .completePair:
            return "This action permanently removes both key files from disk."
        case .privateKey:
            return "This action permanently removes the private key file from disk."
        case .publicKey:
            return "This action permanently removes the public key file from disk."
        }
    }

    private var pathsToDelete: [String] {
        switch key.kind {
        case .completePair:
            return [key.privateKeyPath, key.publicKeyPath].compactMap { $0 }
        case .privateKey, .publicKey:
            return [key.filePath]
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

struct GenerateSSHKeyView: View {
    let sshDirectoryPath: String
    let availableKeyName: (String) async -> String?
    let onGenerate: (SSHKeyGenerationRequest) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var keyType: SSHKeyGenerationType = .ed25519
    @State private var fileName = SSHKeyGenerationType.ed25519.defaultFileName
    @State private var hasEditedFileName = false
    @State private var comment = ""
    @State private var passphrase = ""
    @State private var confirmPassphrase = ""
    @State private var suggestedFileName: String?
    @State private var isCheckingFileNames = true
    @State private var submitController = AsyncActionController()
    @State private var suggestionTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailTitle(
                title: "Generate New Key",
                subtitle: sshDirectoryPath,
                systemImage: "plus.circle.fill"
            )

            VStack(alignment: .leading, spacing: 12) {
                AppPopupPicker("Key type", selection: $keyType) {
                    ForEach(SSHKeyGenerationType.allCases) { type in
                        Text(type.title)
                            .tag(type)
                    }
                }

                AppFormTextField("Key file name", text: fileNameBinding)

                if let suggestedFileName, !submitController.isPerforming {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        Text("A key with this name already exists.")
                            .appSheetSupportingText()
                            .foregroundStyle(.secondary)

                        AppInlineButton(title: "Use \(suggestedFileName)") {
                            useSuggestedFileName()
                        }
                    }
                }

                AppFormTextField("Comment", text: $comment)
                AppFormTextField("Passphrase", text: $passphrase, inputMode: .secure)
                AppFormTextField("Confirm passphrase", text: $confirmPassphrase, inputMode: .secure)

                if !isFileNameValid {
                    Text("Use a file name without path separators or .pub extension.")
                        .appSheetSupportingText()
                        .foregroundStyle(.red)
                } else if !passphrasesMatch {
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

                AppButton("Generate", tone: .primary, action: generate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canGenerate)
            }
        }
        .padding(24)
        .frame(width: 460)
        .disabled(submitController.isPerforming)
        .task(id: sshDirectoryPath) {
            queueSuggestedFileNameRefresh()
        }
        .onChange(of: keyType) { _, newType in
            if !hasEditedFileName {
                fileName = newType.defaultFileName
            }

            queueSuggestedFileNameRefresh()
        }
        .onDisappear {
            suggestionTask?.cancel()
            suggestionTask = nil
            submitController.cancel()
        }
    }

    private var fileNameBinding: Binding<String> {
        Binding(
            get: {
                fileName
            },
            set: { newValue in
                fileName = newValue
                hasEditedFileName = true
                queueSuggestedFileNameRefresh()
            }
        )
    }

    private var trimmedFileName: String {
        fileName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFileNameValid: Bool {
        !trimmedFileName.isEmpty
            && trimmedFileName.rangeOfCharacter(from: CharacterSet(charactersIn: "/:")) == nil
            && trimmedFileName != "."
            && trimmedFileName != ".."
            && !trimmedFileName.hasSuffix(".pub")
    }

    private var passphrasesMatch: Bool {
        passphrase == confirmPassphrase
    }

    private var canGenerate: Bool {
        isFileNameValid
            && passphrasesMatch
            && suggestedFileName == nil
            && !isCheckingFileNames
            && !submitController.isPerforming
    }

    private func queueSuggestedFileNameRefresh() {
        suggestionTask?.cancel()
        suggestionTask = Task {
            await refreshSuggestedFileName()
        }
    }

    private func refreshSuggestedFileName() async {
        guard !submitController.isPerforming else {
            suggestedFileName = nil
            isCheckingFileNames = false
            return
        }

        isCheckingFileNames = true
        defer {
            if !Task.isCancelled {
                isCheckingFileNames = false
            }
        }

        guard isFileNameValid else {
            suggestedFileName = nil
            return
        }

        let candidateName = trimmedFileName
        let availableName = await availableKeyName(candidateName)
        guard !Task.isCancelled else {
            return
        }

        guard candidateName == trimmedFileName else {
            return
        }

        suggestedFileName = availableName == candidateName ? nil : availableName
    }

    private func useSuggestedFileName() {
        guard let suggestedFileName else {
            return
        }

        fileName = suggestedFileName
        hasEditedFileName = true
        queueSuggestedFileNameRefresh()
    }

    private func generate() {
        guard canGenerate else {
            return
        }

        suggestionTask?.cancel()
        suggestionTask = nil
        suggestedFileName = nil

        let request = SSHKeyGenerationRequest(
            fileName: trimmedFileName,
            keyType: keyType,
            comment: comment,
            passphrase: passphrase.isEmpty ? nil : passphrase
        )

        submitController.run(
            operation: {
                try await onGenerate(request)
            },
            onSuccess: dismiss.callAsFunction,
            onFailure: { _ in
                queueSuggestedFileNameRefresh()
            }
        )
    }
}
