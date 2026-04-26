import CryptoKit
import Darwin
import Foundation

struct SSHKeyStore: @unchecked Sendable {
    nonisolated(unsafe) private let fileManager: FileManager
    nonisolated private let sshKeygenURL: URL

    nonisolated init(
        fileManager: FileManager = .default,
        sshKeygenURL: URL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
    ) {
        self.fileManager = fileManager
        self.sshKeygenURL = sshKeygenURL
    }

    nonisolated func updatingSSHKeygenURL(_ sshKeygenURL: URL) -> Self {
        Self(fileManager: fileManager, sshKeygenURL: sshKeygenURL)
    }

    nonisolated func loadKeys(from directoryPath: String) throws -> SSHKeyInventory {
        let directoryURL = expandedDirectoryURL(for: directoryPath)
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let regularFileURLs = fileURLs.filter { isRegularFile($0) }
        var pairedPublicKeyPaths = Set<String>()
        var pairedPrivateKeyPaths = Set<String>()

        let completePairs = regularFileURLs.compactMap { privateKeyURL -> SSHKeyItem? in
            guard privateKeyURL.pathExtension != "pub" else {
                return nil
            }

            let publicKeyURL = privateKeyURL.appendingPathExtension("pub")
            guard let item = completePairItem(privateKeyURL: privateKeyURL, publicKeyURL: publicKeyURL) else {
                return nil
            }

            pairedPrivateKeyPaths.insert(privateKeyURL.path)
            pairedPublicKeyPaths.insert(publicKeyURL.path)
            return item
        }

        let otherKeys = regularFileURLs.compactMap { fileURL -> SSHKeyItem? in
            guard !pairedPrivateKeyPaths.contains(fileURL.path), !pairedPublicKeyPaths.contains(fileURL.path) else {
                return nil
            }

            return standaloneKeyItem(for: fileURL)
        }

        return SSHKeyInventory(completePairs: completePairs, otherKeys: otherKeys)
    }

