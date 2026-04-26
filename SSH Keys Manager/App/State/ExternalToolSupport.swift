import Foundation

enum ExternalTool: String, CaseIterable, Identifiable, Sendable {
    case sshKeygen

    nonisolated var id: Self { self }

    nonisolated var displayName: String {
        switch self {
        case .sshKeygen:
            "ssh-keygen"
        }
    }

    nonisolated var defaultPath: String {
        switch self {
        case .sshKeygen:
            "/usr/bin/ssh-keygen"
        }
    }
}

enum ExternalToolStatus: Sendable {
    case available(String)
    case missing(String)
    case notExecutable(String)
    case invalidBinary(String)

    nonisolated var path: String {
        switch self {
        case .available(let path), .missing(let path), .notExecutable(let path), .invalidBinary(let path):
            path
        }
    }

    nonisolated var isAvailable: Bool {
        if case .available = self {
            return true
        }

        return false
    }

    nonisolated var title: String {
        switch self {
        case .available:
            "Found"
        case .missing:
            "Missing"
        case .notExecutable:
            "Not executable"
        case .invalidBinary:
            "Invalid binary"
        }
    }

    nonisolated var warningMessage: String? {
        switch self {
        case .available:
            nil
        case .missing(let path):
            "ssh-keygen was not found at \(ExternalToolPath.displayPath(for: path)). Choose the binary in Settings to enable key generation and passphrase changes."
        case .notExecutable(let path):
            "ssh-keygen at \(ExternalToolPath.displayPath(for: path)) is not executable. Choose a valid binary in Settings."
        case .invalidBinary(let path):
            "The file at \(ExternalToolPath.displayPath(for: path)) does not behave like ssh-keygen. Choose the real ssh-keygen binary in Settings."
        }
    }
}

enum ExternalToolPath {
    nonisolated static func normalizeExecutablePath(_ path: String, defaultPath: String) -> String {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let inputPath = trimmedPath.isEmpty ? defaultPath : trimmedPath
        let expandedPath = (inputPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath, isDirectory: false)
            .standardizedFileURL
            .path
    }

    nonisolated static func displayPath(for path: String) -> String {
        let normalizedPath = normalizeExecutablePath(path, defaultPath: path)
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path

        if normalizedPath == homePath {
            return "~"
        }

        if normalizedPath.hasPrefix(homePath + "/") {
            return "~" + normalizedPath.dropFirst(homePath.count)
        }

        return normalizedPath
    }
}

struct ExternalToolValidator: Sendable {
    nonisolated(unsafe) private let fileManager: FileManager

    nonisolated init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    nonisolated func status(for tool: ExternalTool, path: String) -> ExternalToolStatus {
        let normalizedPath = ExternalToolPath.normalizeExecutablePath(path, defaultPath: tool.defaultPath)
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: normalizedPath, isDirectory: &isDirectory) else {
            return .missing(normalizedPath)
        }

        guard !isDirectory.boolValue, fileManager.isExecutableFile(atPath: normalizedPath) else {
            return .notExecutable(normalizedPath)
        }

        guard probeSSHKeygenBinary(at: normalizedPath) else {
            return .invalidBinary(normalizedPath)
        }

        return .available(normalizedPath)
    }

    nonisolated private func probeSSHKeygenBinary(at path: String) -> Bool {
        do {
            let result = try ExternalToolProbeRunner.run(
                executableURL: URL(fileURLWithPath: path),
                arguments: ["-?"],
                timeout: 5
            )

            let output = [result.standardOutput, result.standardError]
                .joined(separator: "\n")
                .lowercased()

            return output.contains("usage: ssh-keygen")
                && output.contains("ssh-keygen")
                && output.contains("ed25519")
                && output.contains("[-t")
        } catch {
            return false
        }
    }
}

private enum ExternalToolProbeRunner {
    struct Result {
        let terminationStatus: Int32
        let standardOutput: String
        let standardError: String
    }

    nonisolated static func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> Result {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let terminationSemaphore = DispatchSemaphore(value: 0)

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }

        defer {
            process.terminationHandler = nil
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
        }

        try process.run()

        if terminationSemaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw ExternalToolProbeError.timedOut(executableURL.path)
        }

        return Result(
            terminationStatus: process.terminationStatus,
            standardOutput: String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "",
            standardError: String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
        )
    }
}

private enum ExternalToolProbeError: LocalizedError {
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let path):
            return "Timed out while probing \(path)"
        }
    }
}
