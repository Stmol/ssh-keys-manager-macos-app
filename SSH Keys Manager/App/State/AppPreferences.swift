import Foundation

protocol AppPreferencesManaging {
    var sshDirectoryPath: String { get }
    var sshKeygenPath: String { get }
    var hostPropertyIndentation: SSHConfigHostPropertyIndentation { get }
    var configBackupLimit: Int { get }
    var isReadOnlyModeEnabled: Bool { get }
    var isMinimizeToMenuBarEnabled: Bool { get }
    var clipboardClearSeconds: Int { get }
    var confirmPrivateKeyCopy: Bool { get }
    func setSSHDirectoryPath(_ path: String)
    func setSSHKeygenPath(_ path: String)
    func setHostPropertyIndentation(_ indentation: SSHConfigHostPropertyIndentation)
    func setConfigBackupLimit(_ limit: Int)
    func setReadOnlyModeEnabled(_ isEnabled: Bool)
    func setMinimizeToMenuBarEnabled(_ isEnabled: Bool)
    func setClipboardClearSeconds(_ seconds: Int)
    func setConfirmPrivateKeyCopy(_ isEnabled: Bool)
}

struct AppPreferences: AppPreferencesManaging {
    static let allowedClipboardClearSeconds = [0, 30, 60, 120, 300]
    static let defaultClipboardClearSeconds = 60

    private enum Keys {
        static let sshDirectoryPath = "sshDirectoryPath"
        static let sshKeygenPath = "sshKeygenPath"
        static let hostPropertyIndentation = "hostPropertyIndentation"
        static let configBackupLimit = "configBackupLimit"
        static let isReadOnlyModeEnabled = "isReadOnlyModeEnabled"
        static let isMinimizeToMenuBarEnabled = "isMinimizeToMenuBarEnabled"
        static let clipboardClearSeconds = "clipboardClearSeconds"
        static let confirmPrivateKeyCopy = "confirmPrivateKeyCopy"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var sshDirectoryPath: String {
        let storedPath = userDefaults.string(forKey: Keys.sshDirectoryPath)
        return SSHWorkspacePath.normalizeDirectoryPath(storedPath ?? SSHWorkspacePath.defaultDirectoryPath)
    }

    var sshKeygenPath: String {
        let storedPath = userDefaults.string(forKey: Keys.sshKeygenPath)
        return ExternalToolPath.normalizeExecutablePath(
            storedPath ?? ExternalTool.sshKeygen.defaultPath,
            defaultPath: ExternalTool.sshKeygen.defaultPath
        )
    }

    var hostPropertyIndentation: SSHConfigHostPropertyIndentation {
        SSHConfigHostPropertyIndentation(rawValue: userDefaults.integer(forKey: Keys.hostPropertyIndentation)) ?? .default
    }

    var configBackupLimit: Int {
        SSHConfigBackupLimit.clamped(userDefaults.integer(forKey: Keys.configBackupLimit))
    }

    var isReadOnlyModeEnabled: Bool {
        userDefaults.bool(forKey: Keys.isReadOnlyModeEnabled)
    }

    var isMinimizeToMenuBarEnabled: Bool {
        userDefaults.bool(forKey: Keys.isMinimizeToMenuBarEnabled)
    }

    var clipboardClearSeconds: Int {
        guard let storedSeconds = userDefaults.object(forKey: Keys.clipboardClearSeconds) as? Int else {
            return Self.defaultClipboardClearSeconds
        }

        return Self.normalizedClipboardClearSeconds(storedSeconds)
    }

    var confirmPrivateKeyCopy: Bool {
        userDefaults.object(forKey: Keys.confirmPrivateKeyCopy) as? Bool ?? true
    }

    func setSSHDirectoryPath(_ path: String) {
        userDefaults.set(
            SSHWorkspacePath.normalizeDirectoryPath(path),
            forKey: Keys.sshDirectoryPath
        )
    }

    func setSSHKeygenPath(_ path: String) {
        userDefaults.set(
            ExternalToolPath.normalizeExecutablePath(
                path,
                defaultPath: ExternalTool.sshKeygen.defaultPath
            ),
            forKey: Keys.sshKeygenPath
        )
    }

    func setHostPropertyIndentation(_ indentation: SSHConfigHostPropertyIndentation) {
        userDefaults.set(indentation.rawValue, forKey: Keys.hostPropertyIndentation)
    }

    func setConfigBackupLimit(_ limit: Int) {
        userDefaults.set(SSHConfigBackupLimit.clamped(limit), forKey: Keys.configBackupLimit)
    }

    func setReadOnlyModeEnabled(_ isEnabled: Bool) {
        userDefaults.set(isEnabled, forKey: Keys.isReadOnlyModeEnabled)
    }

    func setMinimizeToMenuBarEnabled(_ isEnabled: Bool) {
        userDefaults.set(isEnabled, forKey: Keys.isMinimizeToMenuBarEnabled)
    }

    func setClipboardClearSeconds(_ seconds: Int) {
        userDefaults.set(
            Self.normalizedClipboardClearSeconds(seconds),
            forKey: Keys.clipboardClearSeconds
        )
    }

    func setConfirmPrivateKeyCopy(_ isEnabled: Bool) {
        userDefaults.set(isEnabled, forKey: Keys.confirmPrivateKeyCopy)
    }

    private static func normalizedClipboardClearSeconds(_ seconds: Int) -> Int {
        allowedClipboardClearSeconds.contains(seconds) ? seconds : defaultClipboardClearSeconds
    }
}
