import Foundation

@MainActor
extension AppModel {
    func loadKeys() {
        keysCoordinator.load()
    }

    func loadKeysIfNeeded() async {
        await keysCoordinator.loadIfNeeded()
    }

    func revealSSHDirectoryInFinder() {
        keysCoordinator.revealSSHDirectoryInFinder()
    }

    func revealSelectedKeyInFinder() {
        keysCoordinator.revealSelectedKeyInFinder()
    }

    func copySelectedPublicKey() async {
        await keysCoordinator.copySelectedPublicKey()
    }

    func copySelectedPrivateKey() async {
        await keysCoordinator.copySelectedPrivateKey()
    }

    func copyPublicKey(for key: SSHKeyItem) async {
        await keysCoordinator.copyPublicKey(for: key)
    }

    func copyPrivateKey(for key: SSHKeyItem) async {
        await keysCoordinator.copyPrivateKey(for: key)
    }

    func copySelectedFingerprint() {
        keysCoordinator.copySelectedFingerprint()
    }

    func deleteSelectedKey() async throws {
        try await keysCoordinator.deleteSelectedKey()
    }

    func updateSelectedKeyComment(_ comment: String) async throws {
        try await keysCoordinator.updateSelectedKeyComment(comment)
    }

    func changeSelectedKeyPassphrase(oldPassphrase: String, newPassphrase: String) async throws {
        try await keysCoordinator.changeSelectedKeyPassphrase(
            oldPassphrase: oldPassphrase,
            newPassphrase: newPassphrase
        )
    }

    func renameSelectedKey(to newName: String) async throws {
        try await keysCoordinator.renameSelectedKey(to: newName)
    }

    func duplicateSelectedKey(to newName: String) async throws {
        try await keysCoordinator.duplicateSelectedKey(to: newName)
    }

    func availableKeyName(for baseName: String) async -> String? {
        await keysCoordinator.availableKeyName(for: baseName)
    }

    func generateKey(_ request: SSHKeyGenerationRequest) async throws {
        try await keysCoordinator.generateKey(request)
    }
}

@MainActor
final class SSHKeysCoordinator {
    private unowned let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func load() {
        Task {
            await loadAsync()
        }
    }

    func loadIfNeeded() async {
        guard model.loadedKeysDirectoryPath != model.sshDirectoryPath else {
            return
        }

        await loadAsync()
    }

    func revealSSHDirectoryInFinder() {
        guard model.canRevealSSHDirectoryInFinder else {
            return
        }

        model.keyActions.openDirectory(atPath: model.sshDirectoryPath)
    }

    func revealSelectedKeyInFinder() {
        guard let selectedKey = model.selectedKey else {
            return
        }

        model.keyActions.reveal(selectedKey)
    }

    func copySelectedPublicKey() async {
        guard let selectedKey = model.selectedKey else {
            return
        }

        await copyPublicKey(for: selectedKey)
    }

    func copySelectedPrivateKey() async {
        guard let selectedKey = model.selectedKey else {
            return
        }

        await copyPrivateKey(for: selectedKey)
    }

    func copyPublicKey(for key: SSHKeyItem) async {
        do {
            let contents = try await model.keyStorage.publicKeyContents(for: key)
            model.keyActions.copyToPasteboard(contents)
            model.showNotification("Public key was copied to the clipboard", kind: .success)
        } catch {
            model.keyErrorMessage = "Unable to copy public key for \(key.name): \(error.localizedDescription)"
        }
    }

    func copyPrivateKey(for key: SSHKeyItem) async {
        do {
            let contents = try await model.keyStorage.privateKeyContents(for: key)
            model.keyActions.copyToPasteboard(contents)
            model.showNotification("Private key was copied to the clipboard", kind: .success)
        } catch {
            model.keyErrorMessage = "Unable to copy private key for \(key.name): \(error.localizedDescription)"
        }
    }

