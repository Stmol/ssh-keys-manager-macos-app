import Foundation

@MainActor
extension AppModel {
    var clipboardClearSeconds: Int {
        get {
            preferences.clipboardClearSeconds
        }
        set {
            preferences.setClipboardClearSeconds(newValue)
        }
    }

    var confirmPrivateKeyCopy: Bool {
        get {
            preferences.confirmPrivateKeyCopy
        }
        set {
            preferences.setConfirmPrivateKeyCopy(newValue)
        }
    }

    func loadKeys() {
        Task {
            await loadKeysAsync()
        }
    }

    func loadKeysIfNeeded() async {
        guard loadedKeysDirectoryPath != sshDirectoryPath else {
            return
        }

        await loadKeysAsync()
    }

    func revealSSHDirectoryInFinder() {
        guard canRevealSSHDirectoryInFinder else {
            return
        }

        keyActions.openDirectory(atPath: sshDirectoryPath)
    }

    func revealSelectedKeyInFinder() {
        guard let selectedKey else {
            return
        }

        keyActions.reveal(selectedKey)
    }

    func copySelectedPublicKey() async {
        guard let selectedKey else {
            return
        }

        await copyPublicKey(for: selectedKey)
    }

    func copySelectedPrivateKey() async {
        guard let selectedKey else {
            return
        }

        await copyPrivateKey(for: selectedKey)
    }

    func copyPublicKey(for key: SSHKeyItem) async {
        do {
            let contents = try await keyStorage.publicKeyContents(for: key)
            keyActions.copyToPasteboard(contents)
            showNotification("Public key was copied to the clipboard", kind: .success)
        } catch {
            keyErrorMessage = "Unable to copy public key for \(key.name): \(error.localizedDescription)"
        }
    }

    func copyPrivateKey(for key: SSHKeyItem) async {
        guard shouldCopyPrivateKey(named: key.name) else {
            return
        }

        do {
            let contents = try await keyStorage.privateKeyContents(for: key)
            let clearSeconds = clipboardClearSeconds
            keyActions.copySensitiveToPasteboard(
                contents,
                clearAfter: TimeInterval(clearSeconds)
            )
            showNotification(privateKeyCopyNotification(clearSeconds: clearSeconds), kind: .success)
        } catch {
            keyErrorMessage = "Unable to copy private key for \(key.name): \(error.localizedDescription)"
        }
    }

    func copySelectedFingerprint() {
        guard let selectedKey else {
            return
        }

        keyActions.copyFingerprint(selectedKey)
        showNotification("Fingerprint was copied to the clipboard", kind: .success)
    }

    func deleteSelectedKey() async throws {
        guard let selectedKey else {
            return
        }

        let previousIndex = displayedKeys.firstIndex { $0.id == selectedKey.id } ?? 0
        let runner = WorkspaceMutationRunner(model: self)

        try await runner.runKeyMutation { directoryPath in
            do {
                try await keyStorage.delete(selectedKey)
                guard runner.isCurrentWorkspace(directoryPath) else {
                    return
                }

                showNotification("Deleted \(selectedKey.name)", kind: .success)
                try await reloadKeyInventory(from: directoryPath)
                guard runner.isCurrentWorkspace(directoryPath) else {
                    return
                }

                runner.selectNextVisibleKey(afterDeletingAt: previousIndex)
            } catch {
                keyErrorMessage = "Unable to delete \(selectedKey.name): \(error.localizedDescription)"
                throw error
            }
        }
    }

    func updateSelectedKeyComment(_ comment: String) async throws {
        guard let selectedKey else {
            return
        }

        let runner = WorkspaceMutationRunner(model: self)

        try await runner.runKeyMutation { directoryPath in
            do {
                try await keyStorage.updateComment(for: selectedKey, comment: comment)
                try await reloadKeyInventoryPreservingSelection(
                    selectedKey.id,
                    directoryPath: directoryPath,
                    failurePrefix: "Updated comment, but could not refresh SSH keys"
                )
            } catch {
                keyErrorMessage = "Unable to update comment for \(selectedKey.name): \(error.localizedDescription)"
                throw error
            }
        }
    }

