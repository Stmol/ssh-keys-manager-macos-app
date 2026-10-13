import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var selectedTab: AppTab = .keys
    var selectedKeyID: SSHKeyItem.ID?
    var selectedConfigEntryID: SSHConfigEntry.ID?
    var sshDirectoryPath: String
    var includeSubfolders: Bool {
        didSet {
            preferences.setIncludeSubfolders(includeSubfolders)
            Task {
                await refreshAvailableSubfolders()
            }
            loadKeys()
        }
    }
    var subfolderScope: SSHSubfolderScope {
        didSet {
            preferences.setSubfolderScope(subfolderScope)
            loadKeys()
        }
    }
    var selectedSubfolders: [String] {
        didSet {
            preferences.setSelectedSubfolders(selectedSubfolders)
            loadKeys()
        }
    }
    var availableSubfolders: [String] = []
    var sshKeygenPath: String
    var hostPropertyIndentation: SSHConfigHostPropertyIndentation {
        didSet {
            preferences.setHostPropertyIndentation(hostPropertyIndentation)
        }
    }
    var configBackupLimit: Int {
        didSet {
            let clampedLimit = SSHConfigBackupLimit.clamped(configBackupLimit)
            if configBackupLimit != clampedLimit {
                configBackupLimit = clampedLimit
            }

            preferences.setConfigBackupLimit(configBackupLimit)
        }
    }
    var isReadOnlyModeEnabled: Bool {
        didSet {
            preferences.setReadOnlyModeEnabled(isReadOnlyModeEnabled)
        }
    }
    var isMinimizeToMenuBarEnabled: Bool {
        didSet {
            preferences.setMinimizeToMenuBarEnabled(isMinimizeToMenuBarEnabled)
        }
    }
    var sshKeygenStatus: ExternalToolStatus

    var keys: [SSHKeyItem]
    var otherKeys: [SSHKeyItem] = []
    var selectedKeyList: SSHKeyListKind = .completePairs {
        didSet {
            if !displayedKeys.contains(where: { $0.id == selectedKeyID }) {
                selectedKeyID = displayedKeys.first?.id
            }
        }
    }
    var searchText = ""
    var keySortOrder: SSHKeySortOrder = .createdDescending {
        didSet {
            keys = sortedKeys(keys)
            otherKeys = sortedKeys(otherKeys)
        }
    }

    var configSearchText = ""
    var configEntries: [SSHConfigEntry]
    var configSortOrder: SSHConfigSortOrder = .original {
        didSet {
            configEntries = sortedConfigEntries(originalConfigEntries)
        }
    }

    var isLoadingKeys = false
    var keyErrorMessage: String?
    var isLoadingConfig = false
    var configErrorMessage: String?
    var isConfigFileMissing = false
    var isCheckingConfigHosts = false
    var isChangingSSHDirectory = false
    var notification: AppNotification?
    var configHostStatuses: [SSHConfigEntry.ID: SSHConfigHostReachabilityStatus] = [:]

    var originalConfigEntries: [SSHConfigEntry]
    let keyStorage: any SSHKeyStorageManaging
    let configStorage: any SSHConfigStorageManaging
    let hostReachabilityChecker: any SSHHostReachabilityChecking
    let keyActions: any SSHKeyActionHandling
    let preferences: any AppPreferencesManaging
    let workspaceValidator: any SSHWorkspaceValidating
    let externalToolValidator: ExternalToolValidator

    var activeKeyOperationCount = 0
    var activeConfigOperationCount = 0
    var activeDirectoryChangeCount = 0
    var loadedKeysDirectoryPath: String?
    var loadedConfigDirectoryPath: String?
    @ObservationIgnored var isPrivateKeyCopyConfirmationSuppressed = false
    @ObservationIgnored var configHostCheckGeneration = 0
    @ObservationIgnored var configHostReachabilityTask: Task<Void, Never>?

    init(
        keys: [SSHKeyItem] = [],
        configEntries: [SSHConfigEntry] = [],
        keyStore: SSHKeyStore? = nil,
        dependencies: AppModelDependencies? = nil
    ) {
        let resolvedKeyStore = keyStore ?? SSHKeyStore(
            sshKeygenURL: URL(fileURLWithPath: AppPreferences().sshKeygenPath)
        )
        let resolvedDependencies = dependencies ?? .live(keyStore: resolvedKeyStore)

        self.keys = keys.sortedBy(.createdDescending)
        self.configEntries = configEntries.sortedBy(.original)
        self.originalConfigEntries = configEntries
        self.keyStorage = resolvedDependencies.keyStorage
        self.configStorage = resolvedDependencies.configStorage
        self.hostReachabilityChecker = resolvedDependencies.hostReachabilityChecker
        self.keyActions = resolvedDependencies.keyActions
        self.preferences = resolvedDependencies.preferences
        self.workspaceValidator = resolvedDependencies.workspaceValidator
        self.externalToolValidator = resolvedDependencies.externalToolValidator
        self.sshDirectoryPath = resolvedDependencies.preferences.sshDirectoryPath
        self.includeSubfolders = resolvedDependencies.preferences.includeSubfolders
        self.subfolderScope = resolvedDependencies.preferences.subfolderScope
        self.selectedSubfolders = resolvedDependencies.preferences.selectedSubfolders
        self.sshKeygenPath = resolvedDependencies.preferences.sshKeygenPath
        self.hostPropertyIndentation = resolvedDependencies.preferences.hostPropertyIndentation
        self.configBackupLimit = resolvedDependencies.preferences.configBackupLimit
        self.isReadOnlyModeEnabled = resolvedDependencies.preferences.isReadOnlyModeEnabled
        self.isMinimizeToMenuBarEnabled = resolvedDependencies.preferences.isMinimizeToMenuBarEnabled
        self.sshKeygenStatus = resolvedDependencies.externalToolValidator.status(
            for: .sshKeygen,
            path: resolvedDependencies.preferences.sshKeygenPath
        )
        selectedKeyID = self.keys.first?.id
        selectedConfigEntryID = self.configEntries.first?.id
    }

    var keyScanOptions: SSHKeyScanOptions {
        SSHKeyScanOptions(
            includesSubfolders: includeSubfolders,
            scope: subfolderScope,
            selectedSubfolders: selectedSubfolders
        )
    }

    var selectedKey: SSHKeyItem? {
        displayedKeys.first { $0.id == selectedKeyID }
    }

    var recentKeys: [SSHKeyItem] {
        (keys + otherKeys)
            .sortedBy(.createdDescending)
            .prefix(10)
            .map { $0 }
    }

    var displayedKeys: [SSHKeyItem] {
        let sourceKeys: [SSHKeyItem]
        switch selectedKeyList {
        case .completePairs:
            sourceKeys = keys
        case .otherKeys:
            sourceKeys = otherKeys
        }

        if searchText.isEmpty {
            return sourceKeys
        }

        return sourceKeys.filter { SSHKeyItem.fuzzyMatch(query: searchText, in: $0.name) }
    }

    var displayedConfigEntries: [SSHConfigEntry] {
        if configSearchText.isEmpty {
            return configEntries
        }

        return configEntries.filter { SSHConfigEntry.fuzzyMatches(query: configSearchText, in: $0) }
    }

    var selectedConfigEntry: SSHConfigEntry? {
        displayedConfigEntries.first { $0.id == selectedConfigEntryID }
    }

    var availableIdentityFileOptions: [SSHConfigIdentityFileOption] {
        SSHConfigIdentityFileCatalog.options(
            keys: keys,
            otherKeys: otherKeys,
            homeDirectoryPath: FileManager.default.homeDirectoryForCurrentUser.path
        )
    }

    var canRevealSSHDirectoryInFinder: Bool {
        let normalizedPath = SSHWorkspacePath.normalizeDirectoryPath(sshDirectoryPath)
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: normalizedPath, isDirectory: &isDirectory) else {
            return false
        }

        return isDirectory.boolValue
    }
}
