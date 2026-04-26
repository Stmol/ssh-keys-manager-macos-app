import SwiftUI

struct SSHKeyMetadataCard: View {
    private let labelWidth: CGFloat = 110

    let key: SSHKeyItem
    let onCopyFingerprint: () -> Void
    let onCopyPrivateKey: (() -> Void)?
    let onCopyPublicKey: (() -> Void)?

    var body: some View {
        InfoCard(spacing: 10, padding: 16) {
            DetailField(
                title: "Kind",
                value: key.kind.title,
                isMonospaced: true,
                labelWidth: labelWidth
            )
            DetailField(
                title: "Type",
                value: key.type,
                isMonospaced: true,
                labelWidth: labelWidth
            )
            DetailField(
                title: "Passphrase",
                value: key.isPassphraseProtected ? "yes" : "no",
                isMonospaced: true,
                labelWidth: labelWidth
            )
            DetailField(
                title: "Fingerprint",
                value: key.fingerprint,
                isMonospaced: true,
                truncatesValue: true,
                labelWidth: labelWidth,
                copyHelpText: "Copy fingerprint to clipboard",
                onCopy: onCopyFingerprint
            )
            DetailField(
                title: "Private Key",
                value: key.privateKeyPath ?? "Unavailable",
                isMonospaced: true,
                truncatesValue: true,
                labelWidth: labelWidth,
                copyHelpText: key.privateKeyPath == nil ? nil : "Copy private key to clipboard",
                onCopy: onCopyPrivateKey
            )
            DetailField(
                title: "Public Key",
                value: key.publicKeyPath ?? "Unavailable",
                isMonospaced: true,
                truncatesValue: true,
                labelWidth: labelWidth,
                copyHelpText: key.publicKeyPath == nil ? nil : "Copy public key to clipboard",
                onCopy: onCopyPublicKey
            )
            DetailField(
                title: "Created",
                value: key.createdAt.formatted(date: .abbreviated, time: .omitted),
                isMonospaced: true,
                labelWidth: labelWidth
            )
        }
    }
}
