import Foundation

enum SSHConfigWriterError: LocalizedError, Equatable, Sendable {
    case emptyHost
    case invalidHost
    case invalidPropertyName(String)
    case invalidPropertyValue(String)
    case hostBlockNotFound

    var errorDescription: String? {
        switch self {
        case .emptyHost:
            return "Host alias is required."
        case .invalidHost:
            return "Host alias cannot contain line breaks."
        case .invalidPropertyName(let name):
            return "\(name) is not a valid SSH config property name."
        case .invalidPropertyValue(let name):
            return "\(name) value cannot contain line breaks."
        case .hostBlockNotFound:
            return "The selected Host block could not be found in SSH config."
        }
    }
}

enum SSHConfigWriter {
    nonisolated static var propertyIndent: String { "    " }
    nonisolated private static var newline: String { "\n" }

    nonisolated static func apply(
        _ mutation: SSHConfigMutation,
        inDirectory directoryPath: String,
        propertyIndentation: SSHConfigHostPropertyIndentation = .default,
        backupLimit: Int = SSHConfigBackupLimit.default
    ) throws {
        let directoryURL: URL

        switch mutation {
        case .add:
            directoryURL = try preparedConfigDirectoryURL(for: directoryPath)
        case .update, .delete:
            directoryURL = URL(
                fileURLWithPath: (directoryPath as NSString).expandingTildeInPath,
                isDirectory: true
            )
        }

        try apply(
            mutation,
            in: directoryURL.appendingPathComponent("config"),
            propertyIndentation: propertyIndentation,
            backupLimit: backupLimit
        )
    }

    nonisolated static func apply(
        _ mutation: SSHConfigMutation,
        in configURL: URL,
        propertyIndentation: SSHConfigHostPropertyIndentation = .default,
        backupLimit: Int = SSHConfigBackupLimit.default
    ) throws {
        let existingContents: String

        switch mutation {
        case .add:
            existingContents = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        case .update, .delete:
            existingContents = try String(contentsOf: configURL, encoding: .utf8)
        }

        let lineEnding = preferredLineEnding(for: existingContents)
        let snapshot = SSHConfigParser.parseDocument(existingContents, configPath: configURL.path)
        let updatedSnapshot = try snapshot.applying(
            mutation,
            configPath: configURL.path,
            lineEnding: lineEnding,
            propertyIndentation: propertyIndentation
        )
        let updatedContents = updatedSnapshot.renderedContents(
            normalizingHostIndentation: true,
            propertyIndent: propertyIndentation.value
        )

        try createBackupIfNeeded(for: configURL, limit: backupLimit)
        try updatedContents.write(to: configURL, atomically: true, encoding: .utf8)
    }

    nonisolated static func appendHost(_ request: SSHConfigHostSaveRequest, toDirectory directoryPath: String) throws {
        try apply(.add(request), inDirectory: directoryPath)
    }

    nonisolated static func createEmptyConfig(inDirectory directoryPath: String) throws {
        let directoryURL = URL(
            fileURLWithPath: SSHWorkspacePath.normalizeDirectoryPath(directoryPath),
            isDirectory: true
        )
        let configURL = directoryURL.appendingPathComponent("config")

        guard !FileManager.default.fileExists(atPath: configURL.path) else {
            return
        }

        try "".write(to: configURL, atomically: true, encoding: .utf8)
    }

    nonisolated static func appendHost(_ request: SSHConfigHostSaveRequest, to configURL: URL) throws {
        try apply(.add(request), in: configURL)
    }

    nonisolated static func replaceHost(
        _ entry: SSHConfigEntry,
        with request: SSHConfigHostSaveRequest,
        inDirectory directoryPath: String
    ) throws {
        try apply(.update(entry: entry, request: request), inDirectory: directoryPath)
    }

    nonisolated static func replaceHost(
        _ entry: SSHConfigEntry,
        with request: SSHConfigHostSaveRequest,
        in configURL: URL
    ) throws {
        try apply(.update(entry: entry, request: request), in: configURL)
    }

