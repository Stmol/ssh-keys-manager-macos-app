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
    func createEmptyConfig(inDirectory directoryPath: String) async throws
}

actor SSHConfigStorage: SSHConfigStorageManaging {
    func loadEntries(from directoryPath: String) async throws -> [SSHConfigEntry] {
        try SSHConfigParser.loadEntries(from: directoryPath)
    }

    func apply(
        _ mutation: SSHConfigMutation,
        inDirectory directoryPath: String,
        propertyIndentation: SSHConfigHostPropertyIndentation,
        backupLimit: Int
    ) async throws {
        try SSHConfigWriter.apply(
            mutation,
            inDirectory: directoryPath,
            propertyIndentation: propertyIndentation,
            backupLimit: backupLimit
        )
    }

    func createEmptyConfig(inDirectory directoryPath: String) async throws {
        try SSHConfigWriter.createEmptyConfig(inDirectory: directoryPath)
    }
}
