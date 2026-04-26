import XCTest
@testable import SSH_Keys_Manager

final class SSHKeyStoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []
    private let fileManager = FileManager.default

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? fileManager.removeItem(at: directory)
        }

        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testLoadKeysClassifiesCompletePairsStandaloneKeysAndIgnoresInvalidFiles() throws {
        let directory = try makeTemporaryDirectory()
        let pairedPrivateURL = directory.appendingPathComponent("id_ed25519")
        let pairedPublicURL = directory.appendingPathComponent("id_ed25519.pub")
        let standalonePublicURL = directory.appendingPathComponent("deploy.pub")
        let standalonePrivateURL = directory.appendingPathComponent("legacy_rsa")
        let invalidPublicURL = directory.appendingPathComponent("broken.pub")
        let unrelatedURL = directory.appendingPathComponent("notes.txt")

        try writePrivateKey(to: pairedPrivateURL)
        try writePublicKey(to: pairedPublicURL, comment: "work laptop")
        try writePublicKey(to: standalonePublicURL, type: "ssh-rsa", comment: "deploy key")
        try writePrivateKey(to: standalonePrivateURL, marker: "-----BEGIN RSA PRIVATE KEY-----")
        try "not a public key\n".write(to: invalidPublicURL, atomically: true, encoding: .utf8)
        try "plain notes\n".write(to: unrelatedURL, atomically: true, encoding: .utf8)

        let inventory = try SSHKeyStore().loadKeys(from: directory.path)

        XCTAssertEqual(inventory.completePairs.map(\.name), ["id_ed25519"])
        XCTAssertEqual(inventory.completePairs.first?.kind, .completePair)
        XCTAssertEqual(inventory.completePairs.first?.publicKeyPath, pairedPublicURL.path)
        XCTAssertEqual(inventory.completePairs.first?.privateKeyPath, pairedPrivateURL.path)
        XCTAssertEqual(Set(inventory.otherKeys.map(\.name)), ["deploy.pub", "legacy_rsa"])
        XCTAssertNil(inventory.otherKeys.first { $0.name == "broken.pub" })
        XCTAssertNil(inventory.otherKeys.first { $0.name == "notes.txt" })
    }

    func testLoadKeysDoesNotClassifyNonPrivateFileWithMatchingPublicKeyAsPair() throws {
        let directory = try makeTemporaryDirectory()
        let plainURL = directory.appendingPathComponent("not_a_key")
        let matchingPublicURL = directory.appendingPathComponent("not_a_key.pub")

        try "plain text\n".write(to: plainURL, atomically: true, encoding: .utf8)
        try writePublicKey(to: matchingPublicURL)

        let inventory = try SSHKeyStore().loadKeys(from: directory.path)

        XCTAssertTrue(inventory.completePairs.isEmpty)
        XCTAssertNil(inventory.otherKeys.first { $0.name == "not_a_key" })
        XCTAssertEqual(inventory.otherKeys.first?.name, "not_a_key.pub")
        XCTAssertEqual(inventory.otherKeys.first?.kind, .publicKey)
    }

    func testLoadKeysMarksEncryptedPrivateKeysAsPassphraseProtected() throws {
        let directory = try makeTemporaryDirectory()
        let privateURL = directory.appendingPathComponent("encrypted_rsa")
        let publicURL = directory.appendingPathComponent("encrypted_rsa.pub")

        try writePrivateKey(
            to: privateURL,
            marker: "-----BEGIN RSA PRIVATE KEY-----",
            body: """
            Proc-Type: 4,ENCRYPTED
            DEK-Info: AES-128-CBC,00000000000000000000000000000000

            private-key-data
            """
        )
        try writePublicKey(to: publicURL)

        let key = try completePair(named: "encrypted_rsa", in: directory)

        XCTAssertTrue(key.isPassphraseProtected)
    }

    func testUpdateCommentRewritesPublicKeyCommentAndNormalizesWhitespace() throws {
        let directory = try makeTemporaryDirectory()
        let publicURL = directory.appendingPathComponent("id_ed25519.pub")
        try writePublicKey(to: publicURL, comment: "old comment")
        let key = try publicKey(named: "id_ed25519.pub", in: directory)

        try SSHKeyStore().updateComment(for: key, comment: "  new\ncomment  ")

        let contents = try String(contentsOf: publicURL, encoding: .utf8)
        XCTAssertEqual(contents, "ssh-ed25519 \(publicKeyData) new comment\n")
    }

    func testUpdateCommentWithBlankCommentRemovesExistingComment() throws {
        let directory = try makeTemporaryDirectory()
        let publicURL = directory.appendingPathComponent("id_ed25519.pub")
        try writePublicKey(to: publicURL, comment: "old comment")
        let key = try publicKey(named: "id_ed25519.pub", in: directory)

        try SSHKeyStore().updateComment(for: key, comment: " \n ")

        let contents = try String(contentsOf: publicURL, encoding: .utf8)
        XCTAssertEqual(contents, "ssh-ed25519 \(publicKeyData)\n")
    }

    func testSSHConfigWriterRendersHostBlockWithDefaultFourSpaceIndentation() throws {
        let request = SSHConfigHostSaveRequest(
            host: " production ",
            properties: [
                .init(name: "HostName", value: " 192.168.1.10 "),
                .init(name: "User", value: "deploy"),
                .init(name: "Port", value: "2222"),
                .init(name: "IdentityFile", value: "~/.ssh/id_ed25519")
            ]
        )

        let entry = try SSHConfigWriter.renderedEntry(for: request)

        XCTAssertEqual(
            entry,
            """
            Host production
                HostName 192.168.1.10
                User deploy
                Port 2222
                IdentityFile ~/.ssh/id_ed25519

            """
        )
    }

    func testSSHConfigWriterRendersHostBlockWithTwoSpaceIndentation() throws {
        let request = SSHConfigHostSaveRequest(
            host: "production",
            properties: [
                .init(name: "HostName", value: "prod.example.com"),
                .init(name: "User", value: "deploy")
            ]
        )

        let entry = try SSHConfigWriter.renderedEntry(
            for: request,
            propertyIndentation: .twoSpaces
        )

        XCTAssertEqual(
            entry,
            """
            Host production
              HostName prod.example.com
              User deploy

            """
        )
    }

    func testSSHConfigWriterPreservesUserDefinedPropertyOrder() throws {
        let request = SSHConfigHostSaveRequest(
            host: "production",
            properties: [
                .init(name: "User", value: "deploy"),
                .init(name: "HostName", value: "prod.example.com"),
                .init(name: "IdentityFile", value: "~/.ssh/id_prod")
            ]
        )

        let entry = try SSHConfigWriter.renderedEntry(for: request)

        XCTAssertEqual(
            entry,
            """
            Host production
                User deploy
                HostName prod.example.com
                IdentityFile ~/.ssh/id_prod

            """
        )
    }

    func testSSHConfigWriterApplyNormalizesHostIndentationWithSelectedIndentation() throws {
        let directory = try makeTemporaryDirectory()
        let configURL = directory.appendingPathComponent("config")
        try """
        Host first
            HostName first.example.com

        """.write(to: configURL, atomically: true, encoding: .utf8)
        let request = SSHConfigHostSaveRequest(
            host: "second",
            properties: [
                .init(name: "HostName", value: "second.example.com")
            ]
        )

        try SSHConfigWriter.apply(.add(request), in: configURL, propertyIndentation: .twoSpaces)

        let contents = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertEqual(
            contents,
            """
            Host first
              HostName first.example.com

            Host second
              HostName second.example.com

            """
        )
    }

    func testSSHConfigHostSaveRequestWritablePropertiesKeepsOrderAfterFilteringEmptyValues() {
        let request = SSHConfigHostSaveRequest(
            host: "production",
            properties: [
                .init(name: "User", value: "deploy"),
                .init(name: "Port", value: " "),
                .init(name: "HostName", value: "prod.example.com"),
                .init(name: "IdentityFile", value: "~/.ssh/id_prod")
            ]
        )

        XCTAssertEqual(
            request.writableProperties.map(\.name),
            ["User", "HostName", "IdentityFile"]
        )
    }

    func testSSHConfigWriterAppendsHostToEndWithBlankLineBeforeEntry() throws {
        let existingConfig = """
        Host first
            HostName first.example.com
        """
        let newEntry = """
        Host second
            HostName second.example.com

        """

        let config = SSHConfigWriter.append(entry: newEntry, to: existingConfig)

        XCTAssertEqual(
            config,
            """
            Host first
                HostName first.example.com

            Host second
                HostName second.example.com

            """
        )
    }

    func testSSHConfigWriterDoesNotAddExtraBlankLinesWhenFileAlreadyHasSeparator() throws {
        let existingConfig = """
        Host first
            HostName first.example.com


        """
        let newEntry = """
        Host second
            HostName second.example.com

        """

        let config = SSHConfigWriter.append(entry: newEntry, to: existingConfig)

        XCTAssertEqual(
            config,
            """
            Host first
                HostName first.example.com

            Host second
                HostName second.example.com

            """
        )
    }

    func testSSHConfigWriterCreatesMissingSSHDirectoryWithSecurePermissions() throws {
        let parentDirectory = try makeTemporaryDirectory()
        let sshDirectory = parentDirectory.appendingPathComponent("missing-ssh", isDirectory: true)
        let request = SSHConfigHostSaveRequest(
            host: "production",
            properties: [
                .init(name: "HostName", value: "example.com")
            ]
        )

        try SSHConfigWriter.appendHost(request, toDirectory: sshDirectory.path)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(fileManager.fileExists(atPath: sshDirectory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(fileManager.fileExists(atPath: sshDirectory.appendingPathComponent("config").path))

        let permissions = try XCTUnwrap(
            fileManager.attributesOfItem(atPath: sshDirectory.path)[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, 0o700)
    }

    func testSSHConfigWriterApplyAddUsesSnapshotAndRewritesWholeDocument() throws {
        let directory = try makeTemporaryDirectory()
        let configURL = directory.appendingPathComponent("config")
        let request = SSHConfigHostSaveRequest(
            host: "second",
            properties: [
                .init(name: "HostName", value: "second.example.com")
            ]
        )
        try """
        # Shared settings

        Host first
        \tHostName first.example.com
        """.write(to: configURL, atomically: true, encoding: .utf8)

        try SSHConfigWriter.apply(.add(request), in: configURL)

        let config = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertEqual(
            config,
            """
            # Shared settings

            Host first
                HostName first.example.com

            Host second
                HostName second.example.com

            """
        )
    }

    func testSSHConfigWriterDoesNotCreateBackupWhenBackupLimitIsZero() throws {
        let directory = try makeTemporaryDirectory()
        let configURL = directory.appendingPathComponent("config")
        let request = SSHConfigHostSaveRequest(
            host: "second",
            properties: [
                .init(name: "HostName", value: "second.example.com")
            ]
        )
        try """
        Host first
            HostName first.example.com

        """.write(to: configURL, atomically: true, encoding: .utf8)

        try SSHConfigWriter.apply(.add(request), in: configURL, backupLimit: 0)

        XCTAssertFalse(fileManager.fileExists(atPath: configBackupURL(for: configURL, index: 1).path))
    }

    func testSSHConfigWriterCreatesBackupBeforeOverwritingConfig() throws {
        let directory = try makeTemporaryDirectory()
        let configURL = directory.appendingPathComponent("config")
        let originalConfig = """
        Host first
            HostName first.example.com

        """
        let request = SSHConfigHostSaveRequest(
            host: "second",
            properties: [
                .init(name: "HostName", value: "second.example.com")
            ]
        )
        try originalConfig.write(to: configURL, atomically: true, encoding: .utf8)

        try SSHConfigWriter.apply(.add(request), in: configURL, backupLimit: 2)

        let backupContents = try String(contentsOf: configBackupURL(for: configURL, index: 1), encoding: .utf8)
        let updatedContents = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertEqual(backupContents, originalConfig)
        XCTAssertNotEqual(updatedContents, originalConfig)
        XCTAssertFalse(fileManager.fileExists(atPath: configBackupURL(for: configURL, index: 2).path))
    }

    func testSSHConfigWriterRotatesBackupsUpToSelectedLimit() throws {
        let directory = try makeTemporaryDirectory()
        let configURL = directory.appendingPathComponent("config")
        let firstRequest = SSHConfigHostSaveRequest(
            host: "first",
            properties: [
                .init(name: "HostName", value: "first.example.com")
            ]
        )
        let secondRequest = SSHConfigHostSaveRequest(
            host: "second",
            properties: [
                .init(name: "HostName", value: "second.example.com")
            ]
        )
        let thirdRequest = SSHConfigHostSaveRequest(
            host: "third",
            properties: [
                .init(name: "HostName", value: "third.example.com")
            ]
        )
        try "# base\n".write(to: configURL, atomically: true, encoding: .utf8)

        try SSHConfigWriter.apply(.add(firstRequest), in: configURL, backupLimit: 2)
        let afterFirstMutation = try String(contentsOf: configURL, encoding: .utf8)
        try SSHConfigWriter.apply(.add(secondRequest), in: configURL, backupLimit: 2)
        let afterSecondMutation = try String(contentsOf: configURL, encoding: .utf8)
        try SSHConfigWriter.apply(.add(thirdRequest), in: configURL, backupLimit: 2)

        XCTAssertEqual(
            try String(contentsOf: configBackupURL(for: configURL, index: 1), encoding: .utf8),
            afterSecondMutation
        )
        XCTAssertEqual(
            try String(contentsOf: configBackupURL(for: configURL, index: 2), encoding: .utf8),
            afterFirstMutation
        )
        XCTAssertFalse(fileManager.fileExists(atPath: configBackupURL(for: configURL, index: 3).path))
    }

    func testSSHConfigWriterReplacesSelectedHostBlock() throws {
        let existingConfig = """
        Host first
            HostName first.example.com

        Host second
            HostName second.example.com
            User old

        Host third
            HostName third.example.com

        """
        let entry = try configEntry(named: "second", in: existingConfig)
        let request = SSHConfigHostSaveRequest(
            host: "second-renamed",
            properties: [
                .init(name: "HostName", value: "new.example.com"),
                .init(name: "User", value: "deploy"),
                .init(name: "Port", value: "2222")
            ]
        )
        let renderedEntry = try SSHConfigWriter.renderedEntry(for: request)

        let config = try SSHConfigWriter.replace(
            entry: entry,
            with: renderedEntry,
            in: existingConfig,
            configPath: "/tmp/config"
        )

        XCTAssertEqual(
            config,
            """
            Host first
                HostName first.example.com

            Host second-renamed
                HostName new.example.com
                User deploy
                Port 2222

            Host third
                HostName third.example.com

            """
        )
    }

    func testSSHConfigWriterRejectsReplaceWhenFingerprintNoLongerMatchesCurrentFile() throws {
        let originalConfig = """
        Host production
            HostName old.example.com

        """
        let modifiedConfig = """
        Host production
            HostName changed.example.com

        """
        let entry = try configEntry(named: "production", in: originalConfig)
        let request = SSHConfigHostSaveRequest(
            host: "production",
            properties: [
                .init(name: "HostName", value: "new.example.com")
            ]
        )
        let renderedEntry = try SSHConfigWriter.renderedEntry(for: request)

        XCTAssertThrowsError(
            try SSHConfigWriter.replace(
                entry: entry,
                with: renderedEntry,
                in: modifiedConfig,
                configPath: "/tmp/config"
            )
        ) { error in
            XCTAssertEqual(error as? SSHConfigWriterError, .hostBlockNotFound)
        }
    }

    func testSSHConfigWriterReplacePreservesCRLFLineEndings() throws {
        let existingConfig = [
            "Host first",
            "    HostName first.example.com",
            "",
            "Host second",
            "    HostName second.example.com",
            ""
        ].joined(separator: "\r\n")
        let entry = try configEntry(named: "second", in: existingConfig)
        let request = SSHConfigHostSaveRequest(
            host: "second",
            properties: [
                .init(name: "HostName", value: "updated.example.com"),
                .init(name: "User", value: "deploy")
            ]
        )
        let renderedEntry = try SSHConfigWriter.renderedEntry(for: request)

        let config = try SSHConfigWriter.replace(
            entry: entry,
            with: renderedEntry,
            in: existingConfig,
            configPath: "/tmp/config"
        )

        XCTAssertEqual(
            config,
            [
                "Host first",
                "    HostName first.example.com",
                "",
                "Host second",
                "    HostName updated.example.com",
                "    User deploy",
                ""
            ].joined(separator: "\r\n")
        )
    }

    func testSSHConfigWriterDeletesOnlySelectedHostBlockFromMiddle() throws {
        let existingConfig = """
        Host first
            HostName first.example.com

        Host second
            HostName second.example.com
            User deploy

        Host third
            HostName third.example.com

        """
        let entry = try configEntry(named: "second", in: existingConfig)

        let config = try deleteConfigEntry(entry, from: existingConfig)

        XCTAssertEqual(
            config,
            """
            Host first
                HostName first.example.com

            Host third
                HostName third.example.com

            """
        )
    }

    func testSSHConfigWriterDeletesFirstHostBlockAndPreservesFollowingComment() throws {
        let existingConfig = """
        Host first
            HostName first.example.com
        # shared comment

        Host second
            HostName second.example.com

        """
        let entry = try configEntry(named: "first", in: existingConfig)

        let config = try deleteConfigEntry(entry, from: existingConfig)

        XCTAssertEqual(
            config,
            """
            # shared comment

            Host second
                HostName second.example.com

            """
        )
    }

    func testSSHConfigWriterDeletesLastHostBlockAndPreservesLeadingCommentAndSpacing() throws {
        let existingConfig = """
        # global comment

        Host first
            HostName first.example.com

        Host second
            HostName second.example.com
            User deploy
        """
        let entry = try configEntry(named: "second", in: existingConfig)

        let config = try deleteConfigEntry(entry, from: existingConfig)

        XCTAssertEqual(
            config,
            """
            # global comment

            Host first
                HostName first.example.com

            """
        )
    }

    func testSSHConfigWriterNormalizesPropertyIndentationAndPreservesCRLFCommentsAndTrailingSpacesOutsideDeletedBlock() throws {
        let existingConfig = [
            "Host first",
            "\tHostName first.example.com",
            "",
            "# keep this comment  ",
            "",
            "Host second",
            "\tHostName second.example.com",
            "\tUser deploy",
            "",
            "Host third",
            "    HostName third.example.com  ",
            "\tIdentityFile ~/.ssh/id_third"
        ].joined(separator: "\r\n") + "\r\n"
        let entry = try configEntry(named: "second", in: existingConfig)

        let config = try deleteConfigEntry(entry, from: existingConfig)

        XCTAssertEqual(
            config,
            [
                "Host first",
                "    HostName first.example.com",
                "",
                "# keep this comment  ",
                "",
                "Host third",
                "    HostName third.example.com  ",
                "    IdentityFile ~/.ssh/id_third"
            ].joined(separator: "\r\n") + "\r\n"
        )
    }

    func testSSHConfigWriterCollapsesExtraBlankLinesAfterDeletingMiddleBlock() throws {
        let existingConfig = """
        Host first
            HostName first.example.com


        Host second
            HostName second.example.com


        Host third
            HostName third.example.com

        """
        let entry = try configEntry(named: "second", in: existingConfig)

        let config = try deleteConfigEntry(entry, from: existingConfig)

        XCTAssertEqual(
            config,
            """
            Host first
                HostName first.example.com

            Host third
                HostName third.example.com

            """
        )
    }

    func testSSHConfigWriterDeletesOnlyEntryMatchedByFingerprintWhenHostNamesRepeat() throws {
        let existingConfig = """
        Host duplicate
            HostName first.example.com

        Host duplicate
            HostName second.example.com

        """
        let snapshot = SSHConfigParser.parseDocument(existingConfig, configPath: "/tmp/config")
        let entry = try XCTUnwrap(snapshot.entries.last)

        let config = try deleteConfigEntry(entry, from: existingConfig)

        XCTAssertEqual(
            config,
            """
            Host duplicate
                HostName first.example.com

            """
        )
    }

    func testSSHConfigWriterUsesLineNumberToDeleteOneOfTwoIdenticalHostBlocks() throws {
        let existingConfig = """
        Host duplicate
            HostName same.example.com

        Host duplicate
            HostName same.example.com

        """
        let snapshot = SSHConfigParser.parseDocument(existingConfig, configPath: "/tmp/config")
        let entry = try XCTUnwrap(snapshot.entries.last)

        let config = try deleteConfigEntry(entry, from: existingConfig)

        XCTAssertEqual(
            config,
            """
            Host duplicate
                HostName same.example.com

            """
        )
    }

    func testSSHConfigWriterRejectsDeleteWhenFingerprintNoLongerMatchesCurrentFile() throws {
        let originalConfig = """
        Host production
            HostName old.example.com

        """
        let modifiedConfig = """
        Host production
            HostName changed.example.com

        """
        let entry = try configEntry(named: "production", in: originalConfig)

        XCTAssertThrowsError(try deleteConfigEntry(entry, from: modifiedConfig)) { error in
            XCTAssertEqual(error as? SSHConfigWriterError, .hostBlockNotFound)
        }
    }

    func testSSHConfigWriterRejectsLineBreaksInPropertyValues() throws {
        let request = SSHConfigHostSaveRequest(
            host: "production",
            properties: [
                .init(name: "ProxyCommand", value: "ssh jump\nmalformed")
            ]
        )

        XCTAssertThrowsError(try SSHConfigWriter.renderedEntry(for: request)) { error in
            XCTAssertEqual(error as? SSHConfigWriterError, .invalidPropertyValue("ProxyCommand"))
        }
    }

    func testUpdateCommentRejectsPrivateOnlyKeys() throws {
        let directory = try makeTemporaryDirectory()
        let privateURL = directory.appendingPathComponent("id_ed25519")
        try writePrivateKey(to: privateURL)
        let key = try privateKey(named: "id_ed25519", in: directory)

        XCTAssertThrowsError(try SSHKeyStore().updateComment(for: key, comment: "new")) { error in
            guard case SSHKeyStoreError.commentRequiresPublicKey = error else {
                XCTFail("Expected commentRequiresPublicKey, got \(error)")
                return
            }
        }
    }

    func testChangePassphraseRunsSSHKeygenWithoutSecretsInArguments() throws {
        let directory = try makeTemporaryDirectory()
        let privateURL = directory.appendingPathComponent("id_ed25519")
        let publicURL = directory.appendingPathComponent("id_ed25519.pub")
        let argumentsURL = directory.appendingPathComponent("ssh-keygen-args.txt")
        let inputURL = directory.appendingPathComponent("ssh-keygen-input.txt")
        let sshKeygenURL = try writePassphraseChangingSSHKeygenScript(
            in: directory,
            argumentsURL: argumentsURL,
            inputURL: inputURL
        )
        try writePrivateKey(to: privateURL)
        try writePublicKey(to: publicURL)
        let key = try completePair(named: "id_ed25519", in: directory)

        try SSHKeyStore(sshKeygenURL: sshKeygenURL).changePassphrase(
            for: key,
            oldPassphrase: "old secret",
            newPassphrase: "new secret"
        )

        let arguments = try String(contentsOf: argumentsURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        XCTAssertEqual(
            arguments,
            ["-p", "-f", privateURL.path]
        )

        let inputLines = try String(contentsOf: inputURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        XCTAssertEqual(inputLines, ["old secret", "new secret", "new secret"])
    }

    func testChangePassphraseRejectsPublicOnlyKeys() throws {
        let directory = try makeTemporaryDirectory()
        let publicURL = directory.appendingPathComponent("id_ed25519.pub")
        try writePublicKey(to: publicURL)
        let key = try publicKey(named: "id_ed25519.pub", in: directory)

        XCTAssertThrowsError(
            try SSHKeyStore().changePassphrase(
                for: key,
                oldPassphrase: "old",
                newPassphrase: "new"
            )
        ) { error in
            guard case SSHKeyStoreError.passphraseChangeRequiresPrivateKey = error else {
                XCTFail("Expected passphraseChangeRequiresPrivateKey, got \(error)")
                return
            }
        }
    }

    func testDeleteCompletePairRemovesPrivateAndPublicFiles() throws {
        let directory = try makeTemporaryDirectory()
        let privateURL = directory.appendingPathComponent("id_ed25519")
        let publicURL = directory.appendingPathComponent("id_ed25519.pub")
        try writePrivateKey(to: privateURL)
        try writePublicKey(to: publicURL)
        let key = try completePair(named: "id_ed25519", in: directory)

        try SSHKeyStore().delete(key)

        XCTAssertFalse(fileManager.fileExists(atPath: privateURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: publicURL.path))
    }

    func testRenameCompletePairMovesBothFilesAndUpdatesConfigReferences() throws {
        let directory = try makeTemporaryDirectory()
        let privateURL = directory.appendingPathComponent("id_ed25519")
        let publicURL = directory.appendingPathComponent("id_ed25519.pub")
        let configURL = directory.appendingPathComponent("config")
        try writePrivateKey(to: privateURL)
        try writePublicKey(to: publicURL)
        try """
        Host production
            HostName example.com
            IdentityFile \(privateURL.path)
        Host unrelated
            IdentityFile \(privateURL.path)_work
        # comment path: \(privateURL.path)
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let key = try completePair(named: "id_ed25519", in: directory)

        let newID = try SSHKeyStore().rename(key, to: "prod_ed25519")

        let renamedPrivateURL = directory.appendingPathComponent("prod_ed25519")
        let renamedPublicURL = directory.appendingPathComponent("prod_ed25519.pub")
        XCTAssertEqual(newID, renamedPrivateURL.path)
        XCTAssertFalse(fileManager.fileExists(atPath: privateURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: publicURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: renamedPrivateURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: renamedPublicURL.path))

        let config = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(config.contains("IdentityFile \(renamedPrivateURL.path)"))
        XCTAssertTrue(config.contains("IdentityFile \(privateURL.path)_work"))
        XCTAssertTrue(config.contains("# comment path: \(privateURL.path)"))
        XCTAssertTrue(config.contains(renamedPrivateURL.path))
        XCTAssertFalse(config.contains(renamedPublicURL.path))
    }

    func testRenameRejectsInvalidNameAndLeavesFilesInPlace() throws {
        let directory = try makeTemporaryDirectory()
        let privateURL = directory.appendingPathComponent("id_ed25519")
        let publicURL = directory.appendingPathComponent("id_ed25519.pub")
        try writePrivateKey(to: privateURL)
        try writePublicKey(to: publicURL)
        let key = try completePair(named: "id_ed25519", in: directory)

        XCTAssertThrowsError(try SSHKeyStore().rename(key, to: "../prod")) { error in
            guard case SSHKeyStoreError.invalidKeyName = error else {
                XCTFail("Expected invalidKeyName, got \(error)")
                return
            }
        }

        XCTAssertTrue(fileManager.fileExists(atPath: privateURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: publicURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: directory.appendingPathComponent("prod").path))
    }

    func testRenameRejectsExistingTargetAndLeavesOriginalFilesInPlace() throws {
        let directory = try makeTemporaryDirectory()
        let privateURL = directory.appendingPathComponent("id_ed25519")
        let publicURL = directory.appendingPathComponent("id_ed25519.pub")
        let existingURL = directory.appendingPathComponent("prod_ed25519")
        try writePrivateKey(to: privateURL)
        try writePublicKey(to: publicURL)
        try writePrivateKey(to: existingURL)
        let key = try completePair(named: "id_ed25519", in: directory)

        XCTAssertThrowsError(try SSHKeyStore().rename(key, to: "prod_ed25519")) { error in
            guard case SSHKeyStoreError.keyNameAlreadyExists("prod_ed25519") = error else {
                XCTFail("Expected keyNameAlreadyExists, got \(error)")
                return
            }
        }

        XCTAssertTrue(fileManager.fileExists(atPath: privateURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: publicURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: existingURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: directory.appendingPathComponent("prod_ed25519.pub").path))
    }

    func testDuplicateCompletePairCopiesBothFilesWithoutMutatingSource() throws {
        let directory = try makeTemporaryDirectory()
        let privateURL = directory.appendingPathComponent("id_ed25519")
        let publicURL = directory.appendingPathComponent("id_ed25519.pub")
        try writePrivateKey(to: privateURL)
        try writePublicKey(to: publicURL, comment: "original")
        let key = try completePair(named: "id_ed25519", in: directory)

        let newID = try SSHKeyStore().duplicate(key, to: "id_ed25519_copy")

        let copiedPrivateURL = directory.appendingPathComponent("id_ed25519_copy")
        let copiedPublicURL = directory.appendingPathComponent("id_ed25519_copy.pub")
        XCTAssertEqual(newID, copiedPrivateURL.path)
        XCTAssertEqual(
            try String(contentsOf: copiedPrivateURL, encoding: .utf8),
            try String(contentsOf: privateURL, encoding: .utf8)
        )
        XCTAssertEqual(
            try String(contentsOf: copiedPublicURL, encoding: .utf8),
            try String(contentsOf: publicURL, encoding: .utf8)
        )
        XCTAssertTrue(fileManager.fileExists(atPath: privateURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: publicURL.path))
    }

    func testDuplicateRejectsExistingTargetAndDoesNotCreatePartialPair() throws {
        let directory = try makeTemporaryDirectory()
        let privateURL = directory.appendingPathComponent("id_ed25519")
        let publicURL = directory.appendingPathComponent("id_ed25519.pub")
        let existingPublicURL = directory.appendingPathComponent("id_ed25519_copy.pub")
        try writePrivateKey(to: privateURL)
        try writePublicKey(to: publicURL)
        try writePublicKey(to: existingPublicURL, comment: "existing")
        let key = try completePair(named: "id_ed25519", in: directory)

        XCTAssertThrowsError(try SSHKeyStore().duplicate(key, to: "id_ed25519_copy")) { error in
            guard case SSHKeyStoreError.keyNameAlreadyExists("id_ed25519_copy.pub") = error else {
                XCTFail("Expected keyNameAlreadyExists, got \(error)")
                return
            }
        }

        XCTAssertFalse(fileManager.fileExists(atPath: directory.appendingPathComponent("id_ed25519_copy").path))
        XCTAssertTrue(fileManager.fileExists(atPath: existingPublicURL.path))
    }

    func testRenamePublicOnlyKeyAppendsPubExtensionWhenNeeded() throws {
        let directory = try makeTemporaryDirectory()
        let publicURL = directory.appendingPathComponent("deploy.pub")
        try writePublicKey(to: publicURL)
        let key = try publicKey(named: "deploy.pub", in: directory)

        let newID = try SSHKeyStore().rename(key, to: "production")

        let renamedPublicURL = directory.appendingPathComponent("production.pub")
        XCTAssertEqual(newID, renamedPublicURL.path)
        XCTAssertFalse(fileManager.fileExists(atPath: publicURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: renamedPublicURL.path))
    }

    func testGenerateKeyCreatesED25519PairWithComment() throws {
        let directory = try makeTemporaryDirectory()
        let request = SSHKeyGenerationRequest(
            fileName: "id_ed25519",
            keyType: .ed25519,
            comment: "work laptop",
            passphrase: nil
        )

        let generatedID = try SSHKeyStore().generateKey(request, in: directory.path)

        let privateURL = directory.appendingPathComponent("id_ed25519")
        let publicURL = directory.appendingPathComponent("id_ed25519.pub")
        XCTAssertEqual(generatedID, privateURL.path)
        XCTAssertTrue(fileManager.fileExists(atPath: privateURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: publicURL.path))
        XCTAssertTrue(try String(contentsOf: publicURL, encoding: .utf8).contains("work laptop"))

        let inventory = try SSHKeyStore().loadKeys(from: directory.path)
        let generatedKey = try XCTUnwrap(inventory.completePairs.first { $0.id == generatedID })
        XCTAssertEqual(generatedKey.kind, .completePair)
        XCTAssertEqual(generatedKey.type, "ED25519")
        XCTAssertEqual(generatedKey.comment, "work laptop")
    }

    func testGenerateKeyPassphraseIsSentViaPseudoTerminalInsteadOfArguments() throws {
        let directory = try makeTemporaryDirectory()
        let privateURL = directory.appendingPathComponent("id_ed25519")
        let argumentsURL = directory.appendingPathComponent("ssh-keygen-generate-args.txt")
        let inputURL = directory.appendingPathComponent("ssh-keygen-generate-input.txt")
        let sshKeygenURL = try writeGeneratingSSHKeygenScript(
            in: directory,
            argumentsURL: argumentsURL,
            inputURL: inputURL
        )
        let request = SSHKeyGenerationRequest(
            fileName: "id_ed25519",
            keyType: .ed25519,
            comment: "secure comment",
            passphrase: "very secret"
        )

        let generatedID = try SSHKeyStore(sshKeygenURL: sshKeygenURL).generateKey(request, in: directory.path)

        XCTAssertEqual(generatedID, privateURL.path)
        let arguments = try String(contentsOf: argumentsURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        XCTAssertEqual(
            arguments,
            ["-q", "-t", "ed25519", "-f", privateURL.path, "-C", "secure comment"]
        )

        let inputLines = try String(contentsOf: inputURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        XCTAssertEqual(inputLines, ["very secret", "very secret"])
    }

    func testGenerateKeyRejectsExistingTargetAndLeavesOriginalFilesInPlace() throws {
        let directory = try makeTemporaryDirectory()
        let privateURL = directory.appendingPathComponent("id_ed25519")
        try writePrivateKey(to: privateURL)

        let request = SSHKeyGenerationRequest(
            fileName: "id_ed25519",
            keyType: .ed25519,
            comment: "new",
            passphrase: nil
        )

        XCTAssertThrowsError(try SSHKeyStore().generateKey(request, in: directory.path)) { error in
            guard case SSHKeyStoreError.keyNameAlreadyExists("id_ed25519") = error else {
                XCTFail("Expected keyNameAlreadyExists, got \(error)")
                return
            }
        }

        XCTAssertEqual(
            try String(contentsOf: privateURL, encoding: .utf8),
            "-----BEGIN OPENSSH PRIVATE KEY-----\nprivate-key-data\n-----END OPENSSH PRIVATE KEY-----\n"
        )
        XCTAssertFalse(fileManager.fileExists(atPath: directory.appendingPathComponent("id_ed25519.pub").path))
    }

    func testGenerateKeyRejectsInvalidName() throws {
        let directory = try makeTemporaryDirectory()
        let request = SSHKeyGenerationRequest(
            fileName: "id_ed25519.pub",
            keyType: .ed25519,
            comment: "",
            passphrase: nil
        )

        XCTAssertThrowsError(try SSHKeyStore().generateKey(request, in: directory.path)) { error in
            guard case SSHKeyStoreError.invalidKeyName = error else {
                XCTFail("Expected invalidKeyName, got \(error)")
                return
            }
        }
    }

    func testGenerateKeyRemovesPartialFilesWhenSSHKeygenFails() throws {
        let directory = try makeTemporaryDirectory()
        let failingSSHKeygenURL = try writeFailingSSHKeygenScript(in: directory)
        let request = SSHKeyGenerationRequest(
            fileName: "partial_key",
            keyType: .ed25519,
            comment: "partial",
            passphrase: nil
        )

        XCTAssertThrowsError(
            try SSHKeyStore(sshKeygenURL: failingSSHKeygenURL).generateKey(request, in: directory.path)
        ) { error in
            guard case SSHKeyStoreError.keyGenerationFailed(let message) = error else {
                XCTFail("Expected keyGenerationFailed, got \(error)")
                return
            }

            XCTAssertTrue(message.contains("simulated failure"))
        }

        XCTAssertFalse(fileManager.fileExists(atPath: directory.appendingPathComponent("partial_key").path))
        XCTAssertFalse(fileManager.fileExists(atPath: directory.appendingPathComponent("partial_key.pub").path))
    }

    func testGenerateKeyFailsClearlyWhenSSHKeygenIsMissing() throws {
        let directory = try makeTemporaryDirectory()
        let missingSSHKeygenURL = directory.appendingPathComponent("missing-ssh-keygen")
        let request = SSHKeyGenerationRequest(
            fileName: "id_missing_tool",
            keyType: .ed25519,
            comment: "missing",
            passphrase: nil
        )

        XCTAssertThrowsError(
            try SSHKeyStore(sshKeygenURL: missingSSHKeygenURL).generateKey(request, in: directory.path)
        ) { error in
            guard case SSHKeyStoreError.sshKeygenUnavailable(.missing(let path)) = error else {
                XCTFail("Expected sshKeygenUnavailable missing, got \(error)")
                return
            }

            XCTAssertEqual(path, normalizedExternalToolPath(missingSSHKeygenURL.path))
            XCTAssertTrue(error.localizedDescription.contains("ssh-keygen was not found"))
        }

        XCTAssertFalse(fileManager.fileExists(atPath: directory.appendingPathComponent("id_missing_tool").path))
        XCTAssertFalse(fileManager.fileExists(atPath: directory.appendingPathComponent("id_missing_tool.pub").path))
    }

    func testGenerateKeyFailsClearlyWhenSSHKeygenIsNotExecutable() throws {
        let directory = try makeTemporaryDirectory()
        let nonExecutableSSHKeygenURL = try writeNoopScript(named: "ssh-keygen", in: directory, permissions: 0o644)
        let request = SSHKeyGenerationRequest(
            fileName: "id_non_executable_tool",
            keyType: .ed25519,
            comment: "not executable",
            passphrase: nil
        )

        XCTAssertThrowsError(
            try SSHKeyStore(sshKeygenURL: nonExecutableSSHKeygenURL).generateKey(request, in: directory.path)
        ) { error in
            guard case SSHKeyStoreError.sshKeygenUnavailable(.notExecutable(let path)) = error else {
                XCTFail("Expected sshKeygenUnavailable notExecutable, got \(error)")
                return
            }

            XCTAssertEqual(path, normalizedExternalToolPath(nonExecutableSSHKeygenURL.path))
            XCTAssertTrue(error.localizedDescription.contains("is not executable"))
        }

        XCTAssertFalse(fileManager.fileExists(atPath: directory.appendingPathComponent("id_non_executable_tool").path))
        XCTAssertFalse(fileManager.fileExists(atPath: directory.appendingPathComponent("id_non_executable_tool.pub").path))
    }

    func testChangePassphraseFailsClearlyWhenSSHKeygenIsMissing() throws {
        let directory = try makeTemporaryDirectory()
        let privateURL = directory.appendingPathComponent("id_ed25519")
        let publicURL = directory.appendingPathComponent("id_ed25519.pub")
        let missingSSHKeygenURL = directory.appendingPathComponent("missing-ssh-keygen")
        try writePrivateKey(to: privateURL)
        try writePublicKey(to: publicURL)
        let key = try completePair(named: "id_ed25519", in: directory)

        XCTAssertThrowsError(
            try SSHKeyStore(sshKeygenURL: missingSSHKeygenURL).changePassphrase(
                for: key,
                oldPassphrase: "old",
                newPassphrase: "new"
            )
        ) { error in
            guard case SSHKeyStoreError.sshKeygenUnavailable(.missing(let path)) = error else {
                XCTFail("Expected sshKeygenUnavailable missing, got \(error)")
                return
            }

            XCTAssertEqual(path, normalizedExternalToolPath(missingSSHKeygenURL.path))
            XCTAssertTrue(error.localizedDescription.contains("ssh-keygen was not found"))
        }
    }

    func testAvailableKeyNameSuggestsFirstFreeSuffix() throws {
        let directory = try makeTemporaryDirectory()
        try writePrivateKey(to: directory.appendingPathComponent("id_ed25519"))

        let availableName = try SSHKeyStore().availableKeyName(for: "id_ed25519", in: directory.path)

        XCTAssertEqual(availableName, "id_ed25519_1")
    }

    func testAvailableKeyNameSkipsOccupiedSuffixes() throws {
        let directory = try makeTemporaryDirectory()
        try writePrivateKey(to: directory.appendingPathComponent("id_ed25519"))
        try writePrivateKey(to: directory.appendingPathComponent("id_ed25519_1"))

        let availableName = try SSHKeyStore().availableKeyName(for: "id_ed25519", in: directory.path)

        XCTAssertEqual(availableName, "id_ed25519_2")
    }

    @MainActor
    func testDeleteSelectedConfigEntryReloadsEntriesSelectsNextEntryAndShowsNotification() async throws {
        let initialEntries = [
            makeConfigEntry(host: "first", lineNumber: 1, fingerprint: "first"),
            makeConfigEntry(host: "second", lineNumber: 4, fingerprint: "second"),
            makeConfigEntry(host: "third", lineNumber: 7, fingerprint: "third")
        ]
        let updatedEntries = [
            makeConfigEntry(host: "first", lineNumber: 1, fingerprint: "first"),
            makeConfigEntry(host: "third", lineNumber: 4, fingerprint: "third")
        ]
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        let configStorage = FakeSSHConfigStorage(loadEntriesResult: updatedEntries)
        let model = AppModel(
            configEntries: initialEntries,
            dependencies: AppModelDependencies(
                keyStorage: SSHKeyStorage(keyStore: SSHKeyStore()),
                configStorage: configStorage,
                keyActions: SSHKeyFileActions(),
                preferences: preferences
            )
        )
        let expectedSelectedID = initialEntries[1].id
        model.selectedConfigEntryID = expectedSelectedID

        try await model.deleteSelectedConfigEntry()

        let deletedHosts = await configStorage.deletedHosts
        let configHosts = model.configEntries.map { $0.host }
        let selectedConfigEntryID = model.selectedConfigEntryID
        let updatedSelectedID = updatedEntries[1].id
        let notificationMessage = model.notification?.message
        let configErrorMessage = model.configErrorMessage
        XCTAssertEqual(deletedHosts, ["second"])
        XCTAssertEqual(configHosts, ["first", "third"])
        XCTAssertEqual(selectedConfigEntryID, updatedSelectedID)
        XCTAssertEqual(notificationMessage, "Deleted SSH config host second")
        XCTAssertNil(configErrorMessage)
    }

    @MainActor
    func testDeleteSelectedConfigEntryClearsSelectionWhenLastEntryRemoved() async throws {
        let initialEntry = makeConfigEntry(host: "solo", lineNumber: 1, fingerprint: "solo")
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        let configStorage = FakeSSHConfigStorage(loadEntriesResult: [])
        let model = AppModel(
            configEntries: [initialEntry],
            dependencies: AppModelDependencies(
                keyStorage: SSHKeyStorage(keyStore: SSHKeyStore()),
                configStorage: configStorage,
                keyActions: SSHKeyFileActions(),
                preferences: preferences
            )
        )
        let initialEntryID = initialEntry.id
        model.selectedConfigEntryID = initialEntryID

        try await model.deleteSelectedConfigEntry()

        let configEntries = model.configEntries
        let selectedConfigEntryID = model.selectedConfigEntryID
        let notificationMessage = model.notification?.message
        XCTAssertTrue(configEntries.isEmpty)
        XCTAssertNil(selectedConfigEntryID)
        XCTAssertEqual(notificationMessage, "Deleted SSH config host solo")
    }

    func testIdentityFileOptionsIncludeAllPrivateKeysDeduplicateAndUseTildePaths() {
        let sharedPath = "/Users/tester/.ssh/id_shared"
        let options = SSHConfigIdentityFileCatalog.options(
            keys: [
                makeKeyItem(name: "id_work", privateKeyPath: "/Users/tester/.ssh/id_work"),
                makeKeyItem(name: "shared_pair", privateKeyPath: sharedPath)
            ],
            otherKeys: [
                makeKeyItem(name: "legacy_rsa", kind: .privateKey, publicKeyPath: nil, privateKeyPath: "/opt/keys/legacy_rsa"),
                makeKeyItem(name: "shared_standalone", kind: .privateKey, publicKeyPath: nil, privateKeyPath: sharedPath),
                makeKeyItem(name: "public_only", kind: .publicKey, publicKeyPath: "/Users/tester/.ssh/public_only.pub", privateKeyPath: nil)
            ],
            homeDirectoryPath: "/Users/tester"
        )

        XCTAssertEqual(
            options,
            [
                SSHConfigIdentityFileOption(keyName: "id_work", value: "~/.ssh/id_work"),
                SSHConfigIdentityFileOption(keyName: "legacy_rsa", value: "/opt/keys/legacy_rsa"),
                SSHConfigIdentityFileOption(keyName: "shared_pair", value: "~/.ssh/id_shared")
            ]
        )
    }

    func testIdentityFilePickerSupportMatchesOnlyIdentityFileProperties() {
        XCTAssertTrue(SSHConfigHostPropertyDefinition.isIdentityFilePropertyName("IdentityFile"))
        XCTAssertTrue(SSHConfigHostPropertyDefinition.isIdentityFilePropertyName(" identityfile "))
        XCTAssertFalse(SSHConfigHostPropertyDefinition.isIdentityFilePropertyName("CertificateFile"))
    }

    func testIdentityFilePickerMenuTitleIncludesPathForDuplicateKeyNames() {
        let duplicateOptions = [
            SSHConfigIdentityFileOption(keyName: "id_prod", value: "~/.ssh/id_prod"),
            SSHConfigIdentityFileOption(keyName: "id_prod", value: "/opt/keys/id_prod")
        ]

        XCTAssertEqual(
            SSHConfigIdentityFileMenuPresentation.menuTitle(
                for: duplicateOptions[0],
                allOptions: duplicateOptions
            ),
            "id_prod • ~/.ssh/id_prod"
        )
        XCTAssertEqual(
            SSHConfigIdentityFileMenuPresentation.menuTitle(
                for: SSHConfigIdentityFileOption(keyName: "id_unique", value: "~/.ssh/id_unique"),
                allOptions: duplicateOptions + [SSHConfigIdentityFileOption(keyName: "id_unique", value: "~/.ssh/id_unique")]
            ),
            "id_unique"
        )
    }

    @MainActor
    func testRenameSelectedKeyPropagatesFailureAndKeepsErrorMessage() async throws {
        let key = makeKeyItem(name: "id_ed25519")
        let keyStorage = FakeSSHKeyStorage(renameError: SSHKeyStoreError.invalidKeyName)
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        let model = AppModel(
            keys: [key],
            dependencies: AppModelDependencies(
                keyStorage: keyStorage,
                configStorage: SSHConfigStorage(),
                keyActions: SSHKeyFileActions(),
                preferences: preferences
            )
        )
        let selectedKeyID = key.id
        let keyName = key.name
        model.selectedKeyID = selectedKeyID

        do {
            try await model.renameSelectedKey(to: "../prod")
            XCTFail("Expected renameSelectedKey to throw")
        } catch {
            guard case SSHKeyStoreError.invalidKeyName = error else {
                XCTFail("Expected invalidKeyName, got \(error)")
                return
            }
        }

        let keyErrorMessage = model.keyErrorMessage
        XCTAssertEqual(keyErrorMessage, "Unable to rename \(keyName): Use a file name without path separators.")
    }

    @MainActor
    func testDuplicateSelectedKeyPropagatesFailureAndKeepsErrorMessage() async {
        let key = makeKeyItem(name: "id_ed25519")
        let keyStorage = FakeSSHKeyStorage(duplicateError: SSHKeyStoreError.keyNameAlreadyExists("id_ed25519_copy"))
        let model = AppModel(
            keys: [key],
            dependencies: AppModelDependencies(
                keyStorage: keyStorage,
                configStorage: SSHConfigStorage(),
                keyActions: SSHKeyFileActions()
            )
        )
        let selectedKeyID = key.id
        let keyName = key.name
        model.selectedKeyID = selectedKeyID

        do {
            try await model.duplicateSelectedKey(to: "id_ed25519_copy")
            XCTFail("Expected duplicateSelectedKey to throw")
        } catch {
            guard case SSHKeyStoreError.keyNameAlreadyExists("id_ed25519_copy") = error else {
                XCTFail("Expected keyNameAlreadyExists, got \(error)")
                return
            }
        }

        let keyErrorMessage = model.keyErrorMessage
        XCTAssertEqual(
            keyErrorMessage,
            "Unable to duplicate \(keyName): A key file named id_ed25519_copy already exists."
        )
    }

    func testAppPreferencesUsesDefaultSSHDirectoryWhenValueIsMissing() throws {
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = AppPreferences(userDefaults: userDefaults)

        XCTAssertEqual(preferences.sshDirectoryPath, SSHWorkspacePath.defaultDirectoryPath)
    }

    func testAppPreferencesPersistsNormalizedSSHDirectory() throws {
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = AppPreferences(userDefaults: userDefaults)
        let expectedPath = SSHWorkspacePath.normalizeDirectoryPath("~/custom-ssh/")

        preferences.setSSHDirectoryPath("~/custom-ssh/")

        XCTAssertEqual(preferences.sshDirectoryPath, expectedPath)
    }

    func testAppPreferencesUsesDefaultSSHKeygenPathWhenValueIsMissing() throws {
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = AppPreferences(userDefaults: userDefaults)

        XCTAssertEqual(preferences.sshKeygenPath, ExternalTool.sshKeygen.defaultPath)
    }

    func testAppPreferencesPersistsNormalizedSSHKeygenPath() throws {
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = AppPreferences(userDefaults: userDefaults)
        let expectedPath = ExternalToolPath.normalizeExecutablePath(
            "~/custom-bin/ssh-keygen",
            defaultPath: ExternalTool.sshKeygen.defaultPath
        )

        preferences.setSSHKeygenPath("  ~/custom-bin/ssh-keygen  ")

        XCTAssertEqual(preferences.sshKeygenPath, expectedPath)
    }

    func testAppPreferencesResetsEmptySSHKeygenPathToDefault() throws {
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = AppPreferences(userDefaults: userDefaults)

        preferences.setSSHKeygenPath("")

        XCTAssertEqual(preferences.sshKeygenPath, ExternalTool.sshKeygen.defaultPath)
    }

    func testAppPreferencesUsesDefaultHostPropertyIndentationWhenValueIsMissing() throws {
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = AppPreferences(userDefaults: userDefaults)

        XCTAssertEqual(preferences.hostPropertyIndentation, .fourSpaces)
    }

    func testAppPreferencesPersistsHostPropertyIndentation() throws {
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = AppPreferences(userDefaults: userDefaults)

        preferences.setHostPropertyIndentation(.twoSpaces)

        XCTAssertEqual(preferences.hostPropertyIndentation, .twoSpaces)
    }

    func testAppPreferencesUsesZeroConfigBackupLimitByDefault() throws {
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = AppPreferences(userDefaults: userDefaults)

        XCTAssertEqual(preferences.configBackupLimit, 0)
    }

    func testAppPreferencesPersistsClampedConfigBackupLimit() throws {
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = AppPreferences(userDefaults: userDefaults)

        preferences.setConfigBackupLimit(8)

        XCTAssertEqual(preferences.configBackupLimit, 5)
    }

    func testAppPreferencesPersistsReadOnlyMode() throws {
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = AppPreferences(userDefaults: userDefaults)
        XCTAssertFalse(preferences.isReadOnlyModeEnabled)

        preferences.setReadOnlyModeEnabled(true)

        XCTAssertTrue(preferences.isReadOnlyModeEnabled)
    }

    func testAppPreferencesPersistsMinimizeToMenuBar() throws {
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = AppPreferences(userDefaults: userDefaults)
        XCTAssertFalse(preferences.isMinimizeToMenuBarEnabled)

        preferences.setMinimizeToMenuBarEnabled(true)

        XCTAssertTrue(preferences.isMinimizeToMenuBarEnabled)
    }

    @MainActor
    func testAppModelPersistsHostPropertyIndentationChange() throws {
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        let model = AppModel(
            dependencies: AppModelDependencies(
                keyStorage: RecordingSSHKeyStorage(),
                configStorage: RecordingSSHConfigStorage(),
                keyActions: SSHKeyFileActions(),
                preferences: preferences
            )
        )

        model.hostPropertyIndentation = .twoSpaces

        XCTAssertEqual(preferences.hostPropertyIndentation, .twoSpaces)
    }

    @MainActor
    func testAppModelPersistsConfigBackupLimitChange() throws {
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        let model = AppModel(
            dependencies: AppModelDependencies(
                keyStorage: RecordingSSHKeyStorage(),
                configStorage: RecordingSSHConfigStorage(),
                keyActions: SSHKeyFileActions(),
                preferences: preferences
            )
        )

        model.configBackupLimit = 3

        XCTAssertEqual(preferences.configBackupLimit, 3)
    }

    @MainActor
    func testAppModelPersistsReadOnlyModeChange() throws {
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        let model = AppModel(
            dependencies: AppModelDependencies(
                keyStorage: RecordingSSHKeyStorage(),
                configStorage: RecordingSSHConfigStorage(),
                keyActions: SSHKeyFileActions(),
                preferences: preferences
            )
        )

        model.isReadOnlyModeEnabled = true

        XCTAssertTrue(preferences.isReadOnlyModeEnabled)
    }

    @MainActor
    func testAppModelPersistsMinimizeToMenuBarChange() throws {
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        let model = AppModel(
            dependencies: AppModelDependencies(
                keyStorage: RecordingSSHKeyStorage(),
                configStorage: RecordingSSHConfigStorage(),
                keyActions: SSHKeyFileActions(),
                preferences: preferences
            )
        )

        model.isMinimizeToMenuBarEnabled = true

        XCTAssertTrue(preferences.isMinimizeToMenuBarEnabled)
    }

    @MainActor
    func testReadOnlyModeBlocksKeyDeletionBeforeStorageMutation() async throws {
        let key = makeKeyItem(name: "id_ed25519")
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        preferences.setReadOnlyModeEnabled(true)
        let model = AppModel(
            keys: [key],
            dependencies: AppModelDependencies(
                keyStorage: FakeSSHKeyStorage(),
                configStorage: RecordingSSHConfigStorage(),
                keyActions: SSHKeyFileActions(),
                preferences: preferences
            )
        )
        model.selectedKeyID = key.id

        do {
            try await model.deleteSelectedKey()
            XCTFail("Expected deleteSelectedKey to throw")
        } catch {
            XCTAssertEqual(error as? ReadOnlyModeRestrictionError, .unavailable)
        }

        XCTAssertEqual(model.notification?.message, ReadOnlyModeRestrictionError.unavailable.notificationMessage)
        XCTAssertEqual(model.notification?.kind, .warning)
    }

    @MainActor
    func testReadOnlyModeBlocksConfigUpdateBeforeStorageMutation() async throws {
        let entry = makeConfigEntry(host: "prod", lineNumber: 1, fingerprint: "prod")
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        preferences.setReadOnlyModeEnabled(true)
        let model = AppModel(
            configEntries: [entry],
            dependencies: AppModelDependencies(
                keyStorage: RecordingSSHKeyStorage(),
                configStorage: RecordingSSHConfigStorage(),
                keyActions: SSHKeyFileActions(),
                preferences: preferences
            )
        )
        let request = SSHConfigHostSaveRequest(host: "prod", properties: [])

        do {
            try await model.updateConfigHost(entry, with: request)
            XCTFail("Expected updateConfigHost to throw")
        } catch {
            XCTAssertEqual(error as? ReadOnlyModeRestrictionError, .unavailable)
        }

        XCTAssertEqual(model.notification?.message, ReadOnlyModeRestrictionError.unavailable.notificationMessage)
        XCTAssertEqual(model.notification?.kind, .warning)
    }

    @MainActor
    func testReadOnlyModeDoesNotDeleteOrRenameKeyFilesOnDisk() async throws {
        let directory = try makeTemporaryDirectory()
        let privateURL = directory.appendingPathComponent("id_ed25519")
        let publicURL = directory.appendingPathComponent("id_ed25519.pub")
        try writePrivateKey(to: privateURL)
        try writePublicKey(to: publicURL, comment: "original")
        let key = try completePair(named: "id_ed25519", in: directory)
        let initialPrivateContents = try String(contentsOf: privateURL, encoding: .utf8)
        let initialPublicContents = try String(contentsOf: publicURL, encoding: .utf8)
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        preferences.setReadOnlyModeEnabled(true)
        preferences.setSSHDirectoryPath(directory.path)
        let model = AppModel(
            keys: [key],
            dependencies: AppModelDependencies(
                keyStorage: SSHKeyStorage(keyStore: SSHKeyStore()),
                configStorage: SSHConfigStorage(),
                keyActions: SSHKeyFileActions(),
                preferences: preferences,
                workspaceValidator: SSHWorkspaceValidator(fileManager: fileManager)
            )
        )
        model.selectedKeyID = key.id

        do {
            try await model.deleteSelectedKey()
            XCTFail("Expected deleteSelectedKey to throw")
        } catch {
            XCTAssertEqual(error as? ReadOnlyModeRestrictionError, .unavailable)
        }
        do {
            try await model.renameSelectedKey(to: "renamed_ed25519")
            XCTFail("Expected renameSelectedKey to throw")
        } catch {
            XCTAssertEqual(error as? ReadOnlyModeRestrictionError, .unavailable)
        }

        XCTAssertTrue(fileManager.fileExists(atPath: privateURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: publicURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: directory.appendingPathComponent("renamed_ed25519").path))
        XCTAssertFalse(fileManager.fileExists(atPath: directory.appendingPathComponent("renamed_ed25519.pub").path))
        XCTAssertEqual(try String(contentsOf: privateURL, encoding: .utf8), initialPrivateContents)
        XCTAssertEqual(try String(contentsOf: publicURL, encoding: .utf8), initialPublicContents)
    }

    @MainActor
    func testReadOnlyModeDoesNotRewriteKeyFilesOnDisk() async throws {
        let directory = try makeTemporaryDirectory()
        let privateURL = directory.appendingPathComponent("id_ed25519")
        let publicURL = directory.appendingPathComponent("id_ed25519.pub")
        let invokedURL = directory.appendingPathComponent("ssh-keygen-invoked")
        let sshKeygenURL = try writePassphraseChangingSSHKeygenScript(
            in: directory,
            argumentsURL: invokedURL,
            inputURL: directory.appendingPathComponent("ssh-keygen-input")
        )
        try writePrivateKey(to: privateURL)
        try writePublicKey(to: publicURL, comment: "original")
        let key = try completePair(named: "id_ed25519", in: directory)
        let initialPrivateContents = try String(contentsOf: privateURL, encoding: .utf8)
        let initialPublicContents = try String(contentsOf: publicURL, encoding: .utf8)
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        preferences.setReadOnlyModeEnabled(true)
        preferences.setSSHDirectoryPath(directory.path)
        let model = AppModel(
            keys: [key],
            dependencies: AppModelDependencies(
                keyStorage: SSHKeyStorage(keyStore: SSHKeyStore(sshKeygenURL: sshKeygenURL)),
                configStorage: SSHConfigStorage(),
                keyActions: SSHKeyFileActions(),
                preferences: preferences,
                workspaceValidator: SSHWorkspaceValidator(fileManager: fileManager)
            )
        )
        model.selectedKeyID = key.id

        do {
            try await model.updateSelectedKeyComment("changed")
            XCTFail("Expected updateSelectedKeyComment to throw")
        } catch {
            XCTAssertEqual(error as? ReadOnlyModeRestrictionError, .unavailable)
        }
        do {
            try await model.changeSelectedKeyPassphrase(oldPassphrase: "old", newPassphrase: "new")
            XCTFail("Expected changeSelectedKeyPassphrase to throw")
        } catch {
            XCTAssertEqual(error as? ReadOnlyModeRestrictionError, .unavailable)
        }

        XCTAssertEqual(try String(contentsOf: privateURL, encoding: .utf8), initialPrivateContents)
        XCTAssertEqual(try String(contentsOf: publicURL, encoding: .utf8), initialPublicContents)
        XCTAssertFalse(fileManager.fileExists(atPath: invokedURL.path))
    }

    @MainActor
    func testReadOnlyModeDoesNotRewriteSSHConfigOnDisk() async throws {
        let directory = try makeTemporaryDirectory()
        let configURL = directory.appendingPathComponent("config")
        let originalConfig = """
        Host prod
            HostName prod.example.com
            User deploy

        Host staging
            HostName staging.example.com
            User deploy

        """
        try originalConfig.write(to: configURL, atomically: true, encoding: .utf8)
        let entries = try SSHConfigParser.loadEntries(from: directory.path)
        let prodEntry = try XCTUnwrap(entries.first { $0.host == "prod" })
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        preferences.setReadOnlyModeEnabled(true)
        preferences.setSSHDirectoryPath(directory.path)
        let model = AppModel(
            configEntries: entries,
            dependencies: AppModelDependencies(
                keyStorage: SSHKeyStorage(keyStore: SSHKeyStore()),
                configStorage: SSHConfigStorage(),
                keyActions: SSHKeyFileActions(),
                preferences: preferences,
                workspaceValidator: SSHWorkspaceValidator(fileManager: fileManager)
            )
        )
        model.selectedConfigEntryID = prodEntry.id

        do {
            try await model.addConfigHost(
                SSHConfigHostSaveRequest(host: "new-host", properties: [.init(name: "HostName", value: "new.example.com")])
            )
            XCTFail("Expected addConfigHost to throw")
        } catch {
            XCTAssertEqual(error as? ReadOnlyModeRestrictionError, .unavailable)
        }
        do {
            try await model.updateConfigHost(
                prodEntry,
                with: SSHConfigHostSaveRequest(host: "prod", properties: [.init(name: "HostName", value: "changed.example.com")])
            )
            XCTFail("Expected updateConfigHost to throw")
        } catch {
            XCTAssertEqual(error as? ReadOnlyModeRestrictionError, .unavailable)
        }
        do {
            try await model.deleteSelectedConfigEntry()
            XCTFail("Expected deleteSelectedConfigEntry to throw")
        } catch {
            XCTAssertEqual(error as? ReadOnlyModeRestrictionError, .unavailable)
        }

        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), originalConfig)
    }

    func testExternalToolValidatorReportsAvailableExecutable() throws {
        let directory = try makeTemporaryDirectory()
        let executableURL = try writeNoopScript(named: "ssh-keygen", in: directory, permissions: 0o755)

        let status = ExternalToolValidator(fileManager: fileManager).status(
            for: .sshKeygen,
            path: executableURL.path
        )

        assertExternalToolStatus(status, is: .available, path: executableURL.path)
    }

    func testExternalToolValidatorReportsMissingExecutable() throws {
        let directory = try makeTemporaryDirectory()
        let missingPath = directory.appendingPathComponent("missing-ssh-keygen").path

        let status = ExternalToolValidator(fileManager: fileManager).status(
            for: .sshKeygen,
            path: missingPath
        )

        assertExternalToolStatus(status, is: .missing, path: missingPath)
    }

    func testExternalToolValidatorReportsNonExecutableFile() throws {
        let directory = try makeTemporaryDirectory()
        let nonExecutableURL = try writeNoopScript(named: "ssh-keygen", in: directory, permissions: 0o644)

        let status = ExternalToolValidator(fileManager: fileManager).status(
            for: .sshKeygen,
            path: nonExecutableURL.path
        )

        assertExternalToolStatus(status, is: .notExecutable, path: nonExecutableURL.path)
    }

    func testExternalToolValidatorReportsDirectoryAsNonExecutable() throws {
        let directory = try makeTemporaryDirectory()

        let status = ExternalToolValidator(fileManager: fileManager).status(
            for: .sshKeygen,
            path: directory.path
        )

        assertExternalToolStatus(status, is: .notExecutable, path: directory.path)
    }

    func testExternalToolValidatorRejectsExecutableThatIsNotSSHKeygen() throws {
        let directory = try makeTemporaryDirectory()
        let executableURL = try writeEchoScript(
            named: "not-ssh-keygen",
            in: directory,
            output: "hello from another tool"
        )

        let status = ExternalToolValidator(fileManager: fileManager).status(
            for: .sshKeygen,
            path: executableURL.path
        )

        assertExternalToolStatus(status, is: .invalidBinary, path: executableURL.path)
    }

    @MainActor
    func testSetSSHKeygenPathPersistsStatusAndUpdatesKeyStorage() async throws {
        let directory = try makeTemporaryDirectory()
        let executableURL = try writeNoopScript(named: "custom-ssh-keygen", in: directory, permissions: 0o755)
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        let keyStorage = RecordingSSHKeyStorage()
        let model = AppModel(
            dependencies: AppModelDependencies(
                keyStorage: keyStorage,
                configStorage: RecordingSSHConfigStorage(),
                keyActions: SSHKeyFileActions(),
                preferences: preferences,
                workspaceValidator: SSHWorkspaceValidator(fileManager: fileManager),
                externalToolValidator: ExternalToolValidator(fileManager: fileManager)
            )
        )

        await model.setSSHKeygenPath(executableURL.path)

        let normalizedPath = normalizedExternalToolPath(executableURL.path)
        XCTAssertEqual(model.sshKeygenPath, normalizedPath)
        XCTAssertEqual(preferences.sshKeygenPath, normalizedPath)
        assertExternalToolStatus(model.sshKeygenStatus, is: .available, path: executableURL.path)
        let updates = await keyStorage.sshKeygenPathUpdatesSnapshot()
        XCTAssertEqual(updates, [normalizedPath])
    }

    @MainActor
    func testSetSSHKeygenPathRejectsInvalidBinaryAndKeepsPreviousPath() async throws {
        let directory = try makeTemporaryDirectory()
        let invalidBinaryURL = try writeEchoScript(
            named: "not-ssh-keygen",
            in: directory,
            output: "hello from another tool"
        )
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        let keyStorage = RecordingSSHKeyStorage()
        let model = AppModel(
            dependencies: AppModelDependencies(
                keyStorage: keyStorage,
                configStorage: RecordingSSHConfigStorage(),
                keyActions: SSHKeyFileActions(),
                preferences: preferences,
                workspaceValidator: SSHWorkspaceValidator(fileManager: fileManager),
                externalToolValidator: ExternalToolValidator(fileManager: fileManager)
            )
        )
        let previousPath = model.sshKeygenPath

        await model.setSSHKeygenPath(invalidBinaryURL.path)

        XCTAssertEqual(model.sshKeygenPath, previousPath)
        XCTAssertEqual(preferences.sshKeygenPath, previousPath)
        assertExternalToolStatus(model.sshKeygenStatus, is: .available, path: previousPath)
        XCTAssertEqual(model.notification?.message, "Wrong binary selected")
        let updates = await keyStorage.sshKeygenPathUpdatesSnapshot()
        XCTAssertEqual(updates, [])
    }

    @MainActor
    func testResetSSHKeygenPathRestoresDefaultAndUpdatesKeyStorage() async throws {
        let directory = try makeTemporaryDirectory()
        let executableURL = try writeNoopScript(named: "custom-ssh-keygen", in: directory, permissions: 0o755)
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        preferences.setSSHKeygenPath(executableURL.path)
        let keyStorage = RecordingSSHKeyStorage()
        let model = AppModel(
            dependencies: AppModelDependencies(
                keyStorage: keyStorage,
                configStorage: RecordingSSHConfigStorage(),
                keyActions: SSHKeyFileActions(),
                preferences: preferences,
                workspaceValidator: SSHWorkspaceValidator(fileManager: fileManager),
                externalToolValidator: ExternalToolValidator(fileManager: fileManager)
            )
        )

        await model.resetSSHKeygenPath()

        XCTAssertEqual(model.sshKeygenPath, ExternalTool.sshKeygen.defaultPath)
        XCTAssertEqual(preferences.sshKeygenPath, ExternalTool.sshKeygen.defaultPath)
        let updates = await keyStorage.sshKeygenPathUpdatesSnapshot()
        XCTAssertEqual(updates, [ExternalTool.sshKeygen.defaultPath])
    }

    @MainActor
    func testChangeSSHDirectoryPersistsPathAndReloadsKeysAndConfig() async throws {
        let directory = try makeTemporaryDirectory()
        let normalizedPath = SSHWorkspacePath.normalizeDirectoryPath(directory.path)
        let keyStorage = RecordingSSHKeyStorage(
            inventoriesByPath: [
                normalizedPath: SSHKeyInventory(
                    completePairs: [makeKeyItem(name: "id_work", privateKeyPath: "\(normalizedPath)/id_work")],
                    otherKeys: []
                )
            ]
        )
        let configStorage = RecordingSSHConfigStorage(
            entriesByPath: [
                normalizedPath: [makeConfigEntry(host: "prod", lineNumber: 1, fingerprint: "prod")]
            ]
        )
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        let model = AppModel(
            dependencies: AppModelDependencies(
                keyStorage: keyStorage,
                configStorage: configStorage,
                keyActions: SSHKeyFileActions(),
                preferences: preferences,
                workspaceValidator: SSHWorkspaceValidator(fileManager: fileManager)
            )
        )

        await model.changeSSHDirectory(to: directory.path)

        XCTAssertEqual(model.sshDirectoryPath, normalizedPath)
        XCTAssertEqual(preferences.sshDirectoryPath, normalizedPath)
        let loadedKeyPaths = await keyStorage.loadedPathsSnapshot()
        let loadedConfigPaths = await configStorage.loadedPathsSnapshot()
        XCTAssertEqual(loadedKeyPaths, [normalizedPath])
        XCTAssertEqual(loadedConfigPaths, [normalizedPath])
        XCTAssertEqual(model.keys.map(\.name), ["id_work"])
        XCTAssertEqual(model.configEntries.map(\.host), ["prod"])
        XCTAssertFalse(model.isChangingSSHDirectory)
    }

    @MainActor
    func testChangeSSHDirectoryIgnoresRepeatedSelection() async throws {
        let directory = try makeTemporaryDirectory()
        let normalizedPath = SSHWorkspacePath.normalizeDirectoryPath(directory.path)
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        preferences.setSSHDirectoryPath(normalizedPath)
        let keyStorage = RecordingSSHKeyStorage()
        let configStorage = RecordingSSHConfigStorage()
        let model = AppModel(
            dependencies: AppModelDependencies(
                keyStorage: keyStorage,
                configStorage: configStorage,
                keyActions: SSHKeyFileActions(),
                preferences: preferences,
                workspaceValidator: SSHWorkspaceValidator(fileManager: fileManager)
            )
        )

        await model.changeSSHDirectory(to: directory.path)

        let loadedKeyPaths = await keyStorage.loadedPathsSnapshot()
        let loadedConfigPaths = await configStorage.loadedPathsSnapshot()
        XCTAssertEqual(loadedKeyPaths, [])
        XCTAssertEqual(loadedConfigPaths, [])
    }

    @MainActor
    func testChangeSSHDirectoryKeepsLatestStateWhenPreviousReloadFinishesLater() async throws {
        let slowDirectory = try makeTemporaryDirectory()
        let fastDirectory = try makeTemporaryDirectory()
        let slowPath = SSHWorkspacePath.normalizeDirectoryPath(slowDirectory.path)
        let fastPath = SSHWorkspacePath.normalizeDirectoryPath(fastDirectory.path)
        let keyStorage = RecordingSSHKeyStorage(
            inventoriesByPath: [
                slowPath: SSHKeyInventory(
                    completePairs: [makeKeyItem(name: "slow_key", privateKeyPath: "\(slowPath)/slow_key")],
                    otherKeys: []
                ),
                fastPath: SSHKeyInventory(
                    completePairs: [makeKeyItem(name: "fast_key", privateKeyPath: "\(fastPath)/fast_key")],
                    otherKeys: []
                )
            ],
            delaysByPath: [
                slowPath: 300_000_000
            ]
        )
        let configStorage = RecordingSSHConfigStorage(
            entriesByPath: [
                slowPath: [makeConfigEntry(host: "slow", lineNumber: 1, fingerprint: "slow")],
                fastPath: [makeConfigEntry(host: "fast", lineNumber: 1, fingerprint: "fast")]
            ],
            delaysByPath: [
                slowPath: 300_000_000
            ]
        )
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        let model = AppModel(
            dependencies: AppModelDependencies(
                keyStorage: keyStorage,
                configStorage: configStorage,
                keyActions: SSHKeyFileActions(),
                preferences: preferences,
                workspaceValidator: SSHWorkspaceValidator(fileManager: fileManager)
            )
        )

        let firstChange = Task {
            await model.changeSSHDirectory(to: slowDirectory.path)
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        let secondChange = Task {
            await model.changeSSHDirectory(to: fastDirectory.path)
        }

        await firstChange.value
        await secondChange.value

        XCTAssertEqual(model.sshDirectoryPath, fastPath)
        XCTAssertEqual(model.keys.map(\.name), ["fast_key"])
        XCTAssertEqual(model.configEntries.map(\.host), ["fast"])
    }

    func testSSHWorkspaceValidatorRejectsMissingDirectory() {
        let path = "/tmp/ssh-keys-manager-tests/missing-\(UUID().uuidString)"

        XCTAssertThrowsError(try SSHWorkspaceValidator(fileManager: fileManager).validate(directoryPath: path)) { error in
            XCTAssertEqual(
                error as? SSHWorkspaceDirectoryError,
                .directoryMissing(SSHWorkspacePath.displayPath(for: path))
            )
        }
    }

    func testSSHWorkspaceValidatorRejectsFilePath() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("config")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try SSHWorkspaceValidator(fileManager: fileManager).validate(directoryPath: fileURL.path)) { error in
            XCTAssertEqual(
                error as? SSHWorkspaceDirectoryError,
                .notDirectory(SSHWorkspacePath.displayPath(for: fileURL.path))
            )
        }
    }

    func testSSHWorkspaceValidatorRejectsUnreadableDirectory() throws {
        let directory = try makeTemporaryDirectory()
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o000)], ofItemAtPath: directory.path)
        defer {
            try? fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: directory.path)
        }

        XCTAssertThrowsError(try SSHWorkspaceValidator(fileManager: fileManager).validate(directoryPath: directory.path)) { error in
            XCTAssertEqual(
                error as? SSHWorkspaceDirectoryError,
                .unreadable(SSHWorkspacePath.displayPath(for: directory.path))
            )
        }
    }

    @MainActor
    func testCreateEmptyConfigFileCreatesFileAndReloadsConfigState() async throws {
        let directory = try makeTemporaryDirectory()
        let normalizedPath = SSHWorkspacePath.normalizeDirectoryPath(directory.path)
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        let model = AppModel(
            dependencies: AppModelDependencies(
                keyStorage: RecordingSSHKeyStorage(),
                configStorage: SSHConfigStorage(),
                keyActions: SSHKeyFileActions(),
                preferences: preferences,
                workspaceValidator: SSHWorkspaceValidator(fileManager: fileManager)
            )
        )

        await model.changeSSHDirectory(to: directory.path)
        XCTAssertTrue(model.isConfigFileMissing)

        await model.createEmptyConfigFile()

        XCTAssertTrue(fileManager.fileExists(atPath: "\(normalizedPath)/config"))
        XCTAssertFalse(model.isConfigFileMissing)
        XCTAssertTrue(model.configEntries.isEmpty)
        XCTAssertNil(model.configErrorMessage)
    }

    @MainActor
    func testCreateEmptyConfigFilePreservesMissingStateWhenCreationFails() async throws {
        let directory = try makeTemporaryDirectory()
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        let model = AppModel(
            dependencies: AppModelDependencies(
                keyStorage: RecordingSSHKeyStorage(),
                configStorage: FailingCreateSSHConfigStorage(),
                keyActions: SSHKeyFileActions(),
                preferences: preferences,
                workspaceValidator: SSHWorkspaceValidator(fileManager: fileManager)
            )
        )

        await model.changeSSHDirectory(to: directory.path)
        XCTAssertTrue(model.isConfigFileMissing)

        await model.createEmptyConfigFile()

        XCTAssertTrue(model.isConfigFileMissing)
        XCTAssertTrue(model.configEntries.isEmpty)
        XCTAssertNotNil(model.configErrorMessage)
        XCTAssertTrue(model.configErrorMessage?.hasPrefix("Unable to create SSH config:") == true)
    }

    @MainActor
    func testLoadIfNeededRetriesAfterKeyLoadFailure() async throws {
        let directory = try makeTemporaryDirectory()
        let normalizedPath = SSHWorkspacePath.normalizeDirectoryPath(directory.path)
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        preferences.setSSHDirectoryPath(normalizedPath)
        let keyStorage = FlakySSHKeyStorage(
            failureCountByPath: [normalizedPath: 1],
            inventoriesByPath: [
                normalizedPath: SSHKeyInventory(
                    completePairs: [makeKeyItem(name: "id_retry", privateKeyPath: "\(normalizedPath)/id_retry")],
                    otherKeys: []
                )
            ]
        )
        let model = AppModel(
            dependencies: AppModelDependencies(
                keyStorage: keyStorage,
                configStorage: RecordingSSHConfigStorage(),
                keyActions: SSHKeyFileActions(),
                preferences: preferences,
                workspaceValidator: SSHWorkspaceValidator(fileManager: fileManager)
            )
        )

        await model.loadKeysIfNeeded()
        XCTAssertEqual(model.keys, [])
        XCTAssertNotNil(model.keyErrorMessage)

        await model.loadKeysIfNeeded()

        XCTAssertEqual(model.keys.map(\.name), ["id_retry"])
        XCTAssertNil(model.keyErrorMessage)
        let loadedKeyPaths = await keyStorage.loadedPathsSnapshot()
        XCTAssertEqual(loadedKeyPaths, [normalizedPath, normalizedPath])
    }

    @MainActor
    func testLoadIfNeededRetriesAfterConfigLoadFailure() async throws {
        let directory = try makeTemporaryDirectory()
        let normalizedPath = SSHWorkspacePath.normalizeDirectoryPath(directory.path)
        let suiteName = "SSHKeyStoreTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(userDefaults: userDefaults)
        preferences.setSSHDirectoryPath(normalizedPath)
        let configStorage = FlakySSHConfigStorage(
            failureCountByPath: [normalizedPath: 1],
            entriesByPath: [
                normalizedPath: [makeConfigEntry(host: "retry-host", lineNumber: 1, fingerprint: "retry")]
            ]
        )
        let model = AppModel(
            dependencies: AppModelDependencies(
                keyStorage: RecordingSSHKeyStorage(),
                configStorage: configStorage,
                keyActions: SSHKeyFileActions(),
                preferences: preferences,
                workspaceValidator: SSHWorkspaceValidator(fileManager: fileManager)
            )
        )

        await model.loadConfigIfNeeded()
        XCTAssertTrue(model.configEntries.isEmpty)
        XCTAssertNotNil(model.configErrorMessage)

        await model.loadConfigIfNeeded()

        XCTAssertEqual(model.configEntries.map(\.host), ["retry-host"])
        XCTAssertNil(model.configErrorMessage)
        let loadedConfigPaths = await configStorage.loadedPathsSnapshot()
        XCTAssertEqual(loadedConfigPaths, [normalizedPath, normalizedPath])
    }

    private enum ExpectedExternalToolStatus {
        case available
        case missing
        case notExecutable
        case invalidBinary
    }

    private func assertExternalToolStatus(
        _ status: ExternalToolStatus,
        is expectedStatus: ExpectedExternalToolStatus,
        path: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectedPath = normalizedExternalToolPath(path)

        switch (status, expectedStatus) {
        case (.available(let path), .available),
             (.missing(let path), .missing),
             (.notExecutable(let path), .notExecutable),
             (.invalidBinary(let path), .invalidBinary):
            XCTAssertEqual(path, expectedPath, file: file, line: line)
        default:
            XCTFail("Expected \(expectedStatus), got \(status)", file: file, line: line)
        }
    }

    private func normalizedExternalToolPath(_ path: String) -> String {
        ExternalToolPath.normalizeExecutablePath(
            path,
            defaultPath: ExternalTool.sshKeygen.defaultPath
        )
    }

    private var publicKeyData: String {
        Data("public-key-data".utf8).base64EncodedString()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let temporaryPath = fileManager.temporaryDirectory.path
        let canonicalTemporaryPath: String
        if temporaryPath.hasPrefix("/var/") {
            canonicalTemporaryPath = "/private\(temporaryPath)"
        } else {
            canonicalTemporaryPath = temporaryPath
        }

        let directory = URL(fileURLWithPath: canonicalTemporaryPath, isDirectory: true).appendingPathComponent(
            "SSHKeyStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func configBackupURL(for configURL: URL, index: Int) -> URL {
        configURL.deletingLastPathComponent()
            .appendingPathComponent("\(configURL.lastPathComponent).backup.\(index)")
    }

    private func writePublicKey(
        to url: URL,
        type: String = "ssh-ed25519",
        comment: String = "test@example.com"
    ) throws {
        try "\(type) \(publicKeyData) \(comment)\n".write(to: url, atomically: true, encoding: .utf8)
    }

    private func writePrivateKey(
        to url: URL,
        marker: String = "-----BEGIN OPENSSH PRIVATE KEY-----",
        body: String = "private-key-data"
    ) throws {
        let endMarker = marker.replacingOccurrences(of: "BEGIN", with: "END")
        try "\(marker)\n\(body)\n\(endMarker)\n".write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeNoopScript(named name: String, in directory: URL, permissions: Int) throws -> URL {
        let scriptURL = directory.appendingPathComponent(name)
        try """
        #!/bin/sh
        if [ "$1" = "-?" ]; then
            echo 'usage: ssh-keygen [-q] [-t ed25519]' >&2
            exit 1
        fi
        exit 0
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: permissions)],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL
    }

    private func writeEchoScript(named name: String, in directory: URL, output: String) throws -> URL {
        let scriptURL = directory.appendingPathComponent(name)
        try """
        #!/bin/sh
        echo "\(output)"
        exit 0
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL
    }

    private func writeFailingSSHKeygenScript(in directory: URL) throws -> URL {
        let scriptURL = directory.appendingPathComponent("failing-ssh-keygen")
        try """
        #!/bin/sh
        if [ "$1" = "-?" ]; then
            echo 'usage: ssh-keygen [-q] [-t ed25519]' >&2
            exit 1
        fi
        while [ "$#" -gt 0 ]; do
            if [ "$1" = "-f" ]; then
                shift
                touch "$1"
                touch "$1.pub"
            fi
            shift
        done
        echo "simulated failure" >&2
        exit 1
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL
    }

    private func writePassphraseChangingSSHKeygenScript(in directory: URL, argumentsURL: URL, inputURL: URL) throws -> URL {
        let scriptURL = directory.appendingPathComponent("passphrase-ssh-keygen")
        try """
        #!/bin/sh
        if [ "$1" = "-?" ]; then
            echo 'usage: ssh-keygen [-q] [-t ed25519]' >&2
            exit 1
        fi
        printf '%s\\n' "$@" > '\(argumentsURL.path)'
        IFS= read -r old_passphrase || old_passphrase=''
        IFS= read -r new_passphrase || new_passphrase=''
        IFS= read -r confirm_passphrase || confirm_passphrase=''
        printf '%s\\n%s\\n%s\\n' "$old_passphrase" "$new_passphrase" "$confirm_passphrase" > '\(inputURL.path)'
        exit 0
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL
    }

    private func writeGeneratingSSHKeygenScript(in directory: URL, argumentsURL: URL, inputURL: URL) throws -> URL {
        let scriptURL = directory.appendingPathComponent("generate-ssh-keygen")
        try """
        #!/bin/sh
        if [ "$1" = "-?" ]; then
            echo 'usage: ssh-keygen [-q] [-t ed25519]' >&2
            exit 1
        fi
        printf '%s\\n' "$@" > '\(argumentsURL.path)'
        output_path=''
        while [ "$#" -gt 0 ]; do
            if [ "$1" = "-f" ]; then
                shift
                output_path="$1"
                break
            fi
            shift
        done
        IFS= read -r passphrase || passphrase=''
        IFS= read -r confirm_passphrase || confirm_passphrase=''
        printf '%s\\n%s\\n' "$passphrase" "$confirm_passphrase" > '\(inputURL.path)'
        touch "$output_path"
        touch "$output_path.pub"
        exit 0
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL
    }

    private func completePair(named name: String, in directory: URL) throws -> SSHKeyItem {
        let inventory = try SSHKeyStore().loadKeys(from: directory.path)
        return try XCTUnwrap(inventory.completePairs.first { $0.name == name })
    }

    private func publicKey(named name: String, in directory: URL) throws -> SSHKeyItem {
        let inventory = try SSHKeyStore().loadKeys(from: directory.path)
        return try XCTUnwrap(inventory.otherKeys.first { $0.name == name && $0.kind == .publicKey })
    }

    private func privateKey(named name: String, in directory: URL) throws -> SSHKeyItem {
        let inventory = try SSHKeyStore().loadKeys(from: directory.path)
        return try XCTUnwrap(inventory.otherKeys.first { $0.name == name && $0.kind == .privateKey })
    }

    private func configEntry(named host: String, in contents: String, configPath: String = "/tmp/config") throws -> SSHConfigEntry {
        let snapshot = SSHConfigParser.parseDocument(contents, configPath: configPath)
        return try XCTUnwrap(snapshot.entries.first { $0.host == host })
    }

    private func deleteConfigEntry(
        _ entry: SSHConfigEntry,
        from contents: String,
        configPath: String = "/tmp/config"
    ) throws -> String {
        try SSHConfigWriter.deleteHost(entry: entry, from: contents, configPath: configPath)
    }

    private func makeConfigEntry(host: String, lineNumber: Int, fingerprint: String) -> SSHConfigEntry {
        SSHConfigEntry(
            id: "/tmp/config:\(lineNumber):\(host)",
            host: host,
            lineNumber: lineNumber,
            fields: [
                SSHConfigField(id: "\(lineNumber):host", name: "Host", value: host, normalizedName: "host")
            ],
            sourceFingerprint: fingerprint
        )
    }

    private func makeKeyItem(
        name: String,
        kind: SSHKeyKind = .completePair,
        publicKeyPath: String? = nil,
        privateKeyPath: String? = nil
    ) -> SSHKeyItem {
        let resolvedPrivateKeyPath: String? = switch kind {
        case .completePair, .privateKey:
            privateKeyPath ?? "/tmp/\(name)"
        case .publicKey:
            privateKeyPath
        }
        let resolvedPublicKeyPath: String? = if let publicKeyPath {
            publicKeyPath
        } else {
            switch kind {
            case .completePair:
                "/tmp/\(name).pub"
            case .privateKey:
                nil
            case .publicKey:
                "/tmp/\(name)"
            }
        }
        let resolvedFilePath = resolvedPrivateKeyPath ?? resolvedPublicKeyPath ?? "/tmp/\(name)"

        return SSHKeyItem(
            id: resolvedFilePath,
            name: name,
            publicKeyPath: resolvedPublicKeyPath,
            privateKeyPath: resolvedPrivateKeyPath,
            filePath: resolvedFilePath,
            kind: kind,
            type: "ED25519",
            fingerprint: "SHA256:test",
            comment: "test@example.com",
            createdAt: .now,
            isPassphraseProtected: false
        )
    }
}

private enum TestError: Error {
    case expectedFailure
}

private actor FakeSSHConfigStorage: SSHConfigStorageManaging {
    private let loadEntriesResult: [SSHConfigEntry]
    private(set) var deletedHosts: [String] = []

    init(loadEntriesResult: [SSHConfigEntry]) {
        self.loadEntriesResult = loadEntriesResult
    }

    func loadEntries(from directoryPath: String) async throws -> [SSHConfigEntry] {
        loadEntriesResult
    }

    func apply(
        _ mutation: SSHConfigMutation,
        inDirectory directoryPath: String,
        propertyIndentation: SSHConfigHostPropertyIndentation,
        backupLimit: Int
    ) async throws {
        switch mutation {
        case .delete(let entry):
            let deletedHost = await MainActor.run { entry.host }
            deletedHosts.append(deletedHost)
        case .add, .update:
            XCTFail("Unexpected config mutation: \(mutation)")
        }
    }

    func createEmptyConfig(inDirectory directoryPath: String) async throws {
        XCTFail("createEmptyConfig should not be called")
    }
}

private actor FakeSSHKeyStorage: SSHKeyStorageManaging {
    let renameError: Error?
    let duplicateError: Error?

    init(renameError: Error? = nil, duplicateError: Error? = nil) {
        self.renameError = renameError
        self.duplicateError = duplicateError
    }

    func loadKeys(from directoryPath: String) async throws -> SSHKeyInventory {
        SSHKeyInventory(completePairs: [], otherKeys: [])
    }

    func publicKeyContents(for key: SSHKeyItem) async throws -> String {
        XCTFail("publicKeyContents should not be called")
        return ""
    }

    func privateKeyContents(for key: SSHKeyItem) async throws -> String {
        XCTFail("privateKeyContents should not be called")
        return ""
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
        if let renameError {
            throw renameError
        }

        return "/tmp/\(newName)"
    }

    func duplicate(_ key: SSHKeyItem, to newName: String) async throws -> SSHKeyItem.ID {
        if let duplicateError {
            throw duplicateError
        }

        return "/tmp/\(newName)"
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

private actor FailingCreateSSHConfigStorage: SSHConfigStorageManaging {
    func loadEntries(from directoryPath: String) async throws -> [SSHConfigEntry] {
        let configPath = "\(directoryPath)/config"
        throw SSHConfigLoadError.fileMissing(path: configPath)
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
        throw TestError.expectedFailure
    }
}

private actor RecordingSSHConfigStorage: SSHConfigStorageManaging {
    private(set) var entriesByPath: [String: [SSHConfigEntry]]
    private let delaysByPath: [String: UInt64]
    private(set) var loadedPaths: [String] = []

    init(
        entriesByPath: [String: [SSHConfigEntry]] = [:],
        delaysByPath: [String: UInt64] = [:]
    ) {
        self.entriesByPath = entriesByPath
        self.delaysByPath = delaysByPath
    }

    func loadedPathsSnapshot() -> [String] {
        loadedPaths
    }

    func loadEntries(from directoryPath: String) async throws -> [SSHConfigEntry] {
        loadedPaths.append(directoryPath)

        if let delay = delaysByPath[directoryPath] {
            try? await Task.sleep(nanoseconds: delay)
        }

        return entriesByPath[directoryPath] ?? []
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
        entriesByPath[directoryPath] = []
    }
}

private actor FlakySSHConfigStorage: SSHConfigStorageManaging {
    private var failureCountByPath: [String: Int]
    private let entriesByPath: [String: [SSHConfigEntry]]
    private(set) var loadedPaths: [String] = []

    init(
        failureCountByPath: [String: Int],
        entriesByPath: [String: [SSHConfigEntry]]
    ) {
        self.failureCountByPath = failureCountByPath
        self.entriesByPath = entriesByPath
    }

    func loadedPathsSnapshot() -> [String] {
        loadedPaths
    }

    func loadEntries(from directoryPath: String) async throws -> [SSHConfigEntry] {
        loadedPaths.append(directoryPath)

        if let remainingFailures = failureCountByPath[directoryPath], remainingFailures > 0 {
            failureCountByPath[directoryPath] = remainingFailures - 1
            throw TestError.expectedFailure
        }

        return entriesByPath[directoryPath] ?? []
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

private actor RecordingSSHKeyStorage: SSHKeyStorageManaging {
    private let inventoriesByPath: [String: SSHKeyInventory]
    private let delaysByPath: [String: UInt64]
    private(set) var loadedPaths: [String] = []
    private(set) var sshKeygenPathUpdates: [String] = []

    init(
        inventoriesByPath: [String: SSHKeyInventory] = [:],
        delaysByPath: [String: UInt64] = [:]
    ) {
        self.inventoriesByPath = inventoriesByPath
        self.delaysByPath = delaysByPath
    }

    func loadedPathsSnapshot() -> [String] {
        loadedPaths
    }

    func sshKeygenPathUpdatesSnapshot() -> [String] {
        sshKeygenPathUpdates
    }

    func updateSSHKeygenPath(_ path: String) async {
        sshKeygenPathUpdates.append(path)
    }

    func loadKeys(from directoryPath: String) async throws -> SSHKeyInventory {
        loadedPaths.append(directoryPath)

        if let delay = delaysByPath[directoryPath] {
            try? await Task.sleep(nanoseconds: delay)
        }

        return inventoriesByPath[directoryPath] ?? SSHKeyInventory(completePairs: [], otherKeys: [])
    }

    func publicKeyContents(for key: SSHKeyItem) async throws -> String {
        XCTFail("publicKeyContents should not be called")
        return ""
    }

    func privateKeyContents(for key: SSHKeyItem) async throws -> String {
        XCTFail("privateKeyContents should not be called")
        return ""
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

private actor FlakySSHKeyStorage: SSHKeyStorageManaging {
    private var failureCountByPath: [String: Int]
    private let inventoriesByPath: [String: SSHKeyInventory]
    private(set) var loadedPaths: [String] = []

    init(
        failureCountByPath: [String: Int],
        inventoriesByPath: [String: SSHKeyInventory]
    ) {
        self.failureCountByPath = failureCountByPath
        self.inventoriesByPath = inventoriesByPath
    }

    func loadedPathsSnapshot() -> [String] {
        loadedPaths
    }

    func loadKeys(from directoryPath: String) async throws -> SSHKeyInventory {
        loadedPaths.append(directoryPath)

        if let remainingFailures = failureCountByPath[directoryPath], remainingFailures > 0 {
            failureCountByPath[directoryPath] = remainingFailures - 1
            throw TestError.expectedFailure
        }

        return inventoriesByPath[directoryPath] ?? SSHKeyInventory(completePairs: [], otherKeys: [])
    }

    func publicKeyContents(for key: SSHKeyItem) async throws -> String {
        XCTFail("publicKeyContents should not be called")
        return ""
    }

    func privateKeyContents(for key: SSHKeyItem) async throws -> String {
        XCTFail("privateKeyContents should not be called")
        return ""
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