    nonisolated static func deleteHost(_ entry: SSHConfigEntry, inDirectory directoryPath: String) throws {
        try apply(.delete(entry: entry), inDirectory: directoryPath)
    }

    nonisolated static func deleteHost(_ entry: SSHConfigEntry, in configURL: URL) throws {
        try apply(.delete(entry: entry), in: configURL)
    }

    nonisolated static func renderedEntry(
        for request: SSHConfigHostSaveRequest,
        lineEnding: String = newline,
        propertyIndentation: SSHConfigHostPropertyIndentation = .default
    ) throws -> String {
        let host = request.trimmedHost

        guard !host.isEmpty else {
            throw SSHConfigWriterError.emptyHost
        }

        guard !host.contains(where: \.isNewline) else {
            throw SSHConfigWriterError.invalidHost
        }

        var lines = ["Host \(host)"]

        for property in request.writableProperties {
            let name = property.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = property.value.trimmingCharacters(in: .whitespacesAndNewlines)

            guard isValidPropertyName(name) else {
                throw SSHConfigWriterError.invalidPropertyName(name)
            }

            guard !value.contains(where: \.isNewline) else {
                throw SSHConfigWriterError.invalidPropertyValue(name)
            }

            lines.append("\(propertyIndentation.value)\(name) \(value)")
        }

        return lines.joined(separator: lineEnding) + lineEnding
    }

    nonisolated static func append(entry: String, to existingContents: String) -> String {
        let lineEnding = preferredLineEnding(for: existingContents)
        let normalizedEntry = normalizeLineEndings(in: entry, to: lineEnding)
        let snapshot = SSHConfigParser.parseDocument(existingContents, configPath: "/tmp/config")
        guard let updatedSnapshot = try? snapshot.appendingHost(
            with: normalizedEntry,
            configPath: "/tmp/config",
            lineEnding: lineEnding
        ) else {
            return existingContents + appendSeparator(for: existingContents, lineEnding: lineEnding) + normalizedEntry
        }

        return updatedSnapshot.renderedContents(normalizingHostIndentation: true)
    }

    nonisolated static func replace(
        entry: SSHConfigEntry,
        with renderedEntry: String,
        in existingContents: String,
        configPath: String
    ) throws -> String {
        let lineEnding = preferredLineEnding(for: existingContents)
        let normalizedEntry = normalizeLineEndings(in: renderedEntry, to: lineEnding)
        let snapshot = SSHConfigParser.parseDocument(existingContents, configPath: configPath)
        return try snapshot.replacingHost(matching: entry, with: normalizedEntry, configPath: configPath)
            .renderedContents(normalizingHostIndentation: true)
    }

    nonisolated static func deleteHost(
        entry: SSHConfigEntry,
        from existingContents: String,
        configPath: String
    ) throws -> String {
        let snapshot = SSHConfigParser.parseDocument(existingContents, configPath: configPath)
        return try snapshot.removingHost(matching: entry).renderedContents(normalizingHostIndentation: true)
    }

    nonisolated private static func isValidPropertyName(_ name: String) -> Bool {
        let normalizedName = name.lowercased()
        guard normalizedName != "host", normalizedName != "match" else {
            return false
        }

        return !name.isEmpty && name.allSatisfy { character in
            character.isLetter || character.isNumber
        }
    }

    nonisolated private static func preparedConfigDirectoryURL(for path: String) throws -> URL {
        let directoryURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw CocoaError(.fileWriteFileExists)
            }

