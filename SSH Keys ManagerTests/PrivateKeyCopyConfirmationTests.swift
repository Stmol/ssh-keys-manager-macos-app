import AppKit
import XCTest
@testable import SSH_Keys_Manager

@MainActor
final class PrivateKeyCopyConfirmationTests: XCTestCase {
    func testCancelledPrivateKeyCopyLeavesPasteboardUntouched() async throws {
        let pasteboard = try makePasteboard()
        pasteboard.setString("existing value", forType: .string)
        let confirmer = RecordingPrivateKeyCopyConfirmer(result: false)
        let model = try makeModel(pasteboard: pasteboard, confirmer: confirmer)

        await model.copyPrivateKey(for: makeKeyItem())

        XCTAssertEqual(pasteboard.string(forType: .string), "existing value")
        XCTAssertNil(model.notification)
        XCTAssertEqual(confirmer.requestedKeyNames, ["id_ed25519"])
    }

    func testConfirmedPrivateKeyCopyWritesPasteboard() async throws {
        let pasteboard = try makePasteboard()
        let confirmer = RecordingPrivateKeyCopyConfirmer(result: true)
        let model = try makeModel(pasteboard: pasteboard, confirmer: confirmer)

        await model.copyPrivateKey(for: makeKeyItem())

        XCTAssertEqual(pasteboard.string(forType: .string), TestSSHKeyStorage.privateKeyContents)
        XCTAssertEqual(model.notification?.message, "Private key copied - clearing in 60s")
        XCTAssertEqual(confirmer.requestedKeyNames, ["id_ed25519"])
    }

    func testDisabledPreferenceBypassesConfirmerAndCopiesPrivateKey() async throws {
        let pasteboard = try makePasteboard()
        let confirmer = RecordingPrivateKeyCopyConfirmer(result: false)
        let model = try makeModel(
            pasteboard: pasteboard,
            confirmer: confirmer,
            configurePreferences: { $0.setConfirmPrivateKeyCopy(false) }
        )

        await model.copyPrivateKey(for: makeKeyItem())

        XCTAssertEqual(pasteboard.string(forType: .string), TestSSHKeyStorage.privateKeyContents)
        XCTAssertTrue(confirmer.requestedKeyNames.isEmpty)
    }

    func testSessionSuppressionBypassesConfirmerWithinSameAppModelLifetime() async throws {
        let pasteboard = try makePasteboard()
        let confirmer = RecordingPrivateKeyCopyConfirmer(result: true, suppressAfterConfirm: true)
        let model = try makeModel(pasteboard: pasteboard, confirmer: confirmer)

        await model.copyPrivateKey(for: makeKeyItem(name: "first"))
        pasteboard.clearContents()
        await model.copyPrivateKey(for: makeKeyItem(name: "second"))

        XCTAssertEqual(pasteboard.string(forType: .string), TestSSHKeyStorage.privateKeyContents)
        XCTAssertEqual(confirmer.requestedKeyNames, ["first"])
    }

    func testConfirmPrivateKeyCopyDefaultsToTrueAndPersists() throws {
        let suiteName = "PrivateKeyCopyConfirmationTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = AppPreferences(userDefaults: userDefaults)
        XCTAssertTrue(preferences.confirmPrivateKeyCopy)

        preferences.setConfirmPrivateKeyCopy(false)

        XCTAssertFalse(AppPreferences(userDefaults: userDefaults).confirmPrivateKeyCopy)
    }

    private func makeModel(
        pasteboard: NSPasteboard,
        confirmer: RecordingPrivateKeyCopyConfirmer,
        configurePreferences: (AppPreferences) -> Void = { _ in }
    ) throws -> AppModel {
        let suiteName = "PrivateKeyCopyConfirmationTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let preferences = AppPreferences(userDefaults: userDefaults)
        configurePreferences(preferences)

        return AppModel(
            dependencies: AppModelDependencies(
                keyStorage: TestSSHKeyStorage(),
                configStorage: TestSSHConfigStorage(),
                keyActions: SSHKeyFileActions(pasteboard: pasteboard),
                preferences: preferences,
                privateKeyCopyConfirmer: confirmer
            )
        )
    }

