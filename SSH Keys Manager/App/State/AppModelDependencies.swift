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
        externalToolValidator: ExternalToolValidator = ExternalToolValidator(),
        privateKeyCopyConfirmer: any PrivateKeyCopyConfirming = NSAlertPrivateKeyCopyConfirmer()
    ) {
        self.keyStorage = keyStorage
        self.configStorage = configStorage
        self.keyActions = keyActions
        self.preferences = AppPreferencesWithPrivateKeyCopyConfirmer(
            preferences: preferences,
            privateKeyCopyConfirmer: privateKeyCopyConfirmer
        )
        self.workspaceValidator = workspaceValidator
        self.externalToolValidator = externalToolValidator
    }

    init(
        keyStorage: any SSHKeyStorageManaging,
        configStorage: any SSHConfigStorageManaging,
        keyActions: any SSHKeyActionHandling,
        preferences: any AppPreferencesManaging = AppPreferences(),
        workspaceValidator: any SSHWorkspaceValidating = SSHWorkspaceValidator(),
        privateKeyCopyConfirmer: any PrivateKeyCopyConfirming = NSAlertPrivateKeyCopyConfirmer()
    ) {
        self.init(
            keyStorage: keyStorage,
            configStorage: configStorage,
            keyActions: keyActions,
            preferences: preferences,
            workspaceValidator: workspaceValidator,
            externalToolValidator: ExternalToolValidator(),
            privateKeyCopyConfirmer: privateKeyCopyConfirmer
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
            externalToolValidator: ExternalToolValidator(),
            privateKeyCopyConfirmer: NSAlertPrivateKeyCopyConfirmer()
        )
    }
}

private struct AppPreferencesWithPrivateKeyCopyConfirmer: AppPreferencesManaging, PrivateKeyCopyConfirmationProviding {
    let preferences: any AppPreferencesManaging
    let privateKeyCopyConfirmer: any PrivateKeyCopyConfirming

    var sshDirectoryPath: String {
        preferences.sshDirectoryPath
    }

    var sshKeygenPath: String {
        preferences.sshKeygenPath
    }

    var hostPropertyIndentation: SSHConfigHostPropertyIndentation {
        preferences.hostPropertyIndentation
    }

    var configBackupLimit: Int {
        preferences.configBackupLimit
    }

    var isReadOnlyModeEnabled: Bool {
        preferences.isReadOnlyModeEnabled
    }

    var isMinimizeToMenuBarEnabled: Bool {
        preferences.isMinimizeToMenuBarEnabled
    }

    var clipboardClearSeconds: Int {
        preferences.clipboardClearSeconds
    }

    var confirmPrivateKeyCopy: Bool {
        preferences.confirmPrivateKeyCopy
    }

    func setSSHDirectoryPath(_ path: String) {
        preferences.setSSHDirectoryPath(path)
    }

    func setSSHKeygenPath(_ path: String) {
        preferences.setSSHKeygenPath(path)
    }

    func setHostPropertyIndentation(_ indentation: SSHConfigHostPropertyIndentation) {
        preferences.setHostPropertyIndentation(indentation)
    }

    func setConfigBackupLimit(_ limit: Int) {
        preferences.setConfigBackupLimit(limit)
    }

    func setReadOnlyModeEnabled(_ isEnabled: Bool) {
        preferences.setReadOnlyModeEnabled(isEnabled)
    }

    func setMinimizeToMenuBarEnabled(_ isEnabled: Bool) {
        preferences.setMinimizeToMenuBarEnabled(isEnabled)
    }

    func setClipboardClearSeconds(_ seconds: Int) {
        preferences.setClipboardClearSeconds(seconds)
    }

    func setConfirmPrivateKeyCopy(_ isEnabled: Bool) {
        preferences.setConfirmPrivateKeyCopy(isEnabled)
    }
}
