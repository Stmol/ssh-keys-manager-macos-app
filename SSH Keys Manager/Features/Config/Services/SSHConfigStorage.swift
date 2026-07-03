import Foundation

enum SSHConfigMutation: Hashable, Sendable {
    case add(SSHConfigHostSaveRequest)
    case update(entry: SSHConfigEntry, request: SSHConfigHostSaveRequest)
    case delete(entry: SSHConfigEntry)
}

protocol SSHConfigStorageManaging: Sendable {
    func loadEntries(from directoryPath: String) async throws -> [SSHConfigEntry]
    func apply(
        _ mutation: SSHConfigMutation,
        inDirectory directoryPath: String,
        propertyIndentation: SSHConfigHostPropertyIndentation,
        backupLimit: Int
    ) async throws
    func renameIdentityFileReferences(
        _ replacements: [String: String],
        inDirectory directoryPath: String,
        propertyIndentation: SSHConfigHostPropertyIndentation,
        backupLimit: Int
    ) async throws
    func createEmptyConfig(inDirectory directoryPath: String) async throws
}

extension SSHConfigStorageManaging {
    func renameIdentityFileReferences(
        _ replacements: [String: String],
        inDirectory directoryPath: String,
        propertyIndentation: SSHConfigHostPropertyIndentation,
        backupLimit: Int
    ) async throws {}
}

actor SSHConfigStorage: SSHConfigStorageManaging {
    func loadEntries(from directoryPath: String) async throws -> [SSHConfigEntry] {
        try SSHConfigDocument.load(fromDirectory: directoryPath).entries
    }

    func apply(
        _ mutation: SSHConfigMutation,
        inDirectory directoryPath: String,
        propertyIndentation: SSHConfigHostPropertyIndentation,
        backupLimit: Int
    ) async throws {
        var document = try SSHConfigDocument.loadOrCreateForMutation(
            mutation,
            fromDirectory: directoryPath
        )
        try document.applyHostMutation(
            mutation,
            propertyIndentation: propertyIndentation
        )
        try document.write(
            propertyIndentation: propertyIndentation,
            backupLimit: backupLimit
        )
    }

    func renameIdentityFileReferences(
        _ replacements: [String: String],
        inDirectory directoryPath: String,
        propertyIndentation: SSHConfigHostPropertyIndentation,
        backupLimit: Int
    ) async throws {
        guard !replacements.isEmpty else {
            return
        }

        var document = try SSHConfigDocument.loadIfPresent(fromDirectory: directoryPath)
        guard document != nil else {
            return
        }

        try document?.renameIdentityFileReferences(replacements)
        try document?.write(
            propertyIndentation: propertyIndentation,
            backupLimit: backupLimit
        )
    }

    func createEmptyConfig(inDirectory directoryPath: String) async throws {
        try SSHConfigDocument.createEmptyIfMissing(inDirectory: directoryPath)
    }
}