            return directoryURL
        }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        return directoryURL
    }

    nonisolated private static func createBackupIfNeeded(for configURL: URL, limit: Int) throws {
        let clampedLimit = SSHConfigBackupLimit.clamped(limit)
        guard clampedLimit > 0 else {
            return
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: configURL.path) else {
            return
        }

        for index in stride(from: SSHConfigBackupLimit.maximum, to: clampedLimit, by: -1) {
            let excessBackupURL = backupURL(for: configURL, index: index)
            if fileManager.fileExists(atPath: excessBackupURL.path) {
                try fileManager.removeItem(at: excessBackupURL)
            }
        }

        let oldestBackupURL = backupURL(for: configURL, index: clampedLimit)
        if fileManager.fileExists(atPath: oldestBackupURL.path) {
            try fileManager.removeItem(at: oldestBackupURL)
        }

        guard clampedLimit > 1 else {
            try fileManager.copyItem(at: configURL, to: oldestBackupURL)
            return
        }

        for index in stride(from: clampedLimit - 1, through: 1, by: -1) {
            let sourceURL = backupURL(for: configURL, index: index)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                continue
            }

            let destinationURL = backupURL(for: configURL, index: index + 1)
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }

        try fileManager.copyItem(at: configURL, to: backupURL(for: configURL, index: 1))
    }

    nonisolated private static func backupURL(for configURL: URL, index: Int) -> URL {
        configURL.deletingLastPathComponent()
            .appendingPathComponent("\(configURL.lastPathComponent).backup.\(index)")
    }

    nonisolated fileprivate static func appendSeparator(
        for existingContents: String,
        lineEnding: String = newline
    ) -> String {
        guard !existingContents.isEmpty else {
            return ""
        }

        let trailingNewlines = existingContents.reversed().prefix(while: { $0 == "\n" }).count
        if trailingNewlines >= 2 {
            return ""
        }

        if trailingNewlines == 1 {
            return lineEnding
        }

        return lineEnding + lineEnding
    }

    nonisolated private static func preferredLineEnding(for contents: String) -> String {
        if contents.contains("\r\n") {
            return "\r\n"
        }

        if contents.contains("\r") {
            return "\r"
        }

        return newline
    }

    nonisolated private static func normalizeLineEndings(in text: String, to lineEnding: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: lineEnding)
    }
}

private extension SSHConfigDocumentSnapshot {
    nonisolated func applying(
        _ mutation: SSHConfigMutation,
        configPath: String,
        lineEnding: String,
        propertyIndentation: SSHConfigHostPropertyIndentation
    ) throws -> SSHConfigDocumentSnapshot {
        switch mutation {
        case .add(let request):
            let renderedEntry = try SSHConfigWriter.renderedEntry(
                for: request,
                lineEnding: lineEnding,
                propertyIndentation: propertyIndentation
            )
            return try appendingHost(with: renderedEntry, configPath: configPath, lineEnding: lineEnding)
        case .update(let entry, let request):
            let renderedEntry = try SSHConfigWriter.renderedEntry(
                for: request,
                lineEnding: lineEnding,
                propertyIndentation: propertyIndentation
            )
            return try replacingHost(matching: entry, with: renderedEntry, configPath: configPath)
        case .delete(let entry):
            return try removingHost(matching: entry)
        }
    }

    nonisolated func appendingHost(
        with renderedEntry: String,
        configPath: String,
        lineEnding: String
    ) throws -> SSHConfigDocumentSnapshot {
        let appendedBlock = try hostBlock(from: renderedEntry, configPath: configPath)
        var updatedSegments = segments
        let separator = SSHConfigWriter.appendSeparator(for: renderedContents(), lineEnding: lineEnding)

        if !separator.isEmpty {
            updatedSegments.append(.text(separator))
        }

        updatedSegments.append(.host(appendedBlock))
        return SSHConfigDocumentSnapshot(segments: updatedSegments)
    }

    nonisolated func replacingHost(
        matching entry: SSHConfigEntry,
        with renderedEntry: String,
        configPath: String
    ) throws -> SSHConfigDocumentSnapshot {
        let replacementBlock = try hostBlock(from: renderedEntry, configPath: configPath)
        let replacementIndex = try matchingHostIndex(for: entry)
        var updatedSegments = segments
        updatedSegments[replacementIndex] = .host(replacementBlock)
        return SSHConfigDocumentSnapshot(segments: updatedSegments)
    }

