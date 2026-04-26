import Foundation

@MainActor
extension AppModel {
    func loadConfig() {
        configCoordinator.load()
    }

    func loadConfigIfNeeded() async {
        await configCoordinator.loadIfNeeded()
    }

    func revealConfigInFinder() {
        configCoordinator.revealConfigInFinder()
    }

    func addConfigHost(_ request: SSHConfigHostSaveRequest) async throws {
        try await configCoordinator.addHost(request)
    }

    func updateConfigHost(_ entry: SSHConfigEntry, with request: SSHConfigHostSaveRequest) async throws {
        try await configCoordinator.updateHost(entry, with: request)
    }

    func deleteSelectedConfigEntry() async throws {
        try await configCoordinator.deleteSelectedEntry()
    }
}

@MainActor
final class SSHConfigCoordinator {
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
        guard model.loadedConfigDirectoryPath != model.sshDirectoryPath else {
            return
        }

        await loadAsync()
    }

    func revealConfigInFinder() {
        guard model.canRevealSSHDirectoryInFinder else {
            return
        }

        model.keyActions.openDirectory(atPath: model.sshDirectoryPath)
    }

    func addHost(_ request: SSHConfigHostSaveRequest) async throws {
        guard !model.isReadOnlyModeEnabled else {
            model.rejectReadOnlyModeMutation()
            throw ReadOnlyModeRestrictionError.unavailable
        }

        let directoryPath = model.sshDirectoryPath

        try await model.withConfigOperation {
            do {
                try await model.configStorage.apply(
                    .add(request),
                    inDirectory: directoryPath,
                    propertyIndentation: model.hostPropertyIndentation,
                    backupLimit: model.configBackupLimit
                )
                guard directoryPath == model.sshDirectoryPath else {
                    return
                }

                try await model.reloadConfigEntries(from: directoryPath)
                guard directoryPath == model.sshDirectoryPath else {
                    return
                }

                let addedHost = request.trimmedHost
                if let addedEntry = model.originalConfigEntries.last(where: { $0.host == addedHost }) {
                    model.selectedConfigEntryID = addedEntry.id
                } else {
                    model.selectedConfigEntryID = model.configEntries.last?.id
                }

                model.showNotification("Added SSH config host \(addedHost)", kind: .success)
            } catch {
                model.configErrorMessage = "Unable to add SSH config host: \(error.localizedDescription)"
                throw error
            }
        }
    }

    func updateHost(_ entry: SSHConfigEntry, with request: SSHConfigHostSaveRequest) async throws {
        guard !model.isReadOnlyModeEnabled else {
            model.rejectReadOnlyModeMutation()
            throw ReadOnlyModeRestrictionError.unavailable
        }

        let directoryPath = model.sshDirectoryPath

        try await model.withConfigOperation {
            do {
                try await model.configStorage.apply(
                    .update(entry: entry, request: request),
                    inDirectory: directoryPath,
                    propertyIndentation: model.hostPropertyIndentation,
                    backupLimit: model.configBackupLimit
                )
                guard directoryPath == model.sshDirectoryPath else {
                    return
                }

                try await model.reloadConfigEntries(from: directoryPath)
                guard directoryPath == model.sshDirectoryPath else {
                    return
                }

                let updatedHost = request.trimmedHost
                if let updatedEntry = model.originalConfigEntries.first(where: { $0.host == updatedHost }) {
                    model.selectedConfigEntryID = updatedEntry.id
                } else {
                    model.selectedConfigEntryID = model.configEntries.first?.id
                }

                model.showNotification("Updated SSH config host \(updatedHost)", kind: .success)
            } catch {
                model.configErrorMessage = "Unable to update SSH config host: \(error.localizedDescription)"
                throw error
            }
        }
    }

    func deleteSelectedEntry() async throws {
        guard let selectedConfigEntry = model.selectedConfigEntry else {
            return
        }

        guard !model.isReadOnlyModeEnabled else {
            model.rejectReadOnlyModeMutation()
            throw ReadOnlyModeRestrictionError.unavailable
        }

        let directoryPath = model.sshDirectoryPath
        let previousIndex = model.configEntries.firstIndex { $0.id == selectedConfigEntry.id } ?? 0

        try await model.withConfigOperation {
            do {
                try await model.configStorage.apply(
                    .delete(entry: selectedConfigEntry),
                    inDirectory: directoryPath,
                    propertyIndentation: model.hostPropertyIndentation,
                    backupLimit: model.configBackupLimit
                )
                guard directoryPath == model.sshDirectoryPath else {
                    return
                }

                try await model.reloadConfigEntries(from: directoryPath)
                guard directoryPath == model.sshDirectoryPath else {
                    return
                }

                selectConfigEntryAfterDeletion(previousIndex: previousIndex)
                model.showNotification("Deleted SSH config host \(selectedConfigEntry.host)", kind: .success)
            } catch {
                model.configErrorMessage = "Unable to delete SSH config host \(selectedConfigEntry.host): \(error.localizedDescription)"
                throw error
            }
        }
    }

    private func loadAsync() async {
        let previousSelection = model.selectedConfigEntryID
        let directoryPath = model.sshDirectoryPath
        var didLoadConfig = false

        await model.withConfigOperation {
            do {
                let validatedPath = try model.validateWorkspaceDirectory(at: directoryPath)
                guard validatedPath == model.sshDirectoryPath else {
                    return
                }

                try await model.reloadConfigEntries(from: directoryPath)

                if let previousSelection, model.configEntries.contains(where: { $0.id == previousSelection }) {
                    model.selectedConfigEntryID = previousSelection
                } else {
                    model.selectedConfigEntryID = model.configEntries.first?.id
                }

                didLoadConfig = true
            } catch SSHConfigLoadError.fileMissing {
                guard directoryPath == model.sshDirectoryPath else {
                    return
                }

                model.configEntries = []
                model.originalConfigEntries = []
                model.selectedConfigEntryID = nil
                model.isConfigFileMissing = true
            } catch {
                guard directoryPath == model.sshDirectoryPath else {
                    return
                }

                model.configEntries = []
                model.originalConfigEntries = []
                model.selectedConfigEntryID = nil
                model.configErrorMessage = "Unable to load SSH config: \(error.localizedDescription)"
            }

            if didLoadConfig, directoryPath == model.sshDirectoryPath {
                model.loadedConfigDirectoryPath = directoryPath
            }
        }
    }

    private func selectConfigEntryAfterDeletion(previousIndex: Int) {
        guard !model.configEntries.isEmpty else {
            model.selectedConfigEntryID = nil
            return
        }

        let nextIndex = min(previousIndex, model.configEntries.count - 1)
        model.selectedConfigEntryID = model.configEntries[nextIndex].id
    }
}
