import Foundation

@MainActor
extension AppModel {
    func loadConfig() {
        Task {
            await loadConfigAsync()
        }
    }

    func loadConfigIfNeeded() async {
        guard loadedConfigDirectoryPath != sshDirectoryPath else {
            return
        }

        await loadConfigAsync()
    }

    func revealConfigInFinder() {
        guard canRevealSSHDirectoryInFinder else {
            return
        }

        keyActions.openDirectory(atPath: sshDirectoryPath)
    }

    func addConfigHost(_ request: SSHConfigHostSaveRequest) async throws {
        let runner = WorkspaceMutationRunner(model: self)

        try await runner.runConfigMutation { directoryPath in
            do {
                try await configStorage.apply(
                    .add(request),
                    inDirectory: directoryPath,
                    propertyIndentation: hostPropertyIndentation,
                    backupLimit: configBackupLimit
                )
                guard runner.isCurrentWorkspace(directoryPath) else {
                    return
                }

                try await reloadConfigEntries(from: directoryPath)
                guard runner.isCurrentWorkspace(directoryPath) else {
                    return
                }

                runner.invalidateConfigHostReachability()
                runner.restoreSelectedConfigEntry(
                    host: request.trimmedHost,
                    preferLastHostMatch: true
                )
                showNotification("Added SSH config host \(request.trimmedHost)", kind: .success)
            } catch {
                configErrorMessage = "Unable to add SSH config host: \(error.localizedDescription)"
                throw error
            }
        }
    }

    func updateConfigHost(_ entry: SSHConfigEntry, with request: SSHConfigHostSaveRequest) async throws {
        let runner = WorkspaceMutationRunner(model: self)

        try await runner.runConfigMutation { directoryPath in
            do {
                try await configStorage.apply(
                    .update(entry: entry, request: request),
                    inDirectory: directoryPath,
                    propertyIndentation: hostPropertyIndentation,
                    backupLimit: configBackupLimit
                )
                guard runner.isCurrentWorkspace(directoryPath) else {
                    return
                }

                try await reloadConfigEntries(from: directoryPath)
                guard runner.isCurrentWorkspace(directoryPath) else {
                    return
                }

                runner.invalidateConfigHostReachability()
                runner.restoreSelectedConfigEntry(host: request.trimmedHost, fallbackID: entry.id)
                showNotification("Updated SSH config host \(request.trimmedHost)", kind: .success)
            } catch {
                configErrorMessage = "Unable to update SSH config host: \(error.localizedDescription)"
                throw error
            }
        }
    }

    func deleteSelectedConfigEntry() async throws {
        guard let selectedConfigEntry else {
            return
        }

        let previousIndex = configEntries.firstIndex { $0.id == selectedConfigEntry.id } ?? 0
        let runner = WorkspaceMutationRunner(model: self)

        try await runner.runConfigMutation { directoryPath in
            do {
                try await configStorage.apply(
                    .delete(entry: selectedConfigEntry),
                    inDirectory: directoryPath,
                    propertyIndentation: hostPropertyIndentation,
                    backupLimit: configBackupLimit
                )
                guard runner.isCurrentWorkspace(directoryPath) else {
                    return
                }

                try await reloadConfigEntries(from: directoryPath)
                guard runner.isCurrentWorkspace(directoryPath) else {
                    return
                }

                runner.invalidateConfigHostReachability()
                runner.selectNextConfigEntry(afterDeletingAt: previousIndex)
                showNotification("Deleted SSH config host \(selectedConfigEntry.host)", kind: .success)
            } catch {
                configErrorMessage = "Unable to delete SSH config host \(selectedConfigEntry.host): \(error.localizedDescription)"
                throw error
            }
        }
    }

    func checkConfigHostReachability() {
        let directoryPath = sshDirectoryPath
        let entries = configEntries
        let retainedModel = self
        let preparedEntries = entries.map { entry in
            (entry, SSHHostReachabilityResolver.resolveTarget(for: entry))
        }

        configHostReachabilityTask?.cancel()
        configHostCheckGeneration += 1
        let generation = configHostCheckGeneration

        var statuses: [SSHConfigEntry.ID: SSHConfigHostReachabilityStatus] = [:]
        var initialErrorCount = 0
        var readyEntries: [(SSHConfigEntry, SSHHostReachabilityTarget)] = []

        for (entry, resolution) in preparedEntries {
            switch resolution {
            case .unsupported:
                break
            case .invalidConfiguration:
                statuses[entry.id] = .error
                initialErrorCount += 1
            case .target(let target):
                statuses[entry.id] = .checking
                readyEntries.append((entry, target))
            }
        }

        configHostStatuses = statuses
        isCheckingConfigHosts = !readyEntries.isEmpty

        guard !readyEntries.isEmpty else {
            if initialErrorCount > 0 {
                showConfigReachabilityErrorSummary(count: initialErrorCount)
            }
            return
        }

        configHostReachabilityTask = Task {
            await runReachabilityChecks(
                model: retainedModel,
                entries: readyEntries,
                directoryPath: directoryPath,
                generation: generation,
                initialErrorCount: initialErrorCount
            )
        }
    }
}

