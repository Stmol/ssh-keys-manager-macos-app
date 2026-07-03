import Foundation

extension AppModel {
    func reloadKeyInventory(from directoryPath: String? = nil) async throws {
        let path = directoryPath ?? sshDirectoryPath
        let inventory = try await keyStorage.loadKeys(from: path)
        guard path == sshDirectoryPath else {
            return
        }

        keys = sortedKeys(inventory.completePairs)
        otherKeys = sortedKeys(inventory.otherKeys)
    }

    func reloadKeyInventoryPreservingSelection(
        _ selectedKeyID: SSHKeyItem.ID,
        directoryPath: String,
        failurePrefix: String
    ) async throws {
        do {
            try await reloadKeyInventory(from: directoryPath)
            guard directoryPath == sshDirectoryPath else {
                return
            }

            if displayedKeys.contains(where: { $0.id == selectedKeyID }) {
                self.selectedKeyID = selectedKeyID
            } else {
                self.selectedKeyID = displayedKeys.first?.id
            }
        } catch {
            guard directoryPath == sshDirectoryPath else {
                return
            }

            keys = []
            otherKeys = []
            self.selectedKeyID = nil
            keyErrorMessage = "\(failurePrefix): \(error.localizedDescription)"
            throw error
        }
    }

    func reloadConfigEntries(from directoryPath: String) async throws {
        let entries = try await configStorage.loadEntries(from: directoryPath)
        guard directoryPath == sshDirectoryPath else {
            return
        }

        originalConfigEntries = entries
        configEntries = sortedConfigEntries(entries)
    }

    func validateWorkspaceDirectory(at directoryPath: String) throws -> String {
        try workspaceValidator.validate(directoryPath: directoryPath)
    }

    func showNotification(_ message: String, kind: AppNotificationKind) {
        notification = AppNotification(message: message, kind: kind)
    }

    func rejectReadOnlyModeMutation() {
        showNotification(ReadOnlyModeRestrictionError.unavailable.notificationMessage, kind: .warning)
    }

    func sortedKeys(_ keys: [SSHKeyItem]) -> [SSHKeyItem] {
        keys.sortedBy(keySortOrder)
    }

    func sortedConfigEntries(_ entries: [SSHConfigEntry]) -> [SSHConfigEntry] {
        entries.sortedBy(configSortOrder)
    }

    func withKeyOperation<T>(
        resetError: Bool = true,
        _ operation: () async throws -> T
    ) async rethrows -> T {
        beginKeyOperation()
        if resetError {
            keyErrorMessage = nil
        }
        defer {
            endKeyOperation()
        }

        return try await operation()
    }

    func withConfigOperation<T>(
        resetError: Bool = true,
        resetMissingFlag: Bool = true,
        _ operation: () async throws -> T
    ) async rethrows -> T {
        beginConfigOperation()
        if resetError {
            configErrorMessage = nil
        }
        if resetMissingFlag {
            isConfigFileMissing = false
        }
        defer {
            endConfigOperation()
        }

        return try await operation()
    }
}

private extension AppModel {
    func beginKeyOperation() {
        activeKeyOperationCount += 1
        isLoadingKeys = true
    }

    func endKeyOperation() {
        activeKeyOperationCount = max(activeKeyOperationCount - 1, 0)
        isLoadingKeys = activeKeyOperationCount > 0
    }

    func beginConfigOperation() {
        activeConfigOperationCount += 1
        isLoadingConfig = true
    }

    func endConfigOperation() {
        activeConfigOperationCount = max(activeConfigOperationCount - 1, 0)
        isLoadingConfig = activeConfigOperationCount > 0
    }
}
