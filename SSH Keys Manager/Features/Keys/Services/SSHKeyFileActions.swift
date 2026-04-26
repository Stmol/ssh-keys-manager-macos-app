import AppKit
import Foundation

protocol SSHKeyActionHandling {
    func reveal(_ key: SSHKeyItem)
    func reveal(fileAtPath path: String)
    func openDirectory(atPath path: String)
    func copyToPasteboard(_ contents: String)
    func copyFingerprint(_ key: SSHKeyItem)
}

struct SSHKeyFileActions: SSHKeyActionHandling {
    private let pasteboard: NSPasteboard
    private let workspace: NSWorkspace

    init(
        pasteboard: NSPasteboard = .general,
        workspace: NSWorkspace = .shared
    ) {
        self.pasteboard = pasteboard
        self.workspace = workspace
    }

    func reveal(_ key: SSHKeyItem) {
        let urls = [
            key.privateKeyPath,
            key.publicKeyPath
        ].compactMap { path in
            path.map(URL.init(fileURLWithPath:))
        }

        workspace.activateFileViewerSelecting(urls)
    }

    func reveal(fileAtPath path: String) {
        let resolvedPath = (path as NSString).expandingTildeInPath
        workspace.activateFileViewerSelecting([URL(fileURLWithPath: resolvedPath)])
    }

    func openDirectory(atPath path: String) {
        let resolvedPath = (path as NSString).expandingTildeInPath
        workspace.open(URL(fileURLWithPath: resolvedPath, isDirectory: true))
    }

    func copyFingerprint(_ key: SSHKeyItem) {
        copyToPasteboard(key.fingerprint)
    }

    func copyToPasteboard(_ contents: String) {
        pasteboard.clearContents()
        pasteboard.setString(contents, forType: .string)
    }
}

enum SSHKeyFileActionError: LocalizedError {
    case missingPrivateKey
    case missingPublicKey

    var errorDescription: String? {
        switch self {
        case .missingPrivateKey:
            return "This key has no private key file."
        case .missingPublicKey:
            return "This key has no public key file."
        }
    }
}