    nonisolated func delete(_ key: SSHKeyItem) throws {
        for path in key.pathsToDelete {
            let url = URL(fileURLWithPath: path)

            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    nonisolated func updateComment(for key: SSHKeyItem, comment: String) throws {
        guard let publicKeyPath = key.publicKeyPath else {
            throw SSHKeyStoreError.commentRequiresPublicKey
        }

        let publicKeyURL = URL(fileURLWithPath: publicKeyPath)
        guard
            let contents = try? String(contentsOf: publicKeyURL, encoding: .utf8),
            let line = contents.split(whereSeparator: \.isNewline).first
        else {
            throw SSHKeyStoreError.invalidPublicKey
        }

        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, isSupportedPublicKeyType(String(parts[0])) else {
            throw SSHKeyStoreError.invalidPublicKey
        }

        let normalizedComment = comment
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedLine: String
        if normalizedComment.isEmpty {
            updatedLine = "\(parts[0]) \(parts[1])"
        } else {
            updatedLine = "\(parts[0]) \(parts[1]) \(normalizedComment)"
        }

        try "\(updatedLine)\n".write(to: publicKeyURL, atomically: true, encoding: .utf8)
    }

    nonisolated func changePassphrase(
        for key: SSHKeyItem,
        oldPassphrase: String,
        newPassphrase: String
    ) throws {
        guard let privateKeyPath = key.privateKeyPath else {
            throw SSHKeyStoreError.passphraseChangeRequiresPrivateKey
        }

        let privateKeyURL = URL(fileURLWithPath: privateKeyPath)
        guard fileManager.fileExists(atPath: privateKeyURL.path) else {
            throw SSHKeyStoreError.keyFileMissing(privateKeyURL.path)
        }

        try runSSHKeygenPassphraseChange(
            privateKeyURL: privateKeyURL,
            oldPassphrase: oldPassphrase,
            newPassphrase: newPassphrase
        )
    }

    nonisolated func rename(_ key: SSHKeyItem, to newName: String) throws -> String {
        let normalizedName = try normalizedKeyName(newName)
        let sourceURLs = key.pathsToRename.map(URL.init(fileURLWithPath:))
        guard !sourceURLs.isEmpty else {
            throw SSHKeyStoreError.noKeyFilesToRename
        }

        let primaryURL = URL(fileURLWithPath: key.filePath)
        let targetDirectoryURL = primaryURL.deletingLastPathComponent()
        let targetPrimaryURL = targetDirectoryURL.appendingPathComponent(
            targetName(for: key, normalizedName: normalizedName)
        )
        let targetURLs = targetURLs(
            for: key,
            normalizedName: normalizedName,
            targetPrimaryURL: targetPrimaryURL
        )

        try validateRenameTargets(sourceURLs: sourceURLs, targetURLs: targetURLs)

        var movedPairs: [(source: URL, target: URL)] = []
        do {
            for (sourceURL, targetURL) in zip(sourceURLs, targetURLs) where sourceURL.path != targetURL.path {
                try fileManager.moveItem(at: sourceURL, to: targetURL)
                movedPairs.append((source: sourceURL, target: targetURL))
            }

            try updateSSHConfigReferences(from: key, targetURLs: targetURLs)
            return targetPrimaryURL.path
        } catch {
            for movedPair in movedPairs.reversed() where fileManager.fileExists(atPath: movedPair.target.path) {
                try? fileManager.moveItem(at: movedPair.target, to: movedPair.source)
            }

            throw error
        }
    }

    nonisolated func duplicate(_ key: SSHKeyItem, to newName: String) throws -> String {
        let normalizedName = try normalizedKeyName(newName)
        let sourceURLs = key.pathsToRename.map(URL.init(fileURLWithPath:))
        guard !sourceURLs.isEmpty else {
            throw SSHKeyStoreError.noKeyFilesToRename
        }

        let primaryURL = URL(fileURLWithPath: key.filePath)
        let targetDirectoryURL = primaryURL.deletingLastPathComponent()
        let targetPrimaryURL = targetDirectoryURL.appendingPathComponent(
            targetName(for: key, normalizedName: normalizedName)
        )
        let targetURLs = targetURLs(
            for: key,
            normalizedName: normalizedName,
            targetPrimaryURL: targetPrimaryURL
        )

        try validateDuplicateTargets(sourceURLs: sourceURLs, targetURLs: targetURLs)

        var copiedURLs: [URL] = []
        do {
            for (sourceURL, targetURL) in zip(sourceURLs, targetURLs) {
                try fileManager.copyItem(at: sourceURL, to: targetURL)
                copiedURLs.append(targetURL)
            }

            return targetPrimaryURL.path
        } catch {
            for copiedURL in copiedURLs.reversed() where fileManager.fileExists(atPath: copiedURL.path) {
                try? fileManager.removeItem(at: copiedURL)
            }

            throw error
        }
    }

    nonisolated func generateKey(_ request: SSHKeyGenerationRequest, in directoryPath: String) throws -> String {
        let normalizedName = try normalizedGeneratedKeyName(request.fileName)
        let directoryURL = try preparedSSHDirectoryURL(for: directoryPath)
        let privateKeyURL = directoryURL.appendingPathComponent(normalizedName)
        let publicKeyURL = privateKeyURL.appendingPathExtension("pub")

        try validateGeneratedKeyTargets(privateKeyURL: privateKeyURL, publicKeyURL: publicKeyURL)

        do {
            try runSSHKeygen(request: request, privateKeyURL: privateKeyURL)
            try setGeneratedKeyPermissions(privateKeyURL: privateKeyURL, publicKeyURL: publicKeyURL)
            return privateKeyURL.path
        } catch {
            removeGeneratedKeyFiles(privateKeyURL: privateKeyURL, publicKeyURL: publicKeyURL)
            throw error
        }
    }

    nonisolated func availableKeyName(for baseName: String, in directoryPath: String) throws -> String {
        let normalizedBaseName = try normalizedGeneratedKeyName(baseName)
        let existingFileNames = try existingKeyFileNames(in: directoryPath)
        var candidate = normalizedBaseName
        var suffix = 1

        while generatedKeyFilesExist(named: candidate, existingFileNames: existingFileNames) {
            candidate = "\(normalizedBaseName)_\(suffix)"
            suffix += 1
        }

        return candidate
    }

    nonisolated func existingKeyFileNames(in directoryPath: String) throws -> Set<String> {
        let directoryURL = expandedDirectoryURL(for: directoryPath)
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return Set(
            fileURLs
                .filter { isRegularFile($0) }
                .map(\.lastPathComponent)
        )
    }

    nonisolated private func expandedDirectoryURL(for path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    nonisolated private func preparedSSHDirectoryURL(for path: String) throws -> URL {
        let directoryURL = expandedDirectoryURL(for: path)
        var isDirectory: ObjCBool = false

        if fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw SSHKeyStoreError.sshDirectoryIsNotDirectory(directoryURL.path)
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

    nonisolated private func normalizedKeyName(_ name: String) throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw SSHKeyStoreError.emptyKeyName
        }

        guard trimmedName.rangeOfCharacter(from: CharacterSet(charactersIn: "/:")) == nil else {
            throw SSHKeyStoreError.invalidKeyName
        }

        guard trimmedName != "." && trimmedName != ".." else {
            throw SSHKeyStoreError.invalidKeyName
        }

        return trimmedName
    }

    nonisolated private func normalizedGeneratedKeyName(_ name: String) throws -> String {
        let normalizedName = try normalizedKeyName(name)
        guard !normalizedName.hasSuffix(".pub") else {
            throw SSHKeyStoreError.invalidKeyName
        }

        return normalizedName
    }

    nonisolated private func normalizedKeyComment(_ comment: String) -> String {
        comment
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private func targetName(for key: SSHKeyItem, normalizedName: String) -> String {
        if key.kind == .publicKey, !normalizedName.hasSuffix(".pub") {
            return "\(normalizedName).pub"
        }

        return normalizedName
    }

    nonisolated private func targetURLs(
        for key: SSHKeyItem,
        normalizedName: String,
        targetPrimaryURL: URL
    ) -> [URL] {
        switch key.kind {
        case .completePair:
            return [
                targetPrimaryURL,
                targetPrimaryURL.appendingPathExtension("pub")
            ]
        case .privateKey:
            return [targetPrimaryURL]
        case .publicKey:
            return [targetPrimaryURL]
        }
    }

    nonisolated private func validateRenameTargets(sourceURLs: [URL], targetURLs: [URL]) throws {
        guard Set(targetURLs.map(\.path)).count == targetURLs.count else {
            throw SSHKeyStoreError.invalidKeyName
        }

        for (sourceURL, targetURL) in zip(sourceURLs, targetURLs) {
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw SSHKeyStoreError.keyFileMissing(sourceURL.path)
            }

            if sourceURL.path != targetURL.path, fileManager.fileExists(atPath: targetURL.path) {
                throw SSHKeyStoreError.keyNameAlreadyExists(targetURL.lastPathComponent)
            }
        }
    }

    nonisolated private func validateDuplicateTargets(sourceURLs: [URL], targetURLs: [URL]) throws {
        guard Set(targetURLs.map(\.path)).count == targetURLs.count else {
            throw SSHKeyStoreError.invalidKeyName
        }

        for (sourceURL, targetURL) in zip(sourceURLs, targetURLs) {
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw SSHKeyStoreError.keyFileMissing(sourceURL.path)
            }

            if fileManager.fileExists(atPath: targetURL.path) {
                throw SSHKeyStoreError.keyNameAlreadyExists(targetURL.lastPathComponent)
            }
        }
    }

    nonisolated private func validateGeneratedKeyTargets(privateKeyURL: URL, publicKeyURL: URL) throws {
        if fileManager.fileExists(atPath: privateKeyURL.path) {
            throw SSHKeyStoreError.keyNameAlreadyExists(privateKeyURL.lastPathComponent)
        }

        if fileManager.fileExists(atPath: publicKeyURL.path) {
            throw SSHKeyStoreError.keyNameAlreadyExists(publicKeyURL.lastPathComponent)
        }
    }

    nonisolated private func generatedKeyFilesExist(named name: String, existingFileNames: Set<String>) -> Bool {
        existingFileNames.contains(name) || existingFileNames.contains("\(name).pub")
    }

    nonisolated private func runSSHKeygen(request: SSHKeyGenerationRequest, privateKeyURL: URL) throws {
        do {
            let sshKeygenURL = try validatedSSHKeygenURL()
            let result = try ProcessRunner.runWithPseudoTerminal(
                executableURL: sshKeygenURL,
                arguments: sshKeygenArguments(for: request, privateKeyURL: privateKeyURL),
                responses: passphraseResponses(for: request.passphrase)
            )

            guard result.terminationStatus == 0 else {
                let message = result.standardError.isEmpty ? result.standardOutput : result.standardError
                throw SSHKeyStoreError.keyGenerationFailed(message)
            }
        } catch let error as SSHKeyStoreError {
            throw error
        } catch {
            throw SSHKeyStoreError.keyGenerationFailed(error.localizedDescription)
        }
    }

    nonisolated private func runSSHKeygenPassphraseChange(
        privateKeyURL: URL,
        oldPassphrase: String,
        newPassphrase: String
    ) throws {
        do {
            let sshKeygenURL = try validatedSSHKeygenURL()
            let result = try ProcessRunner.runWithPseudoTerminal(
                executableURL: sshKeygenURL,
                arguments: sshKeygenPassphraseArguments(privateKeyURL: privateKeyURL),
                responses: passphraseChangeResponses(
                    oldPassphrase: oldPassphrase,
                    newPassphrase: newPassphrase
                )
            )

            guard result.terminationStatus == 0 else {
                let message = result.standardError.isEmpty ? result.standardOutput : result.standardError
                throw SSHKeyStoreError.passphraseChangeFailed(message)
            }
        } catch let error as SSHKeyStoreError {
            throw error
        } catch {
            throw SSHKeyStoreError.passphraseChangeFailed(error.localizedDescription)
        }
    }

    nonisolated private func validatedSSHKeygenURL() throws -> URL {
        let status = ExternalToolValidator(fileManager: fileManager).status(
            for: .sshKeygen,
            path: sshKeygenURL.path
        )

        guard status.isAvailable else {
            throw SSHKeyStoreError.sshKeygenUnavailable(status)
        }

        return URL(fileURLWithPath: status.path)
    }

    nonisolated private func sshKeygenArguments(
        for request: SSHKeyGenerationRequest,
        privateKeyURL: URL
    ) -> [String] {
        var arguments = [
            "-q",
            "-t", request.keyType.sshKeygenType
        ]

        if let bitCount = request.keyType.bitCount {
            arguments += ["-b", "\(bitCount)"]
        }

        arguments += [
            "-f", privateKeyURL.path,
            "-C", normalizedKeyComment(request.comment)
        ]

        return arguments
    }

    nonisolated private func sshKeygenPassphraseArguments(privateKeyURL: URL) -> [String] {
        [
            "-p",
            "-f", privateKeyURL.path
        ]
    }

    nonisolated private func passphraseResponses(for passphrase: String?) -> [String] {
        let resolvedPassphrase = passphrase ?? ""
        return [resolvedPassphrase, resolvedPassphrase]
    }

    nonisolated private func passphraseChangeResponses(
        oldPassphrase: String,
        newPassphrase: String
    ) -> [String] {
        if oldPassphrase.isEmpty {
            return [newPassphrase, newPassphrase]
        }

        return [oldPassphrase, newPassphrase, newPassphrase]
    }

    nonisolated private func setGeneratedKeyPermissions(privateKeyURL: URL, publicKeyURL: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: privateKeyURL.path
        )
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o644)],
            ofItemAtPath: publicKeyURL.path
        )
    }

    nonisolated private func removeGeneratedKeyFiles(privateKeyURL: URL, publicKeyURL: URL) {
        for url in [privateKeyURL, publicKeyURL] where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    nonisolated private func updateSSHConfigReferences(from key: SSHKeyItem, targetURLs: [URL]) throws {
        let configURL = URL(fileURLWithPath: key.filePath).deletingLastPathComponent().appendingPathComponent("config")
        guard fileManager.fileExists(atPath: configURL.path) else {
            return
        }

        let originalContents = try String(contentsOf: configURL, encoding: .utf8)
        var replacements: [String: String] = [:]

        for (oldPath, newURL) in zip(key.pathsToRename, targetURLs) {
            let oldURL = URL(fileURLWithPath: oldPath)
            replacements[oldURL.path] = newURL.path
            replacements[tildePath(for: oldURL)] = tildePath(for: newURL)
        }

        let updatedContents = updatedSSHConfigContents(originalContents, replacements: replacements)
        if updatedContents != originalContents {
            try updatedContents.write(to: configURL, atomically: true, encoding: .utf8)
        }
    }

    nonisolated private func updatedSSHConfigContents(_ contents: String, replacements: [String: String]) -> String {
        contents
            .components(separatedBy: "\n")
            .map { updatedSSHConfigLine($0, replacements: replacements) }
            .joined(separator: "\n")
    }

    nonisolated private func updatedSSHConfigLine(_ line: String, replacements: [String: String]) -> String {
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

    nonisolated private func sshConfigValue(in valueAndSuffix: Substring) -> SSHConfigValue? {
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

    nonisolated private func tildePath(for url: URL) -> String {
        let homePath = fileManager.homeDirectoryForCurrentUser.path
        guard url.path == homePath || url.path.hasPrefix("\(homePath)/") else {
            return url.path
        }

        return "~\(url.path.dropFirst(homePath.count))"
    }

    nonisolated private func isRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }

        return true
    }

    nonisolated private func completePairItem(privateKeyURL: URL, publicKeyURL: URL) -> SSHKeyItem? {
        guard let privateKey = readPrivateKeyMetadata(at: privateKeyURL) else {
            return nil
        }

        guard let publicKey = readPublicKey(at: publicKeyURL) else {
            return nil
        }

        return SSHKeyItem(
            id: privateKeyURL.path,
            name: privateKeyURL.lastPathComponent,
            publicKeyPath: publicKeyURL.path,
            privateKeyPath: privateKeyURL.path,
            filePath: privateKeyURL.path,
            kind: .completePair,
            type: displayName(for: publicKey.type),
            fingerprint: publicKey.fingerprint,
            comment: publicKey.comment,
            createdAt: creationDate(for: privateKeyURL),
            isPassphraseProtected: privateKey.isPassphraseProtected
        )
    }

    nonisolated private func standaloneKeyItem(for fileURL: URL) -> SSHKeyItem? {
        if fileURL.pathExtension == "pub", let publicKey = readPublicKey(at: fileURL) {
            return SSHKeyItem(
                id: fileURL.path,
                name: fileURL.lastPathComponent,
                publicKeyPath: fileURL.path,
                privateKeyPath: nil,
                filePath: fileURL.path,
                kind: .publicKey,
                type: displayName(for: publicKey.type),
                fingerprint: publicKey.fingerprint,
                comment: publicKey.comment,
                createdAt: creationDate(for: fileURL),
                isPassphraseProtected: false
            )
        }

        guard let privateKey = readPrivateKeyMetadata(at: fileURL) else {
            return nil
        }

        return SSHKeyItem(
            id: fileURL.path,
            name: fileURL.lastPathComponent,
            publicKeyPath: nil,
            privateKeyPath: fileURL.path,
            filePath: fileURL.path,
            kind: .privateKey,
            type: privateKey.type,
            fingerprint: "Unavailable",
            comment: "No public key",
            createdAt: creationDate(for: fileURL),
            isPassphraseProtected: privateKey.isPassphraseProtected
        )
    }

    nonisolated private func readPublicKey(at url: URL) -> PublicKey? {
        guard
            let contents = try? String(contentsOf: url, encoding: .utf8),
            let line = contents.split(whereSeparator: \.isNewline).first
        else {
            return nil
        }

        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, isSupportedPublicKeyType(String(parts[0])) else {
            return nil
        }

        guard let keyData = Data(base64Encoded: String(parts[1])) else {
            return nil
        }

        let comment = parts.dropFirst(2).joined(separator: " ")
        return PublicKey(
            type: String(parts[0]),
            comment: comment.isEmpty ? "No comment" : comment,
            fingerprint: fingerprint(forPublicKeyData: keyData)
        )
    }

    nonisolated private func readPrivateKeyMetadata(at url: URL) -> PrivateKeyMetadata? {
        guard
            let contents = try? String(contentsOf: url, encoding: .utf8),
            !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let type: String
        if contents.contains("-----BEGIN OPENSSH PRIVATE KEY-----") {
            type = "OpenSSH Private Key"
        } else if contents.contains("-----BEGIN RSA PRIVATE KEY-----") {
            type = "RSA Private Key"
        } else if contents.contains("-----BEGIN EC PRIVATE KEY-----") {
            type = "EC Private Key"
        } else if contents.contains("-----BEGIN DSA PRIVATE KEY-----") {
            type = "DSA Private Key"
        } else if contents.contains("-----BEGIN PRIVATE KEY-----") {
            type = "Private Key"
        } else {
            return nil
        }

        return PrivateKeyMetadata(
            type: type,
            isPassphraseProtected: isPassphraseProtectedPrivateKey(contents: contents)
        )
    }

    nonisolated private func isPassphraseProtectedPrivateKey(contents: String) -> Bool {
        if contents.contains("-----BEGIN ENCRYPTED PRIVATE KEY-----")
            || contents.contains("Proc-Type: 4,ENCRYPTED")
            || contents.contains("DEK-Info:") {
            return true
        }

        guard contents.contains("-----BEGIN OPENSSH PRIVATE KEY-----") else {
            return false
        }

        return openSSHPrivateKeyCipherName(in: contents).map { $0 != "none" } ?? false
    }

    nonisolated private func openSSHPrivateKeyCipherName(in contents: String) -> String? {
        let base64Body = contents
            .split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("-----") }
            .joined()

        guard let data = Data(base64Encoded: base64Body) else {
            return nil
        }

        let authMagic = Data("openssh-key-v1\0".utf8)
        guard data.starts(with: authMagic) else {
            return nil
        }

        var offset = authMagic.count
        return readOpenSSHString(from: data, offset: &offset).flatMap {
            String(data: $0, encoding: .utf8)
        }
    }

    nonisolated private func fingerprint(forPublicKeyData data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let base64Digest = Data(digest).base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return "SHA256:\(base64Digest)"
    }

    nonisolated private func readOpenSSHString(from data: Data, offset: inout Int) -> Data? {
        guard offset + 4 <= data.count else {
            return nil
        }

        let length = data[offset..<offset + 4].reduce(0) { partialResult, byte in
            (partialResult << 8) | Int(byte)
        }
        offset += 4

        guard offset + length <= data.count else {
            return nil
        }

        defer {
            offset += length
        }
        return data[offset..<offset + length]
    }

    nonisolated private func isSupportedPublicKeyType(_ type: String) -> Bool {
        type == "ssh-ed25519"
            || type == "ssh-rsa"
            || type.hasPrefix("ecdsa-")
            || type.hasPrefix("sk-")
    }

    nonisolated private func displayName(for type: String) -> String {
        switch type {
        case "ssh-ed25519":
            return "ED25519"
        case "ssh-rsa":
            return "RSA"
        case let value where value.hasPrefix("ecdsa-"):
            return "ECDSA"
        case let value where value.hasPrefix("sk-ssh-ed25519"):
            return "Security Key ED25519"
        case let value where value.hasPrefix("sk-ecdsa"):
            return "Security Key ECDSA"
        default:
            return type
        }
    }

    nonisolated private func creationDate(for privateKeyURL: URL) -> Date {
        do {
            let values = try privateKeyURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            return values.creationDate ?? values.contentModificationDate ?? .now
        } catch {
            return .now
        }
    }
}

