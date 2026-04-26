import CryptoKit
import Foundation

enum SSHConfigLoadError: LocalizedError {
    case fileMissing(path: String)

    var errorDescription: String? {
        switch self {
        case .fileMissing(let path):
            return "SSH config file does not exist at \(path)."
        }
    }
}

enum SSHConfigParser {
    nonisolated static func loadEntries(from directoryPath: String) throws -> [SSHConfigEntry] {
        let configURL = sshConfigURL(for: directoryPath)

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw SSHConfigLoadError.fileMissing(path: SSHWorkspacePath.configDisplayPath(for: directoryPath))
        }

        let contents = try String(contentsOf: configURL, encoding: .utf8)
        return parseDocument(contents, configPath: configURL.path).entries
    }

    nonisolated private static func sshConfigURL(for directoryPath: String) -> URL {
        URL(fileURLWithPath: SSHWorkspacePath.normalizeDirectoryPath(directoryPath), isDirectory: true)
            .appendingPathComponent("config")
    }

    nonisolated static func parseDocument(_ contents: String, configPath: String) -> SSHConfigDocumentSnapshot {
        let lines = SSHConfigLineRecord.split(contents)
        var segments: [SSHConfigDocumentSegment] = []
        var textBuffer = ""
        var current: PartialSSHConfigHostBlockSnapshot?

        func flushTextBuffer() {
            guard !textBuffer.isEmpty else {
                return
            }

            segments.append(.text(textBuffer))
            textBuffer = ""
        }

        func appendBlock(_ block: PartialSSHConfigHostBlockSnapshot) {
            guard let snapshot = block.snapshot(configPath: configPath) else {
                return
            }

            segments.append(.host(snapshot))
        }

        func transitionOutOfBlock() {
            guard let current else {
                return
            }

            appendBlock(current)
            textBuffer += current.pendingTrailingTrivia
        }

        for line in lines {
            let directive = SSHConfigDirective(line.content)

            if var activeBlock = current {
                if directive?.key == "host" || directive?.key == "match" {
                    transitionOutOfBlock()
                    current = nil

                    if directive?.key == "host" {
                        flushTextBuffer()
                        current = PartialSSHConfigHostBlockSnapshot(
                            host: directive?.value ?? "",
                            lineNumber: line.number,
                            firstLine: line.rawText
                        )
                    } else {
                        textBuffer += line.rawText
                    }

                    continue
                }

                if line.isTrivia {
                    current = activeBlock.appendingPendingTrivia(line.rawText)
                    continue
                }

                activeBlock = activeBlock.confirmPendingTrivia()
                activeBlock.append(line.rawText)

                if let directive {
                    activeBlock.apply(directive)
                }

                current = activeBlock
                continue
            }

            guard let directive, directive.key == "host" else {
                textBuffer += line.rawText
                continue
            }

            flushTextBuffer()
            current = PartialSSHConfigHostBlockSnapshot(
                host: directive.value,
                lineNumber: line.number,
                firstLine: line.rawText
            )
        }

        if let current {
            appendBlock(current)
            textBuffer += current.pendingTrailingTrivia
        }

        flushTextBuffer()
        return SSHConfigDocumentSnapshot(segments: segments)
    }
}

struct SSHConfigDocumentSnapshot: Equatable {
    var segments: [SSHConfigDocumentSegment]

    nonisolated var entries: [SSHConfigEntry] {
        segments.compactMap {
            guard case .host(let block) = $0 else {
                return nil
            }

            return block.entry
        }
    }

    nonisolated func renderedContents(
        normalizingHostIndentation: Bool = false,
        propertyIndent: String = SSHConfigWriter.propertyIndent
    ) -> String {
        segments.map {
            $0.renderedRawText(
                normalizingHostIndentation: normalizingHostIndentation,
                propertyIndent: propertyIndent
            )
        }.joined()
    }
}

enum SSHConfigDocumentSegment: Equatable {
    case text(String)
    case host(SSHConfigHostBlockSnapshot)

    nonisolated var rawText: String {
        switch self {
        case .text(let text):
            return text
        case .host(let block):
            return block.rawText
        }
    }

    nonisolated func renderedRawText(normalizingHostIndentation: Bool, propertyIndent: String) -> String {
        switch self {
        case .text(let text):
            return text
        case .host(let block):
            guard normalizingHostIndentation else {
                return block.rawText
            }

            return block.normalizedRawText(propertyIndent: propertyIndent)
        }
    }
}

struct SSHConfigHostBlockSnapshot: Equatable {
    let entry: SSHConfigEntry
    let rawText: String