    func copySelectedFingerprint() {
        guard let selectedKey = model.selectedKey else {
            return
        }

        model.keyActions.copyFingerprint(selectedKey)
        model.showNotification("Fingerprint was copied to the clipboard", kind: .success)
    }

    func deleteSelectedKey() async throws {
        guard let selectedKey = model.selectedKey else {
            return
        }

        guard !model.isReadOnlyModeEnabled else {
            model.rejectReadOnlyModeMutation()
            throw ReadOnlyModeRestrictionError.unavailable
        }

        let directoryPath = model.sshDirectoryPath
        let previousIndex = model.displayedKeys.firstIndex { $0.id == selectedKey.id } ?? 0

        try await model.withKeyOperation {
            do {
                try await model.keyStorage.delete(selectedKey)
                guard directoryPath == model.sshDirectoryPath else {
                    return
                }

                model.showNotification("Deleted \(selectedKey.name)", kind: .success)

                try await model.reloadKeyInventory(from: directoryPath)
                guard directoryPath == model.sshDirectoryPath else {
                    return
                }

                selectKeyAfterDeletion(previousIndex: previousIndex)
            } catch {
                model.keyErrorMessage = "Unable to delete \(selectedKey.name): \(error.localizedDescription)"
                throw error
            }
        }
    }

    func updateSelectedKeyComment(_ comment: String) async throws {
        guard let selectedKey = model.selectedKey else {
            return
        }

        guard !model.isReadOnlyModeEnabled else {
            model.rejectReadOnlyModeMutation()
            throw ReadOnlyModeRestrictionError.unavailable
        }

        let directoryPath = model.sshDirectoryPath

        try await model.withKeyOperation {
            do {
                try await model.keyStorage.updateComment(for: selectedKey, comment: comment)
                try await model.reloadKeyInventoryPreservingSelection(
                    selectedKey.id,
                    directoryPath: directoryPath,
                    failurePrefix: "Updated comment, but could not refresh SSH keys"
                )
            } catch {
                model.keyErrorMessage = "Unable to update comment for \(selectedKey.name): \(error.localizedDescription)"
                throw error
            }
        }
    }

    func changeSelectedKeyPassphrase(oldPassphrase: String, newPassphrase: String) async throws {
        guard let selectedKey = model.selectedKey else {
            return
        }

        guard !model.isReadOnlyModeEnabled else {
            model.rejectReadOnlyModeMutation()
            throw ReadOnlyModeRestrictionError.unavailable
        }

        let isChangingExistingPassphrase = selectedKey.isPassphraseProtected
        let actionVerb = isChangingExistingPassphrase ? "change" : "add"
        let successVerb = isChangingExistingPassphrase ? "Changed" : "Added"
        let directoryPath = model.sshDirectoryPath

        try await model.withKeyOperation {
            do {
                try await model.keyStorage.changePassphrase(
                    for: selectedKey,
                    oldPassphrase: oldPassphrase,
                    newPassphrase: newPassphrase
                )
                guard directoryPath == model.sshDirectoryPath else {
                    return
                }
            } catch {
                model.showNotification("Unable to \(actionVerb) passphrase for \(selectedKey.name)", kind: .danger)
                throw error
            }

            do {
                try await model.reloadKeyInventory(from: directoryPath)
                guard directoryPath == model.sshDirectoryPath else {
                    return
                }

                if model.displayedKeys.contains(where: { $0.id == selectedKey.id }) {
                    model.selectedKeyID = selectedKey.id
                }

                model.showNotification("\(successVerb) passphrase for \(selectedKey.name)", kind: .success)
            } catch {
                model.keyErrorMessage = "\(successVerb) passphrase, but could not refresh SSH keys: \(error.localizedDescription)"
                throw error
            }
        }
    }

