import Foundation

protocol SSHKeyStorageManaging: Sendable {
    func updateSSHKeygenPath(_ path: String) async
    func loadKeys(from directoryPath: String) async throws -> SSHKeyInventory
    func publicKeyContents(for key: SSHKeyItem) async throws -> String
    func privateKeyContents(for key: SSHKeyItem) async throws -> String
    func delete(_ key: SSHKeyItem) async throws
    func updateComment(for key: SSHKeyItem, comment: String) async throws
    func changePassphrase(for key: SSHKeyItem, oldPassphrase: String, newPassphrase: String) async throws
    func rename(_ key: SSHKeyItem, to newName: String) async throws -> SSHKeyItem.ID
    func duplicate(_ key: SSHKeyItem, to newName: String) async throws -> SSHKeyItem.ID
    func generateKey(_ request: SSHKeyGenerationRequest, in directoryPath: String) async throws -> SSHKeyItem.ID
    func availableKeyName(for baseName: String, in directoryPath: String) async throws -> String
    func existingKeyFileNames(in directoryPath: String) async throws -> Set<String>
}

extension SSHKeyStorageManaging {
    func updateSSHKeygenPath(_ path: String) async {}
}

actor SSHKeyStorage: SSHKeyStorageManaging {
    private var keyStore: SSHKeyStore

    init(keyStore: SSHKeyStore) {
        self.keyStore = keyStore
    }

    func updateSSHKeygenPath(_ path: String) async {
        keyStore = keyStore.updatingSSHKeygenURL(URL(fileURLWithPath: path))
    }

    func loadKeys(from directoryPath: String) async throws -> SSHKeyInventory {
        try keyStore.loadKeys(from: directoryPath)
    }

    func publicKeyContents(for key: SSHKeyItem) async throws -> String {
        guard let publicKeyPath = key.publicKeyPath else {
            throw SSHKeyFileActionError.missingPublicKey
        }

        return try String(contentsOf: URL(fileURLWithPath: publicKeyPath), encoding: .utf8)
    }

    func privateKeyContents(for key: SSHKeyItem) async throws -> String {
        guard let privateKeyPath = key.privateKeyPath else {
            throw SSHKeyFileActionError.missingPrivateKey
        }

        return try String(contentsOf: URL(fileURLWithPath: privateKeyPath), encoding: .utf8)
    }

    func delete(_ key: SSHKeyItem) async throws {
        try keyStore.delete(key)
    }

    func updateComment(for key: SSHKeyItem, comment: String) async throws {
        try keyStore.updateComment(for: key, comment: comment)
    }

    func changePassphrase(
        for key: SSHKeyItem,
        oldPassphrase: String,
        newPassphrase: String
    ) async throws {
        try keyStore.changePassphrase(
            for: key,
            oldPassphrase: oldPassphrase,
            newPassphrase: newPassphrase
        )
    }

    func rename(_ key: SSHKeyItem, to newName: String) async throws -> SSHKeyItem.ID {
        try keyStore.rename(key, to: newName)
    }

    func duplicate(_ key: SSHKeyItem, to newName: String) async throws -> SSHKeyItem.ID {
        try keyStore.duplicate(key, to: newName)
    }

    func generateKey(_ request: SSHKeyGenerationRequest, in directoryPath: String) async throws -> SSHKeyItem.ID {
        try keyStore.generateKey(request, in: directoryPath)
    }

    func availableKeyName(for baseName: String, in directoryPath: String) async throws -> String {
        try keyStore.availableKeyName(for: baseName, in: directoryPath)
    }

    func existingKeyFileNames(in directoryPath: String) async throws -> Set<String> {
        try keyStore.existingKeyFileNames(in: directoryPath)
    }
}