    private func makePasteboard() throws -> NSPasteboard {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name("test-\(UUID().uuidString)")))
        pasteboard.clearContents()
        return pasteboard
    }

    private func makeKeyItem(name: String = "id_ed25519") -> SSHKeyItem {
        SSHKeyItem(
            id: "/tmp/\(name)",
            name: name,
            publicKeyPath: "/tmp/\(name).pub",
            privateKeyPath: "/tmp/\(name)",
            filePath: "/tmp/\(name)",
            kind: .completePair,
            type: "ED25519",
            fingerprint: "SHA256:test",
            comment: "",
            createdAt: Date(timeIntervalSince1970: 0),
            isPassphraseProtected: false
        )
    }
}

@MainActor
private final class RecordingPrivateKeyCopyConfirmer: PrivateKeyCopyConfirming {
    private let result: Bool
    private let suppressAfterConfirm: Bool
    private(set) var requestedKeyNames: [String] = []
    private(set) var suppressConfirmationUntilAppRestarts = false

    init(result: Bool, suppressAfterConfirm: Bool = false) {
        self.result = result
        self.suppressAfterConfirm = suppressAfterConfirm
    }

    func confirmCopy(keyName: String) -> Bool {
        requestedKeyNames.append(keyName)
        suppressConfirmationUntilAppRestarts = result && suppressAfterConfirm
        return result
    }
}

private actor TestSSHKeyStorage: SSHKeyStorageManaging {
    static let privateKeyContents = "-----BEGIN OPENSSH PRIVATE KEY-----\nprivate\n-----END OPENSSH PRIVATE KEY-----\n"

    func loadKeys(from directoryPath: String) async throws -> SSHKeyInventory {
        SSHKeyInventory(completePairs: [], otherKeys: [])
    }

    func publicKeyContents(for key: SSHKeyItem) async throws -> String {
        XCTFail("publicKeyContents should not be called")
        return ""
    }

    func privateKeyContents(for key: SSHKeyItem) async throws -> String {
        Self.privateKeyContents
    }

    func delete(_ key: SSHKeyItem) async throws {
        XCTFail("delete should not be called")
    }

    func updateComment(for key: SSHKeyItem, comment: String) async throws {
        XCTFail("updateComment should not be called")
    }

    func changePassphrase(for key: SSHKeyItem, oldPassphrase: String, newPassphrase: String) async throws {
        XCTFail("changePassphrase should not be called")
    }

    func rename(_ key: SSHKeyItem, to newName: String) async throws -> SSHKeyItem.ID {
        XCTFail("rename should not be called")
        return ""
    }

    func duplicate(_ key: SSHKeyItem, to newName: String) async throws -> SSHKeyItem.ID {
        XCTFail("duplicate should not be called")
        return ""
    }

    func generateKey(_ request: SSHKeyGenerationRequest, in directoryPath: String) async throws -> SSHKeyItem.ID {
        XCTFail("generateKey should not be called")
        return ""
    }

    func availableKeyName(for baseName: String, in directoryPath: String) async throws -> String {
        XCTFail("availableKeyName should not be called")
        return baseName
    }

    func existingKeyFileNames(in directoryPath: String) async throws -> Set<String> {
        XCTFail("existingKeyFileNames should not be called")
        return []
    }
}

private actor TestSSHConfigStorage: SSHConfigStorageManaging {
    func loadEntries(from directoryPath: String) async throws -> [SSHConfigEntry] {
        []
    }

    func apply(
        _ mutation: SSHConfigMutation,
        inDirectory directoryPath: String,
        propertyIndentation: SSHConfigHostPropertyIndentation,
        backupLimit: Int
    ) async throws {
        XCTFail("apply should not be called")
    }

    func createEmptyConfig(inDirectory directoryPath: String) async throws {
        XCTFail("createEmptyConfig should not be called")
    }
}
