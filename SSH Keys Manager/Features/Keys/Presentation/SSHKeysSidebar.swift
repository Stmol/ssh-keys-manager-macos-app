import SwiftUI

struct SSHKeysSidebar: View {
    let keys: [SSHKeyItem]
    let completePairCount: Int
    let otherKeyCount: Int
    let sshDirectoryPath: String
    let isLoading: Bool
    let errorMessage: String?
    let canRevealSSHDirectory: Bool
    let onRevealDirectory: () -> Void
    let onRefresh: () -> Void
    let onGenerateKey: (SSHKeyGenerationRequest) async throws -> Void
    let availableKeyName: (String) async -> String?
    @Binding var selectedList: SSHKeyListKind
    @Binding var sortOrder: SSHKeySortOrder
    @Binding var selectedKeyID: SSHKeyItem.ID?
    @State private var activeSheet: SSHKeysSidebarSheet?

    var body: some View {
        AppSidebarPanel(
            title: keyCountTitle,
            path: SSHWorkspacePath.displayPath(for: sshDirectoryPath),
            canRevealPath: canRevealSSHDirectory,
            revealHelp: "Reveal SSH directory in Finder",
            onRevealPath: onRevealDirectory,
            trailingActions: {
                SidebarRefreshButton(
                    isLoading: isLoading,
                    helpText: "Refresh SSH keys from the selected directory",
                    accessibilityLabel: "Refresh SSH keys",
                    action: onRefresh
                )
                SSHKeyFilterMenu(
                    selectedList: $selectedList,
                    completePairCount: completePairCount,
                    otherKeyCount: otherKeyCount
                )
                SortOrderMenu(
                    sortOrder: $sortOrder,
                    help: "Sort SSH keys",
                    accessibilityLabel: "Sort SSH keys"
                )
            },
            content: {
                SSHKeyList(
                    keys: keys,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    selectedKeyID: $selectedKeyID
                )
            },
            footer: {
                SidebarPrimaryActionButton(
                    title: "Generate New Key",
                    systemImage: "plus.circle.fill",
                    helpText: "Generate a new private and public SSH key pair",
                    isDisabled: isLoading
                ) {
                    activeSheet = .generateKey
                }
            }
        )
        .sheet(item: $activeSheet, content: sheetContent)
    }

    @ViewBuilder
    private func sheetContent(_ sheet: SSHKeysSidebarSheet) -> some View {
        switch sheet {
        case .generateKey:
            GenerateSSHKeyView(
                sshDirectoryPath: sshDirectoryPath,
                availableKeyName: availableKeyName,
                onGenerate: onGenerateKey
            )
        }
    }

    private var keyCountTitle: String {
        let count = keys.count
        let noun = count == 1 ? "key" : "keys"
        return "\(count) \(noun)"
    }
}

private struct SSHKeyFilterMenu: View {
    @Binding var selectedList: SSHKeyListKind
    let completePairCount: Int
    let otherKeyCount: Int
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            ToolbarIcon(
                systemName: "line.3.horizontal.decrease.circle",
                isHovered: isHovered
            )
        }
        .buttonStyle(AppToolbarButtonStyle())
        .frame(width: 28, height: 28)
        .onHover { isHovered = isEnabled && $0 }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            SSHKeyFilterPopover(
                selectedList: $selectedList,
                completePairCount: completePairCount,
                otherKeyCount: otherKeyCount,
                isPresented: $isPresented
            )
        }
        .help("Filter SSH keys")
        .accessibilityLabel("Filter SSH keys")
    }
}

private struct SSHKeyFilterPopover: View {
    @Binding var selectedList: SSHKeyListKind
    let completePairCount: Int
    let otherKeyCount: Int
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            AppPopoverOptionButton(
                title: "Pairs (\(completePairCount))",
                isSelected: selectedList == .completePairs
            ) {
                selectedList = .completePairs
                isPresented = false
            }

            AppPopoverOptionButton(
                title: "Other (\(otherKeyCount))",
                isSelected: selectedList == .otherKeys
            ) {
                selectedList = .otherKeys
                isPresented = false
            }
        }
        .padding(.vertical, 6)
        .frame(width: 190)
    }
}

private enum SSHKeysSidebarSheet: String, Identifiable {
    case generateKey

    var id: String {
        rawValue
    }
}
