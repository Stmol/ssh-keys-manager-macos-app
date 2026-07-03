import Foundation

protocol SSHWorkspaceValidating {
    func validate(directoryPath: String) throws -> String
}

enum SSHWorkspacePath {
    nonisolated static var defaultDirectoryPath: String {
        normalizeDirectoryPath("~/.ssh")
    }

    nonisolated static func normalizeDirectoryPath(_ path: String) -> String {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let inputPath = trimmedPath.isEmpty ? "~/.ssh" : trimmedPath
        let expandedPath = (inputPath as NSString).expandingTildeInPath
        let normalizedPath = URL(fileURLWithPath: expandedPath, isDirectory: true)
            .standardizedFileURL
            .path

        guard normalizedPath.count > 1, normalizedPath.hasSuffix("/") else {
            return normalizedPath
        }

        return String(normalizedPath.dropLast())
    }

    nonisolated static func displayPath(for directoryPath: String) -> String {
        let normalizedPath = normalizeDirectoryPath(directoryPath)
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path

        if normalizedPath == homePath {
            return "~"
        }

        if normalizedPath.hasPrefix(homePath + "/") {
            return "~" + normalizedPath.dropFirst(homePath.count)
        }

        return normalizedPath
    }

    nonisolated static func configDisplayPath(for directoryPath: String) -> String {
        let displayedDirectoryPath = displayPath(for: directoryPath)
        return displayedDirectoryPath == "/" ? "/config" : "\(displayedDirectoryPath)/config"
    }

    nonisolated static func configFilePath(for directoryPath: String) -> String {
        let normalizedDirectoryPath = normalizeDirectoryPath(directoryPath)
        return normalizedDirectoryPath == "/" ? "/config" : "\(normalizedDirectoryPath)/config"
    }
}

enum SSHWorkspaceDirectoryError: LocalizedError, Equatable {
    case directoryMissing(String)
    case notDirectory(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .directoryMissing(let path):
            return "The SSH workspace directory does not exist: \(path)"
        case .notDirectory(let path):
            return "The SSH workspace path is not a directory: \(path)"
        case .unreadable(let path):
            return "The SSH workspace directory is not readable: \(path)"
        }
    }
}

struct SSHWorkspaceValidator: SSHWorkspaceValidating {
    nonisolated(unsafe) private let fileManager: FileManager

    nonisolated init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    nonisolated func validate(directoryPath: String) throws -> String {
        let normalizedPath = SSHWorkspacePath.normalizeDirectoryPath(directoryPath)
        let displayedPath = SSHWorkspacePath.displayPath(for: normalizedPath)
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: normalizedPath, isDirectory: &isDirectory) else {
            throw SSHWorkspaceDirectoryError.directoryMissing(displayedPath)
        }

        guard isDirectory.boolValue else {
            throw SSHWorkspaceDirectoryError.notDirectory(displayedPath)
        }

        guard fileManager.isReadableFile(atPath: normalizedPath) else {
            throw SSHWorkspaceDirectoryError.unreadable(displayedPath)
        }

        do {
            _ = try fileManager.contentsOfDirectory(atPath: normalizedPath)
        } catch {
            throw SSHWorkspaceDirectoryError.unreadable(displayedPath)
        }

        return normalizedPath
    }
}