    func changeSelectedKeyPassphrase(oldPassphrase: String, newPassphrase: String) async throws {
        guard let selectedKey else {
            return
        }

        let isChangingExistingPassphrase = selectedKey.isPassphraseProtected
        let actionVerb = isChangingExistingPassphrase ? "change" : "add"
        let successVerb = isChangingExistingPassphrase ? "Changed" : "Added"
        let runner = WorkspaceMutationRunner(model: self)

        try await runner.runKeyMutation { directoryPath in
            do {
                try await keyStorage.changePassphrase(
                    for: selectedKey,
                    oldPassphrase: oldPassphrase,
                    newPassphrase: newPassphrase
                )
                guard runner.isCurrentWorkspace(directoryPath) else {
                    return
                }
            } catch {
                showNotification("Unable to \(actionVerb) passphrase for \(selectedKey.name)", kind: .danger)
                throw error
            }

            do {
                try await reloadKeyInventory(from: directoryPath)
                guard runner.isCurrentWorkspace(directoryPath) else {
                    return
                }

                runner.restoreSelectedKey(selectedKey.id)
                showNotification("\(successVerb) passphrase for \(selectedKey.name)", kind: .success)
            } catch {
                keyErrorMessage = "\(successVerb) passphrase, but could not refresh SSH keys: \(error.localizedDescription)"
                throw error
            }
        }
    }

    func renameSelectedKey(to newName: String) async throws {
        guard let selectedKey else {
            return
        }

        let runner = WorkspaceMutationRunner(model: self)

        try await runner.runKeyMutation { directoryPath in
            let renameResult: SSHKeyRenameResult

            do {
                renameResult = try await keyStorage.rename(selectedKey, to: newName)
            } catch {
                keyErrorMessage = "Unable to rename \(selectedKey.name): \(error.localizedDescription)"
                throw error
            }

            do {
                try await configStorage.renameIdentityFileReferences(
                    renameResult.pathReplacements,
                    inDirectory: directoryPath,
                    propertyIndentation: hostPropertyIndentation,
                    backupLimit: configBackupLimit
                )
            } catch let renameConfigError {
                do {
                    try await rollbackRenamedKey(selectedKey, renameResult: renameResult)
                } catch let rollbackFailure {
                    let rollbackError = KeyRenameRecoveryError(
                        renameError: renameConfigError,
                        rollbackError: rollbackFailure
                    )
                    keyErrorMessage = "Unable to rename \(selectedKey.name): \(rollbackError.localizedDescription)"
                    throw rollbackError
                }

                keyErrorMessage = "Unable to rename \(selectedKey.name): \(renameConfigError.localizedDescription)"
                throw renameConfigError
            }

            try await reloadKeyInventoryPreservingSelection(
                renameResult.keyID,
                directoryPath: directoryPath,
                failurePrefix: "Renamed key, but could not refresh SSH keys"
            )
        }
    }

    func duplicateSelectedKey(to newName: String) async throws {
        guard let selectedKey else {
            return
        }

        try await WorkspaceMutationRunner(model: self).runKeyMutation(requiresWriteAccess: false) { directoryPath in
            do {
                let duplicatedKeyID = try await keyStorage.duplicate(selectedKey, to: newName)
                try await reloadKeyInventoryPreservingSelection(
                    duplicatedKeyID,
                    directoryPath: directoryPath,
                    failurePrefix: "Duplicated key, but could not refresh SSH keys"
                )
            } catch {
                keyErrorMessage = "Unable to duplicate \(selectedKey.name): \(error.localizedDescription)"
                throw error
            }
        }
    }

    func availableKeyName(for baseName: String) async -> String? {
        try? await keyStorage.availableKeyName(for: baseName, in: sshDirectoryPath)
    }

