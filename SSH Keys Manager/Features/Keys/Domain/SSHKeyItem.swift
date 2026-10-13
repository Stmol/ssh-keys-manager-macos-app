import Foundation

struct SSHKeyItem: Identifiable, Hashable {
    let id: String
    let name: String
    let publicKeyPath: String?
    let privateKeyPath: String?
    let filePath: String
    let kind: SSHKeyKind
    let type: String
    let fingerprint: String
    let comment: String
    let createdAt: Date
    let isPassphraseProtected: Bool
    /// Path of the containing folder relative to the SSH keys directory,
    /// or `nil` when the key lives directly in the SSH keys directory.
    let relativeDirectory: String?

    init(
        id: String,
        name: String,
        publicKeyPath: String?,
        privateKeyPath: String?,
        filePath: String,
        kind: SSHKeyKind,
        type: String,
        fingerprint: String,
        comment: String,
        createdAt: Date,
        isPassphraseProtected: Bool,
        relativeDirectory: String? = nil
    ) {
        self.id = id
        self.name = name
        self.publicKeyPath = publicKeyPath
        self.privateKeyPath = privateKeyPath
        self.filePath = filePath
        self.kind = kind
        self.type = type
        self.fingerprint = fingerprint
        self.comment = comment
        self.createdAt = createdAt
        self.isPassphraseProtected = isPassphraseProtected
        self.relativeDirectory = relativeDirectory
    }

    /// File name qualified with its subfolder, e.g. `personal/id_ed25519`, so
    /// keys that share a file name in different folders remain distinguishable.
    /// Falls back to the plain file name for keys in the SSH keys directory root.
    var displayName: String {
        guard let relativeDirectory, !relativeDirectory.isEmpty else {
            return name
        }

        return "\(relativeDirectory)/\(name)"
    }

    static func fuzzyMatch(query: String, in text: String) -> Bool {
        guard !query.isEmpty else { return true }
        let queryChars = query.lowercased()
        let textChars = text.lowercased()
        var qi = queryChars.startIndex
        var ti = textChars.startIndex
        while qi < queryChars.endIndex, ti < textChars.endIndex {
            if queryChars[qi] == textChars[ti] {
                qi = textChars.index(after: qi)
            }
            ti = textChars.index(after: ti)
        }
        return qi == queryChars.endIndex
    }
}

enum SSHKeyKind: String, Hashable {
    case completePair
    case privateKey
    case publicKey

    var title: String {
        switch self {
        case .completePair:
            return "Complete Pair"
        case .privateKey:
            return "Private Key"
        case .publicKey:
            return "Public Key"
        }
    }
}
