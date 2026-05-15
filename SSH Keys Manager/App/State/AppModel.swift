import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    @ObservationIgnored
    lazy var keysCoordinator = SSHKeysCoordinator(model: self)
    @ObservationIgnored
    lazy var configCoordinator = SSHConfigCoordinator(model: self)
    @ObservationIgnored
    lazy var workspaceCoordinator = AppWorkspaceCoordinator(model: self)

    var selectedTab: AppTab = .keys
    var selectedKeyID: SSHKeyItem.ID?
    var selectedConfigEntryID: SSHConfigEntry.ID?
    var sshDirectoryPath: String
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
    var isChangingSSHDirectory = false
    var notification: AppNotification?

    var originalConfigEntries: [SSHConfigEntry]
    let keyStorage: any SSHKeyStorageManaging
    let configStorage: any SSHConfigStorageManaging
    let keyActions: any SSHKeyActionHandling
    let preferences: any AppPreferencesManaging
    let workspaceValidator: any SSHWorkspaceValidating
    let externalToolValidator: ExternalToolValidator

    var activeKeyOperationCount = 0
    var activeConfigOperationCount = 0
    var activeDirectoryChangeCount = 0
    var loadedKeysDirectoryPath: String?
    var loadedConfigDirectoryPath: String?

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
        self.keyActions = resolvedDependencies.keyActions
        self.preferences = resolvedDependencies.preferences
        self.workspaceValidator = resolvedDependencies.workspaceValidator
        self.externalToolValidator = resolvedDependencies.externalToolValidator
        self.sshDirectoryPath = resolvedDependencies.preferences.sshDirectoryPath
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