    func renameSelectedKey(to newName: String) async throws {
        guard let selectedKey = model.selectedKey else {
            return
        }

        guard !model.isReadOnlyModeEnabled else {
            model.rejectReadOnlyModeMutation()
            throw ReadOnlyModeRestrictionError.unavailable
        }

        let directoryPath = model.sshDirectoryPath

        try await model.withKeyOperation {
            do {
                let renamedKeyID = try await model.keyStorage.rename(selectedKey, to: newName)
                try await model.reloadKeyInventoryPreservingSelection(
                    renamedKeyID,
                    directoryPath: directoryPath,
                    failurePrefix: "Renamed key, but could not refresh SSH keys"
                )
            } catch {
                model.keyErrorMessage = "Unable to rename \(selectedKey.name): \(error.localizedDescription)"
                throw error
            }
        }
    }

    func duplicateSelectedKey(to newName: String) async throws {
        guard let selectedKey = model.selectedKey else {
            return
        }

        let directoryPath = model.sshDirectoryPath

        try await model.withKeyOperation {
            do {
                let duplicatedKeyID = try await model.keyStorage.duplicate(selectedKey, to: newName)
                try await model.reloadKeyInventoryPreservingSelection(
                    duplicatedKeyID,
                    directoryPath: directoryPath,
                    failurePrefix: "Duplicated key, but could not refresh SSH keys"
                )
            } catch {
                model.keyErrorMessage = "Unable to duplicate \(selectedKey.name): \(error.localizedDescription)"
                throw error
            }
        }
    }

    func availableKeyName(for baseName: String) async -> String? {
        try? await model.keyStorage.availableKeyName(for: baseName, in: model.sshDirectoryPath)
    }

    func generateKey(_ request: SSHKeyGenerationRequest) async throws {
        let directoryPath = model.sshDirectoryPath

        try await model.withKeyOperation {
            do {
                let generatedKeyID = try await model.keyStorage.generateKey(request, in: directoryPath)
                guard directoryPath == model.sshDirectoryPath else {
                    return
                }

                try await model.reloadKeyInventory(from: directoryPath)
                guard directoryPath == model.sshDirectoryPath else {
                    return
                }

                model.selectedKeyList = .completePairs

                if model.displayedKeys.contains(where: { $0.id == generatedKeyID }) {
                    model.selectedKeyID = generatedKeyID
                } else {
                    model.selectedKeyID = model.displayedKeys.first?.id
                }

                model.showNotification("Generated \(request.fileName)", kind: .success)
            } catch {
                model.keyErrorMessage = error.localizedDescription
                throw error
            }
        }
    }

    private func loadAsync() async {
        let previousSelection = model.selectedKeyID
        let directoryPath = model.sshDirectoryPath
        var didLoadKeys = false

        await model.withKeyOperation {
            do {
                let validatedPath = try model.validateWorkspaceDirectory(at: directoryPath)
                guard validatedPath == model.sshDirectoryPath else {
                    return
                }

                try await model.reloadKeyInventory(from: directoryPath)

                if let previousSelection, model.displayedKeys.contains(where: { $0.id == previousSelection }) {
                    model.selectedKeyID = previousSelection
                } else {
                    model.selectedKeyID = model.displayedKeys.first?.id
                }

                didLoadKeys = true
            } catch {
                guard directoryPath == model.sshDirectoryPath else {
                    return
                }

                model.keys = []
                model.otherKeys = []
                model.selectedKeyID = nil
                model.keyErrorMessage = "Unable to load SSH keys: \(error.localizedDescription)"
            }

            if didLoadKeys, directoryPath == model.sshDirectoryPath {
                model.loadedKeysDirectoryPath = directoryPath
            }
        }
    }

    private func selectKeyAfterDeletion(previousIndex: Int) {
        let visibleKeys = model.displayedKeys

        if visibleKeys.isEmpty {
            model.selectedKeyID = nil
            return
        }

        let nextIndex = min(previousIndex, visibleKeys.count - 1)
        model.selectedKeyID = visibleKeys[nextIndex].id
    }
}
