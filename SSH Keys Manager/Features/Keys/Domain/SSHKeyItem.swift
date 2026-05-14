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