    func generateKey(_ request: SSHKeyGenerationRequest) async throws {
        let runner = WorkspaceMutationRunner(model: self)

        try await runner.runKeyMutation(requiresWriteAccess: false) { directoryPath in
            do {
                let generatedKeyID = try await keyStorage.generateKey(request, in: directoryPath)
                guard runner.isCurrentWorkspace(directoryPath) else {
                    return
                }

                try await reloadKeyInventory(from: directoryPath)
                guard runner.isCurrentWorkspace(directoryPath) else {
                    return
                }

                runner.restoreSelectedKey(generatedKeyID, listKind: .completePairs)
                showNotification("Generated \(request.fileName)", kind: .success)
            } catch {
                keyErrorMessage = error.localizedDescription
                throw error
            }
        }
    }
}

private extension AppModel {
    func loadKeysAsync() async {
        let previousSelection = selectedKeyID
        let directoryPath = sshDirectoryPath
        var didLoadKeys = false

        await withKeyOperation {
            do {
                let validatedPath = try validateWorkspaceDirectory(at: directoryPath)
                guard validatedPath == sshDirectoryPath else {
                    return
                }

                try await reloadKeyInventory(from: directoryPath)

                if let previousSelection, displayedKeys.contains(where: { $0.id == previousSelection }) {
                    selectedKeyID = previousSelection
                } else {
                    selectedKeyID = displayedKeys.first?.id
                }

                didLoadKeys = true
            } catch {
                guard directoryPath == sshDirectoryPath else {
                    return
                }

                keys = []
                otherKeys = []
                selectedKeyID = nil
                keyErrorMessage = "Unable to load SSH keys: \(error.localizedDescription)"
            }

            if didLoadKeys, directoryPath == sshDirectoryPath {
                loadedKeysDirectoryPath = directoryPath
            }
        }
    }

    func shouldCopyPrivateKey(named keyName: String) -> Bool {
        guard confirmPrivateKeyCopy, !isPrivateKeyCopyConfirmationSuppressed else {
            return true
        }

        let confirmer = privateKeyCopyConfirmer()
        guard confirmer.confirmCopy(keyName: keyName) else {
            return false
        }

        if confirmer.suppressConfirmationUntilAppRestarts {
            isPrivateKeyCopyConfirmationSuppressed = true
        }

        return true
    }

    func privateKeyCopyConfirmer() -> any PrivateKeyCopyConfirming {
        if let provider = preferences as? PrivateKeyCopyConfirmationProviding {
            return provider.privateKeyCopyConfirmer
        }

        return NSAlertPrivateKeyCopyConfirmer()
    }

    func privateKeyCopyNotification(clearSeconds: Int) -> String {
        guard clearSeconds > 0 else {
            return "Private key was copied to the clipboard"
        }

        return "Private key copied - clearing in \(clearSeconds)s"
    }

    func rollbackRenamedKey(_ originalKey: SSHKeyItem, renameResult: SSHKeyRenameResult) async throws {
        guard !renameResult.pathReplacements.isEmpty else {
            return
        }

        let renamedKey = originalKey.applyingRenameResult(renameResult)
        _ = try await keyStorage.rename(renamedKey, to: originalKey.name)
    }
}

private extension SSHKeyItem {
    func applyingRenameResult(_ renameResult: SSHKeyRenameResult) -> SSHKeyItem {
        SSHKeyItem(
            id: renameResult.keyID,
            name: URL(fileURLWithPath: renameResult.keyID).lastPathComponent,
            publicKeyPath: publicKeyPath.map { renameResult.pathReplacements[$0] ?? $0 },
            privateKeyPath: privateKeyPath.map { renameResult.pathReplacements[$0] ?? $0 },
            filePath: renameResult.pathReplacements[filePath] ?? renameResult.keyID,
            kind: kind,
            type: type,
            fingerprint: fingerprint,
            comment: comment,
            createdAt: createdAt,
            isPassphraseProtected: isPassphraseProtected
        )
    }
}

private struct KeyRenameRecoveryError: LocalizedError {
    let renameError: Error
    let rollbackError: Error

    var errorDescription: String? {
        "Failed to update SSH config after renaming the key, and rollback failed: \(renameError.localizedDescription). Rollback error: \(rollbackError.localizedDescription)"
    }
}