private extension AppModel {
    func loadConfigAsync() async {
        let previousSelection = selectedConfigEntryID
        let directoryPath = sshDirectoryPath
        var didLoadConfig = false
        invalidateConfigHostReachability()

        await withConfigOperation {
            do {
                let validatedPath = try validateWorkspaceDirectory(at: directoryPath)
                guard validatedPath == sshDirectoryPath else {
                    return
                }

                try await reloadConfigEntries(from: directoryPath)

                if let previousSelection, configEntries.contains(where: { $0.id == previousSelection }) {
                    selectedConfigEntryID = previousSelection
                } else {
                    selectedConfigEntryID = configEntries.first?.id
                }

                didLoadConfig = true
            } catch SSHConfigLoadError.fileMissing {
                guard directoryPath == sshDirectoryPath else {
                    return
                }

                configEntries = []
                originalConfigEntries = []
                selectedConfigEntryID = nil
                isConfigFileMissing = true
            } catch {
                guard directoryPath == sshDirectoryPath else {
                    return
                }

                configEntries = []
                originalConfigEntries = []
                selectedConfigEntryID = nil
                configErrorMessage = "Unable to load SSH config: \(error.localizedDescription)"
            }

            if didLoadConfig, directoryPath == sshDirectoryPath {
                loadedConfigDirectoryPath = directoryPath
            }
        }

        guard didLoadConfig, directoryPath == sshDirectoryPath else {
            return
        }

        scheduleAutoConfigReachabilityCheckIfNeeded()
    }

    func scheduleAutoConfigReachabilityCheckIfNeeded() {
        guard !configEntries.isEmpty else {
            return
        }

        checkConfigHostReachability()
    }

    func runReachabilityChecks(
        model: AppModel,
        entries: [(SSHConfigEntry, SSHHostReachabilityTarget)],
        directoryPath: String,
        generation: Int,
        initialErrorCount: Int
    ) async {
        var errorCount = initialErrorCount
        let reachabilityTimeout: Duration = .seconds(3)
        let maximumConcurrentHostChecks = 8

        for batchStart in stride(from: 0, to: entries.count, by: maximumConcurrentHostChecks) {
            if Task.isCancelled {
                return
            }

            let batchEnd = min(batchStart + maximumConcurrentHostChecks, entries.count)
            let batch = Array(entries[batchStart..<batchEnd])

            let results = await withTaskGroup(
                of: (SSHConfigEntry.ID, SSHHostReachabilityCheckResult).self,
                returning: [(SSHConfigEntry.ID, SSHHostReachabilityCheckResult)].self
            ) { group in
                for (entry, target) in batch {
                    let checker = model.hostReachabilityChecker
                    group.addTask {
                        let result = await checker.check(
                            target: target,
                            timeout: reachabilityTimeout
                        )
                        return (entry.id, result)
                    }
                }

                var collected: [(SSHConfigEntry.ID, SSHHostReachabilityCheckResult)] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            await MainActor.run {
                guard isCurrentReachabilityRun(generation: generation, directoryPath: directoryPath) else {
                    return
                }

                for (entryID, result) in results {
                    switch result {
                    case .reachable:
                        configHostStatuses[entryID] = .reachable
                    case .unreachable:
                        configHostStatuses[entryID] = .unreachable
                    case .error:
                        configHostStatuses[entryID] = .error
                        errorCount += 1
                    }
                }
            }
        }

        await MainActor.run {
            guard isCurrentReachabilityRun(generation: generation, directoryPath: directoryPath) else {
                return
            }

            isCheckingConfigHosts = false
            configHostReachabilityTask = nil

            if errorCount > 0 {
                showConfigReachabilityErrorSummary(count: errorCount)
            }
        }
    }

    func isCurrentReachabilityRun(generation: Int, directoryPath: String) -> Bool {
        generation == configHostCheckGeneration && directoryPath == sshDirectoryPath
    }
}
