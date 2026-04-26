import SwiftUI

struct SSHKeyDetailView: View {
    let key: SSHKeyItem?
    let emptyState: AppEmptyStateContent
    let onReveal: () -> Void
    let onCopyPublicKey: () async -> Void
    let onCopyPrivateKey: () async -> Void
    let onCopyFingerprint: () -> Void
    let onRename: (String) async throws -> Void
    let onDuplicate: (String) async throws -> Void
    let onUpdateComment: (String) async throws -> Void
    let onChangePassphrase: (String, String) async throws -> Void
    let onDelete: () async throws -> Void

    var body: some View {
        ZStack {
            if let key {
                SSHKeyDetailContent(
                    key: key,
                    onReveal: onReveal,
                    onCopyPublicKey: onCopyPublicKey,
                    onCopyPrivateKey: onCopyPrivateKey,
                    onCopyFingerprint: onCopyFingerprint,
                    onRename: onRename,
                    onDuplicate: onDuplicate,
                    onUpdateComment: onUpdateComment,
                    onChangePassphrase: onChangePassphrase,
                    onDelete: onDelete
                )
            } else {
                AppEmptyStateView(content: emptyState)
            }
        }
    }
}