    nonisolated func normalizedRawText(propertyIndent: String) -> String {
        SSHConfigLineRecord.split(rawText).enumerated().map { index, line in
            guard index > 0,
                  !line.isTrivia,
                  let directive = SSHConfigDirective(line.content),
                  directive.key != "host",
                  directive.key != "match" else {
                return line.rawText
            }

            let contentWithoutLeadingWhitespace = String(
                line.content.drop(while: { $0 == " " || $0 == "\t" })
            )
            return propertyIndent + contentWithoutLeadingWhitespace + line.lineEnding
        }.joined()
    }
}

struct SSHConfigDirective {
    let key: String
    let name: String
    let value: String

    nonisolated init?(_ rawLine: String) {
        let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)

        guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else {
            return nil
        }

        let parts = trimmedLine.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })

        guard parts.count == 2 else {
            return nil
        }

        key = parts[0].lowercased()
        name = String(parts[0])
        value = String(parts[1]).trimmingCharacters(in: .whitespaces)
    }
}

private struct PartialSSHConfigHostBlockSnapshot {
    let host: String
    let lineNumber: Int
    private(set) var rawText: String
    private(set) var pendingTrailingTrivia: String
    var fields: [SSHConfigField]

    nonisolated init(host: String, lineNumber: Int, firstLine: String) {
        self.host = host
        self.lineNumber = lineNumber
        rawText = firstLine
        pendingTrailingTrivia = ""
        self.fields = [
            SSHConfigField(
                id: "\(lineNumber):host",
                name: "Host",
                value: host,
                normalizedName: "host"
            )
        ]
    }

    nonisolated mutating func append(_ text: String) {
        rawText += text
    }

    nonisolated func appendingPendingTrivia(_ text: String) -> Self {
        var copy = self
        copy.pendingTrailingTrivia += text
        return copy
    }

    nonisolated func confirmPendingTrivia() -> Self {
        var copy = self
        copy.rawText += copy.pendingTrailingTrivia
        copy.pendingTrailingTrivia = ""
        return copy
    }

    nonisolated mutating func apply(_ directive: SSHConfigDirective) {
        fields.append(
            SSHConfigField(
                id: "\(lineNumber):\(fields.count):\(directive.key)",
                name: directive.name,
                value: directive.value,
                normalizedName: directive.key
            )
        )
    }

    nonisolated func snapshot(configPath: String) -> SSHConfigHostBlockSnapshot? {
        guard !host.isEmpty else {
            return nil
        }

        let fingerprint = SHA256.hash(data: Data(rawText.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let entry = SSHConfigEntry(
            id: "\(configPath):\(lineNumber):\(host)",
            host: host,
            lineNumber: lineNumber,
            fields: fields,
            sourceFingerprint: fingerprint
        )
        return SSHConfigHostBlockSnapshot(entry: entry, rawText: rawText)
    }
}

struct SSHConfigLineRecord: Equatable {
    let number: Int
    let content: String
    let lineEnding: String

    nonisolated var rawText: String {
        content + lineEnding
    }

    nonisolated var isBlank: Bool {
        content.trimmingCharacters(in: .whitespaces).isEmpty
    }

    nonisolated var isComment: Bool {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.hasPrefix("#")
    }

    nonisolated var isTrivia: Bool {
        isBlank || isComment
    }

    nonisolated static func split(_ contents: String) -> [SSHConfigLineRecord] {
        guard !contents.isEmpty else {
            return []
        }

        let nsContents = contents as NSString
        var lines: [SSHConfigLineRecord] = []
        var lineNumber = 1
        var location = 0

        while location < nsContents.length {
            let contentStart = location

            while location < nsContents.length {
                let scalar = nsContents.character(at: location)
                if scalar == 0x0A || scalar == 0x0D {
                    break
                }

                location += 1
            }

            let content = nsContents.substring(
                with: NSRange(location: contentStart, length: location - contentStart)
            )
            var lineEnding = ""

            if location < nsContents.length {
                let scalar = nsContents.character(at: location)
                if scalar == 0x0D {
                    if location + 1 < nsContents.length,
                       nsContents.character(at: location + 1) == 0x0A {
                        lineEnding = "\r\n"
                        location += 2
                    } else {
                        lineEnding = "\r"
                        location += 1
                    }
                } else {
                    lineEnding = "\n"
                    location += 1
                }
            }

            lines.append(
                SSHConfigLineRecord(
                    number: lineNumber,
                    content: content,
                    lineEnding: lineEnding
                )
            )
            lineNumber += 1
        }

        return lines
    }
}
