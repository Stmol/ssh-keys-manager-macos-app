import Foundation

@MainActor
struct WorkspaceMutationRunner {
    private unowned let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func runKeyMutation<T>(
        requiresWriteAccess: Bool = true,
        resetError: Bool = true,
        _ operation: (_ directoryPath: String) async throws -> T
    ) async throws -> T {
        try guardWriteAccessIfNeeded(requiresWriteAccess)
        let directoryPath = model.sshDirectoryPath
        return try await model.withKeyOperation(resetError: resetError) {
            try await operation(directoryPath)
        }
    }

    func runConfigMutation<T>(
        requiresWriteAccess: Bool = true,
        resetError: Bool = true,
        resetMissingFlag: Bool = true,
        _ operation: (_ directoryPath: String) async throws -> T
    ) async throws -> T {
        try guardWriteAccessIfNeeded(requiresWriteAccess)
        let directoryPath = model.sshDirectoryPath
        return try await model.withConfigOperation(
            resetError: resetError,
            resetMissingFlag: resetMissingFlag
        ) {
            try await operation(directoryPath)
        }
    }

    func isCurrentWorkspace(_ directoryPath: String) -> Bool {
        directoryPath == model.sshDirectoryPath
    }

    func restoreSelectedKey(_ selectedKeyID: SSHKeyItem.ID, listKind: SSHKeyListKind? = nil) {
        if let listKind {
            model.selectedKeyList = listKind
        }

        if model.displayedKeys.contains(where: { $0.id == selectedKeyID }) {
            model.selectedKeyID = selectedKeyID
        } else {
            model.selectedKeyID = model.displayedKeys.first?.id
        }
    }

    func selectNextVisibleKey(afterDeletingAt previousIndex: Int) {
        let visibleKeys = model.displayedKeys

        if visibleKeys.isEmpty {
            model.selectedKeyID = nil
            return
        }

        let nextIndex = min(previousIndex, visibleKeys.count - 1)
        model.selectedKeyID = visibleKeys[nextIndex].id
    }

    func restoreSelectedConfigEntry(
        host: String? = nil,
        fallbackID: SSHConfigEntry.ID? = nil,
        preferLastHostMatch: Bool = false
    ) {
        if let fallbackID,
           model.originalConfigEntries.contains(where: { $0.id == fallbackID }) {
            model.selectedConfigEntryID = fallbackID
            return
        }

        if let host {
            let matchedEntry = preferLastHostMatch
                ? model.originalConfigEntries.last(where: { $0.host == host })
                : model.originalConfigEntries.first(where: { $0.host == host })

            if let matchedEntry {
                model.selectedConfigEntryID = matchedEntry.id
                return
            }
        }

        model.selectedConfigEntryID = model.configEntries.first?.id
    }

    func selectNextConfigEntry(afterDeletingAt previousIndex: Int) {
        guard !model.configEntries.isEmpty else {
            model.selectedConfigEntryID = nil
            return
        }

        let nextIndex = min(previousIndex, model.configEntries.count - 1)
        model.selectedConfigEntryID = model.configEntries[nextIndex].id
    }

    func invalidateConfigHostReachability() {
        model.invalidateConfigHostReachability()
    }

    private func guardWriteAccessIfNeeded(_ requiresWriteAccess: Bool) throws {
        guard requiresWriteAccess, model.isReadOnlyModeEnabled else {
            return
        }

        model.rejectReadOnlyModeMutation()
        throw ReadOnlyModeRestrictionError.unavailable
    }
}
