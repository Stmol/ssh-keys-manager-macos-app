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
    let onCheckHostReachability: () -> Void
    let onAddHost: () -> Void
    let isCheckingHosts: Bool
    let hostStatuses: [SSHConfigEntry.ID: SSHConfigHostReachabilityStatus]
    @Binding var sortOrder: SSHConfigSortOrder
    @Binding var selectedEntryID: SSHConfigEntry.ID?
    @Binding var configSearchText: String

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
                SidebarHostCheckButton(
                    isChecking: isCheckingHosts,
                    action: onCheckHostReachability
                )
                SortOrderMenu(
                    sortOrder: $sortOrder,
                    help: "Sort SSH config hosts",
                    accessibilityLabel: "Sort SSH config hosts"
                )
            },
            content: {
                VStack(alignment: .leading, spacing: 10) {
                    SearchField(text: $configSearchText, placeholder: "Search hosts...")

                    SSHConfigEntryList(
                        entries: entries,
                        isLoading: isLoading,
                        errorMessage: errorMessage,
                        isConfigFileMissing: isConfigFileMissing,
                        hostStatuses: hostStatuses,
                        selectedEntryID: $selectedEntryID,
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
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

private struct SidebarHostCheckButton: View {
    let isChecking: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ToolbarIcon(
                systemName: "dot.radiowaves.left.and.right",
                isHovered: isHovered && !isChecking
            )
        }
        .buttonStyle(AppToolbarButtonStyle())
        .frame(width: 28, height: 28)
        .onHover { isHovered = isEnabled && !isChecking && $0 }
        .opacity(isChecking ? 0.45 : 1)
        .disabled(isChecking)
        .help(isChecking ? "Checking SSH host reachability" : "Check SSH host reachability")
        .accessibilityLabel("Check SSH host reachability")
    }
}