private enum ProcessRunner {
    struct Result {
        let terminationStatus: Int32
        let standardOutput: String
        let standardError: String
    }

    nonisolated static func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval = 60
    ) throws -> Result {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputBuffer = LockedPipeBuffer()
        let errorBuffer = LockedPipeBuffer()
        let terminationSemaphore = DispatchSemaphore(value: 0)

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputBuffer.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorBuffer.append(handle.availableData)
        }

        defer {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            process.terminationHandler = nil
        }

        try process.run()

        if terminationSemaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if terminationSemaphore.wait(timeout: .now() + 2) == .timedOut {
                process.interrupt()
                if terminationSemaphore.wait(timeout: .now() + 2) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                    _ = terminationSemaphore.wait(timeout: .now() + 2)
                }
            }

            throw ProcessRunnerError.timedOut(executableURL.path, timeout)
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputBuffer.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        errorBuffer.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

        return Result(
            terminationStatus: process.terminationStatus,
            standardOutput: outputBuffer.stringValue,
            standardError: errorBuffer.stringValue
        )
    }

    nonisolated static func runWithPseudoTerminal(
        executableURL: URL,
        arguments: [String],
        responses: [String],
        timeout: TimeInterval = 60
    ) throws -> Result {
        var masterFileDescriptor: Int32 = -1
        var slaveFileDescriptor: Int32 = -1
        guard openpty(&masterFileDescriptor, &slaveFileDescriptor, nil, nil, nil) == 0 else {
            throw ProcessRunnerError.pseudoTerminalUnavailable(errno)
        }

        let outputBuffer = LockedPipeBuffer()
        let terminationSemaphore = DispatchSemaphore(value: 0)
        let process = Process()

        let masterHandle = FileHandle(fileDescriptor: masterFileDescriptor, closeOnDealloc: true)
        let inputHandle = FileHandle(fileDescriptor: slaveFileDescriptor, closeOnDealloc: true)
        let outputHandle = FileHandle(fileDescriptor: dup(slaveFileDescriptor), closeOnDealloc: true)
        let errorHandle = FileHandle(fileDescriptor: dup(slaveFileDescriptor), closeOnDealloc: true)

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = inputHandle
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }

        masterHandle.readabilityHandler = { handle in
            outputBuffer.append(handle.availableData)
        }

        defer {
            masterHandle.readabilityHandler = nil
            try? masterHandle.close()
            process.terminationHandler = nil
        }

        try process.run()
        try? inputHandle.close()
        try? outputHandle.close()
        try? errorHandle.close()
        try writePseudoTerminalResponses(responses, to: masterHandle)

        if terminationSemaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if terminationSemaphore.wait(timeout: .now() + 2) == .timedOut {
                process.interrupt()
                if terminationSemaphore.wait(timeout: .now() + 2) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                    _ = terminationSemaphore.wait(timeout: .now() + 2)
                }
            }

            throw ProcessRunnerError.timedOut(executableURL.path, timeout)
        }

        masterHandle.readabilityHandler = nil
        outputBuffer.append(masterHandle.readDataToEndOfFile())

        return Result(
            terminationStatus: process.terminationStatus,
            standardOutput: outputBuffer.stringValue,
            standardError: ""
        )
    }

    nonisolated private static func writePseudoTerminalResponses(
        _ responses: [String],
        to masterHandle: FileHandle
    ) throws {
        let responsePayload = responses.map { "\($0)\n" }.joined()
        guard !responsePayload.isEmpty else {
            return
        }

        try masterHandle.write(contentsOf: Data(responsePayload.utf8))
    }
}

