import SwiftUI

struct SSHKeysView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SSHKeysSidebar(
                keys: model.displayedKeys,
                completePairCount: model.keys.count,
                otherKeyCount: model.otherKeys.count,
                sshDirectoryPath: model.sshDirectoryPath,
                isLoading: model.isLoadingKeys,
                errorMessage: model.keyErrorMessage,
                canRevealSSHDirectory: model.canRevealSSHDirectoryInFinder,
                onRevealDirectory: {
                    model.keysCoordinator.revealSSHDirectoryInFinder()
                },
                onRefresh: {
                    model.keysCoordinator.load()
                },
                onGenerateKey: { request in
                    try await model.keysCoordinator.generateKey(request)
                },
                availableKeyName: { baseName in
                    await model.keysCoordinator.availableKeyName(for: baseName)
                },
                selectedList: $model.selectedKeyList,
                sortOrder: $model.keySortOrder,
                selectedKeyID: $model.selectedKeyID
            )

            Divider()

            SSHKeyDetailView(
                key: model.selectedKey,
                emptyState: keyDetailEmptyState,
                onReveal: {
                    model.keysCoordinator.revealSelectedKeyInFinder()
                },
                onCopyPublicKey: {
                    await model.keysCoordinator.copySelectedPublicKey()
                },
                onCopyPrivateKey: {
                    await model.keysCoordinator.copySelectedPrivateKey()
                },
                onCopyFingerprint: {
                    model.keysCoordinator.copySelectedFingerprint()
                },
                onRename: { newName in
                    try await model.keysCoordinator.renameSelectedKey(to: newName)
                },
                onDuplicate: { newName in
                    try await model.keysCoordinator.duplicateSelectedKey(to: newName)
                },
                onUpdateComment: { comment in
                    try await model.keysCoordinator.updateSelectedKeyComment(comment)
                },
                onChangePassphrase: { oldPassphrase, newPassphrase in
                    try await model.keysCoordinator.changeSelectedKeyPassphrase(
                        oldPassphrase: oldPassphrase,
                        newPassphrase: newPassphrase
                    )
                },
                onDelete: {
                    try await model.keysCoordinator.deleteSelectedKey()
                }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: model.sshDirectoryPath) {
            await model.keysCoordinator.loadIfNeeded()
        }
    }

    private var keyDetailEmptyState: AppEmptyStateContent {
        if model.isLoadingKeys {
            return AppEmptyStateContent(
                title: "Loading SSH Keys",
                message: "Please wait while the app reads the selected SSH workspace.",
                systemImage: "arrow.clockwise"
            )
        }

        if let errorMessage = model.keyErrorMessage {
            return AppEmptyStateContent(
                title: "SSH Keys Unavailable",
                message: errorMessage,
                systemImage: "exclamationmark.triangle"
            )
        }

        switch model.selectedKeyList {
        case .completePairs where model.keys.isEmpty:
            return AppEmptyStateContent(
                title: "Select a Key",
                message: "Choose a key in the sidebar to display its details.",
                systemImage: "key"
            )
        case .otherKeys where model.otherKeys.isEmpty:
            return AppEmptyStateContent(
                title: "Select a Key",
                message: "Choose a key in the sidebar to display its details.",
                systemImage: "key"
            )
        default:
            return AppEmptyStateContent(
                title: "Select a Key",
                message: "Choose a key in the sidebar to display its details.",
                systemImage: "key"
            )
        }
    }
}
