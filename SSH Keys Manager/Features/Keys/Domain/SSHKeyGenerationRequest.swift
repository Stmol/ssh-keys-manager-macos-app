import Foundation

struct SSHKeyGenerationRequest {
    let fileName: String
    let keyType: SSHKeyGenerationType
    let comment: String
    let passphrase: String?
}

enum SSHKeyGenerationType: String, CaseIterable, Identifiable {
    case ed25519
    case rsa
    case ecdsa

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .ed25519:
            return "ED25519"
        case .rsa:
            return "RSA 4096"
        case .ecdsa:
            return "ECDSA P-256"
        }
    }

    var defaultFileName: String {
        switch self {
        case .ed25519:
            return "id_ed25519"
        case .rsa:
            return "id_rsa"
        case .ecdsa:
            return "id_ecdsa"
        }
    }

    nonisolated var sshKeygenType: String {
        switch self {
        case .ed25519:
            return "ed25519"
        case .rsa:
            return "rsa"
        case .ecdsa:
            return "ecdsa"
        }
    }

    nonisolated var bitCount: Int? {
        switch self {
        case .ed25519:
            return nil
        case .rsa:
            return 4096
        case .ecdsa:
            return 256
        }
    }
}
