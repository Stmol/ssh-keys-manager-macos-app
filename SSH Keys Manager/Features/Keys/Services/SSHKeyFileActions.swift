import AppKit
import Foundation

protocol SSHKeyActionHandling {
    func reveal(_ key: SSHKeyItem)
    func reveal(fileAtPath path: String)
    func openDirectory(atPath path: String)
    func copyToPasteboard(_ contents: String)
    func copySensitiveToPasteboard(_ contents: String, clearAfter seconds: TimeInterval)
    func copyFingerprint(_ key: SSHKeyItem)
}

final class SSHKeyFileActions: SSHKeyActionHandling {
    private let pasteboard: NSPasteboard
    private let workspace: NSWorkspace
    private var pendingClear: DispatchWorkItem?

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

    func copySensitiveToPasteboard(_ contents: String, clearAfter seconds: TimeInterval) {
        pasteboard.clearContents()
        pasteboard.setString(contents, forType: .string)
        let copiedChangeCount = pasteboard.changeCount

        pendingClear?.cancel()
        pendingClear = nil

        guard seconds > 0 else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            if pasteboard.changeCount == copiedChangeCount {
                pasteboard.clearContents()
            }

            pendingClear = nil
        }

        pendingClear = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: workItem)
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
