import SwiftUI

struct SSHKeyActionsView: View {
    private let cardSpacing: CGFloat = 14
    private let itemSpacing: CGFloat = 10

    let canCopyPublicKey: Bool
    let canCopyPrivateKey: Bool
    let canEditComment: Bool
    let hasPrivateKey: Bool
    let isPassphraseProtected: Bool
    let onReveal: () -> Void
    let onCopyPublicKey: () -> Void
    let onCopyPrivateKey: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onEditComment: () -> Void
    let onChangePassphrase: () -> Void
    let onDeleteRequest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: cardSpacing) {
            SSHKeyActionCard {
                HStack(spacing: itemSpacing) {
                    SSHKeyActionButton(
                        title: "Copy Public Key",
                        systemImage: "doc.on.doc",
                        tone: .primary,
                        action: onCopyPublicKey
                    )
                    .disabled(!canCopyPublicKey)
                    .help(canCopyPublicKey ? "Copy public key to clipboard" : "This key has no public key file.")

                    SSHKeyActionButton(
                        title: "Copy Private Key",
                        systemImage: "lock.doc",
                        action: onCopyPrivateKey
                    )
                    .disabled(!canCopyPrivateKey)
                    .help(canCopyPrivateKey ? "Copy private key to clipboard" : "This key has no private key file.")
                }
            }

            SSHKeyActionCard {
                HStack(spacing: itemSpacing) {
                    SSHKeyActionButton(
                        title: "Rename Key",
                        systemImage: "pencil",
                        action: onRename
                    )
                    .help("Rename key files and update matching SSH config references.")

                    SSHKeyActionButton(
                        title: "Edit Comment",
                        systemImage: "text.cursor",
                        action: onEditComment
                    )
                    .disabled(!canEditComment)
                    .help(canEditComment ? "Edit public key comment" : "A public key is required to edit the comment.")

                    if hasPrivateKey {
                        SSHKeyActionButton(
                            title: isPassphraseProtected ? "Change Passphrase" : "Add Passphrase",
                            systemImage: "key.horizontal",
                            action: onChangePassphrase
                        )
                        .help(
                            isPassphraseProtected
                                ? "Change the private key passphrase."
                                : "Add a passphrase to the private key."
                        )
                    }
                }
            }

            SSHKeyActionCard {
                HStack(spacing: itemSpacing) {
                    SSHKeyActionButton(
                        title: "Duplicate Key",
                        systemImage: "plus.square.on.square",
                        action: onDuplicate
                    )
                    .help("Duplicate key files with a new name.")

                    SSHKeyActionButton(
                        title: "Reveal in Finder",
                        systemImage: "folder",
                        action: onReveal
                    )

                    SSHKeyActionButton(
                        title: "Delete Key",
                        systemImage: "trash",
                        tone: .destructive,
                        action: onDeleteRequest
                    )
                }
            }
        }
    }
}

private struct SSHKeyActionCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        InfoCard(spacing: 12, padding: 16) {
            content
        }
    }
}

private struct SSHKeyActionButton: View {
    let title: String
    let systemImage: String
    var tone: AppButtonTone = .secondary
    let action: () -> Void

    var body: some View {
        AppButton(
            title,
            systemImage: systemImage,
            tone: tone,
            expands: true,
            action: action
        )
    }
}
