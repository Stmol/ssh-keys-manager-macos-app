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
