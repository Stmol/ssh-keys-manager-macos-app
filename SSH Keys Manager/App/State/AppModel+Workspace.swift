import Foundation

@MainActor
extension AppModel {
    func changeSSHDirectory(to selectedPath: String) async {
        await workspaceCoordinator.changeSSHDirectory(to: selectedPath)
    }

    func createEmptyConfigFile() async {
        await workspaceCoordinator.createEmptyConfigFile()
    }

    func setSSHKeygenPath(_ path: String) async {
        await workspaceCoordinator.setSSHKeygenPath(path)
    }

    func resetSSHKeygenPath() async {
        await workspaceCoordinator.resetSSHKeygenPath()
    }

    func refreshSSHKeygenStatus() {
        workspaceCoordinator.refreshSSHKeygenStatus()
    }
}

@MainActor
final class AppWorkspaceCoordinator {
    private unowned let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func changeSSHDirectory(to selectedPath: String) async {
        let normalizedPath = SSHWorkspacePath.normalizeDirectoryPath(selectedPath)
        guard normalizedPath != model.sshDirectoryPath else {
            return
        }

        beginDirectoryChange()
        defer {
            endDirectoryChange()
        }

        do {
            let validatedPath = try model.validateWorkspaceDirectory(at: normalizedPath)
            resetWorkspaceState(for: validatedPath)
            model.preferences.setSSHDirectoryPath(validatedPath)

            async let keysReload: Void = model.keysCoordinator.loadIfNeeded()
            async let configReload: Void = model.configCoordinator.loadIfNeeded()
            _ = await (keysReload, configReload)
        } catch {
            model.showNotification(error.localizedDescription, kind: .danger)
        }
    }

    func createEmptyConfigFile() async {
        let directoryPath = model.sshDirectoryPath

        await model.withConfigOperation {
            do {
                _ = try model.validateWorkspaceDirectory(at: directoryPath)
                try await model.configStorage.createEmptyConfig(inDirectory: directoryPath)
                guard directoryPath == model.sshDirectoryPath else {
                    return
                }

                try await model.reloadConfigEntries(from: directoryPath)
                guard directoryPath == model.sshDirectoryPath else {
                    return
                }

                model.selectedConfigEntryID = model.configEntries.first?.id
                model.showNotification("Created SSH config file", kind: .success)
            } catch {
                guard directoryPath == model.sshDirectoryPath else {
                    return
                }

                model.configEntries = []
                model.originalConfigEntries = []
                model.selectedConfigEntryID = nil
                model.isConfigFileMissing = true
                model.configErrorMessage = "Unable to create SSH config: \(error.localizedDescription)"
            }
        }
    }

    func setSSHKeygenPath(_ path: String) async {
        let normalizedPath = ExternalToolPath.normalizeExecutablePath(
            path,
            defaultPath: ExternalTool.sshKeygen.defaultPath
        )
        let status = model.externalToolValidator.status(for: .sshKeygen, path: normalizedPath)

        guard status.isAvailable else {
            model.showNotification("Wrong binary selected", kind: .danger)
            return
        }

        model.sshKeygenPath = normalizedPath
        model.preferences.setSSHKeygenPath(normalizedPath)
        model.sshKeygenStatus = status
        await model.keyStorage.updateSSHKeygenPath(normalizedPath)

        if model.sshKeygenStatus.isAvailable {
            model.showNotification("Updated ssh-keygen path", kind: .success)
        } else if let warningMessage = model.sshKeygenStatus.warningMessage {
            model.showNotification(warningMessage, kind: .warning)
        }
    }

    func resetSSHKeygenPath() async {
        await setSSHKeygenPath(ExternalTool.sshKeygen.defaultPath)
    }

    func refreshSSHKeygenStatus() {
        model.sshKeygenStatus = model.externalToolValidator.status(for: .sshKeygen, path: model.sshKeygenPath)
    }

    private func resetWorkspaceState(for directoryPath: String) {
        model.sshDirectoryPath = directoryPath
        model.keys = []
        model.otherKeys = []
        model.configEntries = []
        model.originalConfigEntries = []
        model.selectedKeyID = nil
        model.selectedConfigEntryID = nil
        model.loadedKeysDirectoryPath = nil
        model.loadedConfigDirectoryPath = nil
        model.keyErrorMessage = nil
        model.configErrorMessage = nil
        model.isConfigFileMissing = false
    }

    private func beginDirectoryChange() {
        model.activeDirectoryChangeCount += 1
        model.isChangingSSHDirectory = true
    }

    private func endDirectoryChange() {
        model.activeDirectoryChangeCount = max(model.activeDirectoryChangeCount - 1, 0)
        model.isChangingSSHDirectory = model.activeDirectoryChangeCount > 0
    }
}
