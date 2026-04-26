import Foundation

struct AppModelDependencies {
    let keyStorage: any SSHKeyStorageManaging
    let configStorage: any SSHConfigStorageManaging
    let keyActions: any SSHKeyActionHandling
    let preferences: any AppPreferencesManaging
    let workspaceValidator: any SSHWorkspaceValidating
    let externalToolValidator: ExternalToolValidator

    init(
        keyStorage: any SSHKeyStorageManaging,
        configStorage: any SSHConfigStorageManaging,
        keyActions: any SSHKeyActionHandling,
        preferences: any AppPreferencesManaging = AppPreferences(),
        workspaceValidator: any SSHWorkspaceValidating = SSHWorkspaceValidator(),
        externalToolValidator: ExternalToolValidator = ExternalToolValidator()
    ) {
        self.keyStorage = keyStorage
        self.configStorage = configStorage
        self.keyActions = keyActions
        self.preferences = preferences
        self.workspaceValidator = workspaceValidator
        self.externalToolValidator = externalToolValidator
    }

    init(
        keyStorage: any SSHKeyStorageManaging,
        configStorage: any SSHConfigStorageManaging,
        keyActions: any SSHKeyActionHandling,
        preferences: any AppPreferencesManaging = AppPreferences(),
        workspaceValidator: any SSHWorkspaceValidating = SSHWorkspaceValidator()
    ) {
        self.init(
            keyStorage: keyStorage,
            configStorage: configStorage,
            keyActions: keyActions,
            preferences: preferences,
            workspaceValidator: workspaceValidator,
            externalToolValidator: ExternalToolValidator()
        )
    }

    static func live() -> Self {
        let preferences = AppPreferences()
        return live(
            keyStore: SSHKeyStore(
                sshKeygenURL: URL(fileURLWithPath: preferences.sshKeygenPath)
            ),
            preferences: preferences
        )
    }

    static func live(
        keyStore: SSHKeyStore,
        preferences: AppPreferences = AppPreferences()
    ) -> Self {
        Self(
            keyStorage: SSHKeyStorage(keyStore: keyStore),
            configStorage: SSHConfigStorage(),
            keyActions: SSHKeyFileActions(),
            preferences: preferences,
            workspaceValidator: SSHWorkspaceValidator(),
            externalToolValidator: ExternalToolValidator()
        )
    }
}