private final class LockedPipeBuffer: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var data = Data()

    nonisolated init() {}

    nonisolated func append(_ chunk: Data) {
        guard !chunk.isEmpty else {
            return
        }

        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    nonisolated var stringValue: String {
        lock.lock()
        let snapshot = data
        lock.unlock()

        return (String(data: snapshot, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum ProcessRunnerError: LocalizedError {
    case timedOut(String, TimeInterval)
    case pseudoTerminalUnavailable(Int32)

    var errorDescription: String? {
        switch self {
        case .timedOut(let path, let timeout):
            return "\(path) did not finish within \(Int(timeout)) seconds."
        case .pseudoTerminalUnavailable(let code):
            let message = String(cString: strerror(code))
            return "Unable to allocate a pseudo-terminal: \(message)"
        }
    }
}

private extension SSHKeyItem {
    nonisolated var pathsToDelete: [String] {
        switch kind {
        case .completePair:
            return [privateKeyPath, publicKeyPath].compactMap(\.self)
        case .privateKey, .publicKey:
            return [filePath]
        }
    }

    nonisolated var pathsToRename: [String] {
        switch kind {
        case .completePair:
            return [privateKeyPath, publicKeyPath].compactMap(\.self)
        case .privateKey, .publicKey:
            return [filePath]
        }
    }
}

private struct PublicKey {
    let type: String
    let comment: String
    let fingerprint: String
}

private struct PrivateKeyMetadata {
    let type: String
    let isPassphraseProtected: Bool
}

private struct SSHConfigValue {
    let value: String
    let quote: Character?
    let suffix: String
}

enum SSHKeyStoreError: LocalizedError {
    case commentRequiresPublicKey
    case emptyKeyName
    case invalidPublicKey
    case invalidKeyName
    case keyFileMissing(String)
    case keyNameAlreadyExists(String)
    case keyGenerationFailed(String)
    case passphraseChangeRequiresPrivateKey
    case passphraseChangeFailed(String)
    case noKeyFilesToRename
    case sshDirectoryIsNotDirectory(String)
    case sshKeygenUnavailable(ExternalToolStatus)

    var errorDescription: String? {
        switch self {
        case .commentRequiresPublicKey:
            return "A public key is required to edit the comment."
        case .emptyKeyName:
            return "The key name cannot be empty."
        case .invalidPublicKey:
            return "The public key file is invalid or unreadable."
        case .invalidKeyName:
            return "Use a file name without path separators."
        case .keyFileMissing(let path):
            return "The key file does not exist: \(path)"
        case .keyNameAlreadyExists(let name):
            return "A key file named \(name) already exists."
        case .keyGenerationFailed(let message):
            if message.isEmpty {
                return "Unable to generate the SSH key."
            }

            return "Unable to generate the SSH key: \(message)"
        case .passphraseChangeRequiresPrivateKey:
            return "A private key is required to change the passphrase."
        case .passphraseChangeFailed(let message):
            if message.isEmpty {
                return "Unable to change the key passphrase."
            }

            return "Unable to change the key passphrase: \(message)"
        case .noKeyFilesToRename:
            return "There are no key files to rename."
        case .sshDirectoryIsNotDirectory(let path):
            return "The SSH directory path is not a directory: \(path)"
        case .sshKeygenUnavailable(let status):
            return status.warningMessage ?? "ssh-keygen is unavailable. Choose a valid binary in Settings."
        }
    }
}
