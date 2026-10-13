import Foundation

@MainActor
extension AppModel {
    func changeSSHDirectory(to selectedPath: String) async {
        let normalizedPath = SSHWorkspacePath.normalizeDirectoryPath(selectedPath)
        guard normalizedPath != sshDirectoryPath else {
            return
        }

        beginDirectoryChange()
        defer {
            endDirectoryChange()
        }

        do {
            let validatedPath = try validateWorkspaceDirectory(at: normalizedPath)
            resetWorkspaceState(for: validatedPath)
            preferences.setSSHDirectoryPath(validatedPath)

            async let keysReload: Void = loadKeysIfNeeded()
            async let configReload: Void = loadConfigIfNeeded()
            async let subfoldersReload: Void = refreshAvailableSubfolders()
            _ = await (keysReload, configReload, subfoldersReload)
        } catch {
            showNotification(error.localizedDescription, kind: .danger)
        }
    }

    func refreshAvailableSubfolders() async {
        let directoryPath = sshDirectoryPath

        do {
            let subfolders = try await keyStorage.subfolderNames(in: directoryPath)
            guard directoryPath == sshDirectoryPath else {
                return
            }

            availableSubfolders = subfolders
        } catch {
            guard directoryPath == sshDirectoryPath else {
                return
            }

            availableSubfolders = []
        }
    }

    func setSubfolder(_ folder: String, included: Bool) {
        if included {
            guard !selectedSubfolders.contains(folder) else {
                return
            }

            selectedSubfolders.append(folder)
        } else {
            selectedSubfolders.removeAll { $0 == folder }
        }
    }

    func createEmptyConfigFile() async {
        let runner = WorkspaceMutationRunner(model: self)

        do {
            try await runner.runConfigMutation { directoryPath in
                do {
                    _ = try validateWorkspaceDirectory(at: directoryPath)
                    try await configStorage.createEmptyConfig(inDirectory: directoryPath)
                    guard runner.isCurrentWorkspace(directoryPath) else {
                        return
                    }

                    try await reloadConfigEntries(from: directoryPath)
                    guard runner.isCurrentWorkspace(directoryPath) else {
                        return
                    }

                    selectedConfigEntryID = configEntries.first?.id
                    showNotification("Created SSH config file", kind: .success)
                } catch {
                    guard runner.isCurrentWorkspace(directoryPath) else {
                        return
                    }

                    configEntries = []
                    originalConfigEntries = []
                    selectedConfigEntryID = nil
                    isConfigFileMissing = true
                    configErrorMessage = "Unable to create SSH config: \(error.localizedDescription)"
                }
            }
        } catch {
            return
        }
    }

    func setSSHKeygenPath(_ path: String) async {
        let normalizedPath = ExternalToolPath.normalizeExecutablePath(
            path,
            defaultPath: ExternalTool.sshKeygen.defaultPath
        )
        let status = externalToolValidator.status(for: .sshKeygen, path: normalizedPath)

        guard status.isAvailable else {
            showNotification("Wrong binary selected", kind: .danger)
            return
        }

        sshKeygenPath = normalizedPath
        preferences.setSSHKeygenPath(normalizedPath)
        sshKeygenStatus = status
        await keyStorage.updateSSHKeygenPath(normalizedPath)

        if sshKeygenStatus.isAvailable {
            showNotification("Updated ssh-keygen path", kind: .success)
        } else if let warningMessage = sshKeygenStatus.warningMessage {
            showNotification(warningMessage, kind: .warning)
        }
    }

    func resetSSHKeygenPath() async {
        await setSSHKeygenPath(ExternalTool.sshKeygen.defaultPath)
    }

    func refreshSSHKeygenStatus() {
        sshKeygenStatus = externalToolValidator.status(for: .sshKeygen, path: sshKeygenPath)
    }
}

private extension AppModel {
    func resetWorkspaceState(for directoryPath: String) {
        invalidateConfigHostReachability()
        sshDirectoryPath = directoryPath
        keys = []
        otherKeys = []
        configEntries = []
        originalConfigEntries = []
        selectedKeyID = nil
        selectedConfigEntryID = nil
        loadedKeysDirectoryPath = nil
        loadedConfigDirectoryPath = nil
        keyErrorMessage = nil
        configErrorMessage = nil
        isConfigFileMissing = false
    }

    func beginDirectoryChange() {
        activeDirectoryChangeCount += 1
        isChangingSSHDirectory = true
    }

    func endDirectoryChange() {
        activeDirectoryChangeCount = max(activeDirectoryChangeCount - 1, 0)
        isChangingSSHDirectory = activeDirectoryChangeCount > 0
    }
}
