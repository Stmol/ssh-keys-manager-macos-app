import SwiftUI

struct SSHConfigSidebar: View {
    let entries: [SSHConfigEntry]
    let sshDirectoryPath: String
    let isLoading: Bool
    let errorMessage: String?
    let isConfigFileMissing: Bool
    let canRevealSSHDirectory: Bool
    let onRevealConfig: () -> Void
    let onRefresh: () -> Void
    let onAddHost: () -> Void
    @Binding var sortOrder: SSHConfigSortOrder
    @Binding var selectedEntryID: SSHConfigEntry.ID?

    var body: some View {
        AppSidebarPanel(
            title: hostCountTitle,
            path: configPath,
            canRevealPath: canRevealSSHDirectory,
            revealHelp: "Reveal SSH config in Finder",
            onRevealPath: onRevealConfig,
            trailingActions: {
                SidebarRefreshButton(
                    isLoading: isLoading,
                    helpText: "Refresh SSH config from disk",
                    accessibilityLabel: "Refresh SSH config",
                    action: onRefresh
                )
                SortOrderMenu(
                    sortOrder: $sortOrder,
                    help: "Sort SSH config hosts",
                    accessibilityLabel: "Sort SSH config hosts"
                )
            },
            content: {
                SSHConfigEntryList(
                    entries: entries,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    isConfigFileMissing: isConfigFileMissing,
                    selectedEntryID: $selectedEntryID
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            },
            footer: {
                SidebarPrimaryActionButton(
                    title: "Add Host Entry",
                    systemImage: "plus.circle.fill",
                    helpText: "Append a Host block to SSH config",
                    isDisabled: isConfigFileMissing,
                    action: onAddHost
                )
            }
        )
    }

    private var configPath: String {
        SSHWorkspacePath.configDisplayPath(for: sshDirectoryPath)
    }

    private var hostCountTitle: String {
        let count = entries.count
        let noun = count == 1 ? "host" : "hosts"
        return "\(count) \(noun)"
    }
}
