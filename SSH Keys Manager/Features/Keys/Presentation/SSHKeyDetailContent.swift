import SwiftUI

struct SSHKeyDetailContent: View {
    private let contentSpacing: CGFloat = 14

    let key: SSHKeyItem
    let onReveal: () -> Void
    let onCopyPublicKey: () async -> Void
    let onCopyPrivateKey: () async -> Void
    let onCopyFingerprint: () -> Void
    let onRename: (String) async throws -> Void
    let onDuplicate: (String) async throws -> Void
    let onUpdateComment: (String) async throws -> Void
    let onChangePassphrase: (String, String) async throws -> Void
    let onDelete: () async throws -> Void

    @State private var activeSheet: SSHKeyDetailSheet?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                InfoCard {
                    DetailTitle(
                        title: key.name,
                        subtitle: key.comment,
                        systemImage: "key.viewfinder"
                    )
                }

                SSHKeyMetadataCard(
                    key: key,
                    onCopyFingerprint: onCopyFingerprint,
                    onCopyPrivateKey: key.privateKeyPath == nil ? nil : {
                        Task {
                            await onCopyPrivateKey()
                        }
                    },
                    onCopyPublicKey: key.publicKeyPath == nil ? nil : {
                        Task {
                            await onCopyPublicKey()
                        }
                    }
                )

                SSHKeyActionsView(
                    canCopyPublicKey: key.publicKeyPath != nil,
                    canCopyPrivateKey: key.privateKeyPath != nil,
                    canEditComment: key.publicKeyPath != nil,
                    hasPrivateKey: key.privateKeyPath != nil,
                    isPassphraseProtected: key.isPassphraseProtected,
                    onReveal: onReveal,
                    onCopyPublicKey: {
                        Task {
                            await onCopyPublicKey()
                        }
                    },
                    onCopyPrivateKey: {
                        Task {
                            await onCopyPrivateKey()
                        }
                    },
                    onRename: showRenameSheet,
                    onDuplicate: showDuplicateSheet,
                    onEditComment: showEditCommentSheet,
                    onChangePassphrase: showChangePassphraseSheet,
                    onDeleteRequest: confirmDelete
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .sheet(item: $activeSheet, content: sheetContent)
    }

    private func showRenameSheet() {
        activeSheet = .rename
    }

    private func showDuplicateSheet() {
        activeSheet = .duplicate
    }

    private func showEditCommentSheet() {
        activeSheet = .editComment
    }

    private func showChangePassphraseSheet() {
        activeSheet = key.isPassphraseProtected ? .changePassphrase : .addPassphrase
    }

    private func confirmDelete() {
        activeSheet = .delete
    }

    @ViewBuilder
    private func sheetContent(_ sheet: SSHKeyDetailSheet) -> some View {
        switch sheet {
        case .editComment:
            EditSSHKeyCommentView(
                keyName: key.name,
                initialComment: key.comment == "No comment" ? "" : key.comment,
                onSave: onUpdateComment
            )
        case .changePassphrase:
            ChangeSSHKeyPassphraseView(
                keyName: key.name,
                onSave: onChangePassphrase
            )
        case .addPassphrase:
            AddSSHKeyPassphraseView(
                keyName: key.name,
                onSave: { newPassphrase in
                    try await onChangePassphrase("", newPassphrase)
                }
            )
        case .rename:
            SSHKeyNameEditorView(
                mode: .rename,
                key: key,
                onSave: onRename
            )
        case .duplicate:
            SSHKeyNameEditorView(
                mode: .duplicate,
                key: key,
                onSave: onDuplicate
            )
        case .delete:
            DeleteSSHKeyConfirmationView(
                key: key,
                onDelete: onDelete
            )
        }
    }
}

private enum SSHKeyDetailSheet: String, Identifiable {
    case editComment
    case changePassphrase
    case addPassphrase
    case rename
    case duplicate
    case delete

    var id: String {
        rawValue
    }
}
