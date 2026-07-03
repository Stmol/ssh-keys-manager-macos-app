import Foundation

struct SSHConfigDocument: Equatable {
    private let configURL: URL
    private let lineEnding: String
    private var snapshot: SSHConfigDocumentSnapshot

    nonisolated var entries: [SSHConfigEntry] {
        snapshot.entries
    }

    nonisolated static func load(fromDirectory directoryPath: String) throws -> Self {
        let configURL = sshConfigURL(for: directoryPath)
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw SSHConfigLoadError.fileMissing(path: SSHWorkspacePath.configDisplayPath(for: directoryPath))
        }

        return try load(from: configURL)
    }

    nonisolated static func loadIfPresent(fromDirectory directoryPath: String) throws -> Self? {
        let configURL = sshConfigURL(for: directoryPath)
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return nil
        }

        return try load(from: configURL)
    }

    nonisolated static func loadOrCreateForMutation(
        _ mutation: SSHConfigMutation,
        fromDirectory directoryPath: String
    ) throws -> Self {
        switch mutation {
        case .add:
            try createEmptyIfMissing(inDirectory: directoryPath)
            return try load(fromDirectory: directoryPath)
        case .update, .delete:
            return try load(fromDirectory: directoryPath)
        }
    }

    nonisolated static func createEmptyIfMissing(inDirectory directoryPath: String) throws {
        try SSHConfigWriter.createEmptyConfig(inDirectory: directoryPath)
    }

    nonisolated mutating func applyHostMutation(
        _ mutation: SSHConfigMutation,
        propertyIndentation: SSHConfigHostPropertyIndentation
    ) throws {
        snapshot = try snapshot.applying(
            mutation,
            configPath: configURL.path,
            lineEnding: lineEnding,
            propertyIndentation: propertyIndentation
        )
    }

    nonisolated mutating func renameIdentityFileReferences(_ replacements: [String: String]) throws {
        guard !replacements.isEmpty else {
            return
        }

        let originalContents = snapshot.renderedContents()
        let updatedContents = Self.updatedSSHConfigContents(
            originalContents,
            replacements: pathReplacementsWithTildeAliases(replacements)
        )

        guard updatedContents != originalContents else {
            return
        }

        snapshot = SSHConfigParser.parseDocument(updatedContents, configPath: configURL.path)
    }

    nonisolated func write(
        propertyIndentation: SSHConfigHostPropertyIndentation,
        backupLimit: Int
    ) throws {
        let updatedContents = snapshot.renderedContents(
            normalizingHostIndentation: true,
            propertyIndent: propertyIndentation.value
        )
        try SSHConfigWriter.createBackupIfNeeded(for: configURL, limit: backupLimit)
        try updatedContents.write(to: configURL, atomically: true, encoding: .utf8)
    }

    nonisolated private static func load(from configURL: URL) throws -> Self {
        let contents = try String(contentsOf: configURL, encoding: .utf8)
        return Self(
            configURL: configURL,
            lineEnding: SSHConfigWriter.preferredLineEnding(for: contents),
            snapshot: SSHConfigParser.parseDocument(contents, configPath: configURL.path)
        )
    }

    nonisolated private static func sshConfigURL(for directoryPath: String) -> URL {
        URL(fileURLWithPath: SSHWorkspacePath.normalizeDirectoryPath(directoryPath), isDirectory: true)
            .appendingPathComponent("config")
    }

    nonisolated private func pathReplacementsWithTildeAliases(_ replacements: [String: String]) -> [String: String] {
        var expanded = replacements

        for (oldPath, newPath) in replacements {
            expanded[tildePath(for: oldPath)] = tildePath(for: newPath)
        }

        return expanded
    }

    nonisolated private func tildePath(for path: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == homePath || path.hasPrefix(homePath + "/") else {
            return path
        }

        return "~" + path.dropFirst(homePath.count)
    }

    nonisolated private static func updatedSSHConfigContents(
        _ contents: String,
        replacements: [String: String]
    ) -> String {
        contents
            .components(separatedBy: "\n")
            .map { updatedSSHConfigLine($0, replacements: replacements) }
            .joined(separator: "\n")
    }

    nonisolated private static func updatedSSHConfigLine(
        _ line: String,
        replacements: [String: String]
    ) -> String {
        let lineEnding = line.hasSuffix("\r") ? "\r" : ""
        let contentLine = lineEnding.isEmpty ? line : String(line.dropLast())
        let leadingWhitespace = contentLine.prefix { $0 == " " || $0 == "\t" }
        let remainder = contentLine.dropFirst(leadingWhitespace.count)
        let keyword = "IdentityFile"

        guard remainder.lowercased().hasPrefix(keyword.lowercased()) else {
            return line
        }

        let afterKeyword = remainder.dropFirst(keyword.count)
        guard let firstSeparator = afterKeyword.first, firstSeparator == " " || firstSeparator == "\t" else {
            return line
        }

        let separator = afterKeyword.prefix { $0 == " " || $0 == "\t" }
        let valueAndSuffix = afterKeyword.dropFirst(separator.count)
        guard let parsedValue = sshConfigValue(in: valueAndSuffix) else {
            return line
        }

        guard let replacement = replacements[parsedValue.value] else {
            return line
        }

        let updatedValue: String
        if let quote = parsedValue.quote {
            updatedValue = "\(quote)\(replacement)\(quote)"
        } else {
            updatedValue = replacement
        }

        return "\(leadingWhitespace)\(keyword)\(separator)\(updatedValue)\(parsedValue.suffix)\(lineEnding)"
    }

    nonisolated private static func sshConfigValue(in valueAndSuffix: Substring) -> SSHConfigValue? {
        guard let firstCharacter = valueAndSuffix.first else {
            return nil
        }

        if firstCharacter == "\"" || firstCharacter == "'" {
            let quote = firstCharacter
            let afterOpeningQuote = valueAndSuffix.dropFirst()
            guard let closingQuoteIndex = afterOpeningQuote.firstIndex(of: quote) else {
                return nil
            }

            return SSHConfigValue(
                value: String(afterOpeningQuote[..<closingQuoteIndex]),
                quote: quote,
                suffix: String(afterOpeningQuote[afterOpeningQuote.index(after: closingQuoteIndex)...])
            )
        }

        let value = valueAndSuffix.prefix { !$0.isWhitespace && $0 != "#" }
        guard !value.isEmpty else {
            return nil
        }

        return SSHConfigValue(
            value: String(value),
            quote: nil,
            suffix: String(valueAndSuffix.dropFirst(value.count))
        )
    }
}

private struct SSHConfigValue {
    let value: String
    let quote: Character?
    let suffix: String
}
