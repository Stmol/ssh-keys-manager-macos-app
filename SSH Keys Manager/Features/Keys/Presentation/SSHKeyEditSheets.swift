import Foundation

enum SSHKeyNameEditMode {
    case rename
    case duplicate

    var title: String {
        switch self {
        case .rename:
            return "Rename Key"
        case .duplicate:
            return "Duplicate Key"
        }
    }

    var actionTitle: String {
        switch self {
        case .rename:
            return "Rename"
        case .duplicate:
            return "Duplicate"
        }
    }

    var systemImage: String {
        switch self {
        case .rename:
            return "pencil"
        case .duplicate:
            return "plus.square.on.square"
        }
    }

    var textFieldPrompt: String {
        switch self {
        case .rename:
            return "Key file name"
        case .duplicate:
            return "Duplicate key file name"
        }
    }

    func initialName(for key: SSHKeyItem) -> String {
        switch self {
        case .rename:
            return key.defaultRenameName
        case .duplicate:
            return key.defaultDuplicateName
        }
    }

    func description(for key: SSHKeyItem) -> String {
        switch (self, key.kind) {
        case (.rename, .completePair):
            return "The private key will use this name. The public key will be renamed to the same name with .pub."
        case (.rename, .privateKey):
            return "The private key file will be renamed."
        case (.rename, .publicKey):
            return "The public key file will be renamed. If .pub is omitted, it will be added."
        case (.duplicate, .completePair):
            return "The private and public key files will be copied. The public copy will use the same name with .pub."
        case (.duplicate, .privateKey):
            return "The private key file will be copied with the new name."
        case (.duplicate, .publicKey):
            return "The public key file will be copied. If .pub is omitted, it will be added."
        }
    }
}
