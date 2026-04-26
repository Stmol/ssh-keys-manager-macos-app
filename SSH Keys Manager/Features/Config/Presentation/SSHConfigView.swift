import SwiftUI

struct SSHConfigView: View {
    @Bindable var model: AppModel
    @State private var activeSheet: SSHConfigSheet?

    var body: some View {
        HStack(spacing: 0) {
            SSHConfigSidebar(
                entries: model.configEntries,
                sshDirectoryPath: model.sshDirectoryPath,
                isLoading: model.isLoadingConfig,
                errorMessage: model.configErrorMessage,
                isConfigFileMissing: model.isConfigFileMissing,
                canRevealSSHDirectory: model.canRevealSSHDirectoryInFinder,
                onRevealConfig: {
                    model.configCoordinator.revealConfigInFinder()
                },
                onRefresh: {
                    model.configCoordinator.load()
                },
                onAddHost: {
                    activeSheet = .add
                },
                sortOrder: $model.configSortOrder,
                selectedEntryID: $model.selectedConfigEntryID
            )

            Divider()

            SSHConfigDetailView(
                entry: model.selectedConfigEntry,
                emptyState: configDetailEmptyState,
                onEdit: { entry in
                    activeSheet = .edit(entry)
                },
                onDelete: { entry in
                    activeSheet = .delete(entry)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: model.sshDirectoryPath) {
            await model.configCoordinator.loadIfNeeded()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .add:
                AddSSHConfigHostView(
                    configPath: SSHWorkspacePath.configDisplayPath(for: model.sshDirectoryPath),
                    identityFileOptions: model.availableIdentityFileOptions,
                    onSave: model.configCoordinator.addHost
                )
            case .edit(let entry):
                EditSSHConfigHostView(
                    entry: entry,
                    configPath: SSHWorkspacePath.configDisplayPath(for: model.sshDirectoryPath),
                    identityFileOptions: model.availableIdentityFileOptions,
                    onSave: { request in
                        try await model.configCoordinator.updateHost(entry, with: request)
                    }
                )
            case .delete(let entry):
                DeleteSSHConfigHostView(entry: entry) {
                    model.selectedConfigEntryID = entry.id
                    try await model.configCoordinator.deleteSelectedEntry()
                }
            }
        }
    }

    private var configDetailEmptyState: AppEmptyStateContent {
        let configPath = SSHWorkspacePath.configDisplayPath(for: model.sshDirectoryPath)

        if model.isLoadingConfig {
            return AppEmptyStateContent(
                title: "Loading SSH Config",
                message: "Please wait while the app reads \(configPath).",
                systemImage: "arrow.clockwise"
            )
        }

        if let errorMessage = model.configErrorMessage {
            return AppEmptyStateContent(
                title: "SSH Config Unavailable",
                message: errorMessage,
                systemImage: "exclamationmark.triangle"
            )
        }

        if model.isConfigFileMissing {
            return AppEmptyStateContent(
                title: "Config File Missing",
                message: "No SSH config file was found at \(configPath).",
                systemImage: "doc.badge.plus",
                primaryAction: AppEmptyStateAction(
                    title: "Create Config",
                    systemImage: "plus.circle.fill",
                    action: {
                        Task {
                            await model.workspaceCoordinator.createEmptyConfigFile()
                        }
                    }
                )
            )
        }

        if model.configEntries.isEmpty {
            return AppEmptyStateContent(
                title: "Config File Is Empty",
                message: "No Host blocks were found in \(configPath). Press Add Host Entry to add the first host.",
                systemImage: "doc.text.magnifyingglass"
            )
        }

        return AppEmptyStateContent(
            title: "Select a Host",
            message: "Choose a host entry to inspect its SSH config fields.",
            systemImage: "server.rack"
        )
    }
}

private enum SSHConfigSheet: Identifiable {
    case add
    case edit(SSHConfigEntry)
    case delete(SSHConfigEntry)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let entry):
            return "edit:\(entry.id)"
        case .delete(let entry):
            return "delete:\(entry.id)"
        }
    }
}