    nonisolated func removingHost(matching entry: SSHConfigEntry) throws -> SSHConfigDocumentSnapshot {
        let removalIndex = try matchingHostIndex(for: entry)
        var updatedSegments = segments
        updatedSegments.remove(at: removalIndex)
        updatedSegments = mergeAdjacentTextSegments(updatedSegments)
        updatedSegments = normalizeWhitespaceOnlyTextSegments(updatedSegments)
        return SSHConfigDocumentSnapshot(segments: updatedSegments)
    }

    nonisolated private func mergeAdjacentTextSegments(_ segments: [SSHConfigDocumentSegment]) -> [SSHConfigDocumentSegment] {
        var mergedSegments: [SSHConfigDocumentSegment] = []

        for segment in segments {
            switch (mergedSegments.last, segment) {
            case (.some(.text(let previousText)), .text(let nextText)):
                mergedSegments.removeLast()
                mergedSegments.append(.text(previousText + nextText))
            default:
                mergedSegments.append(segment)
            }
        }

        return mergedSegments
    }

    nonisolated private func normalizeWhitespaceOnlyTextSegments(_ segments: [SSHConfigDocumentSegment]) -> [SSHConfigDocumentSegment] {
        segments.enumerated().map { index, segment in
            guard case .text(let text) = segment else {
                return segment
            }

            let lines = SSHConfigLineRecord.split(text)
            let previousIsHost = if index > 0 {
                if case .host = segments[index - 1] {
                    true
                } else {
                    false
                }
            } else {
                false
            }
            let nextIsHost = if index < segments.index(before: segments.endIndex) {
                if case .host = segments[index + 1] {
                    true
                } else {
                    false
                }
            } else {
                false
            }

            if lines.contains(where: { !$0.isBlank }) {
                guard nextIsHost else {
                    return segment
                }

                let trailingBlankCount = lines.reversed().prefix(while: { $0.isBlank }).count
                guard trailingBlankCount > 1 else {
                    return segment
                }

                let keptBlankLine = lines[lines.count - trailingBlankCount]
                let normalizedText = lines.dropLast(trailingBlankCount).map(\.rawText).joined() + keptBlankLine.rawText
                return .text(normalizedText)
            }

            if previousIsHost && nextIsHost {
                if let separatorLine = lines.first(where: \.isBlank) {
                    return .text(separatorLine.rawText)
                }

                return .text("")
            }

            if previousIsHost || nextIsHost {
                return .text("")
            }

            return segment
        }
    }

    nonisolated private func matchingHostIndex(for entry: SSHConfigEntry) throws -> Int {
        let fingerprintMatchedIndexes = segments.indices.filter { index in
            guard case .host(let block) = segments[index] else {
                return false
            }

            return block.entry.host == entry.host
                && block.entry.sourceFingerprint == entry.sourceFingerprint
        }

        switch fingerprintMatchedIndexes.count {
        case 1:
            return fingerprintMatchedIndexes[0]
        case 0:
            throw SSHConfigWriterError.hostBlockNotFound
        default:
            let lineMatchedIndexes = fingerprintMatchedIndexes.filter { index in
                guard case .host(let block) = segments[index] else {
                    return false
                }

                return block.entry.lineNumber == entry.lineNumber
            }

            guard lineMatchedIndexes.count == 1 else {
                throw SSHConfigWriterError.hostBlockNotFound
            }

            return lineMatchedIndexes[0]
        }
    }

    nonisolated private func hostBlock(
        from renderedEntry: String,
        configPath: String
    ) throws -> SSHConfigHostBlockSnapshot {
        let replacementSnapshot = SSHConfigParser.parseDocument(renderedEntry, configPath: configPath)
        guard replacementSnapshot.segments.count == 1,
              case .host(let replacementBlock) = replacementSnapshot.segments[0] else {
            throw SSHConfigWriterError.hostBlockNotFound
        }

        return replacementBlock
    }
}
