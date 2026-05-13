import AppKit
import Foundation

@MainActor
protocol PrivateKeyCopyConfirming: AnyObject {
    var suppressConfirmationUntilAppRestarts: Bool { get }

    func confirmCopy(keyName: String) -> Bool
}

@MainActor
extension PrivateKeyCopyConfirming {
    var suppressConfirmationUntilAppRestarts: Bool {
        false
    }
}

@MainActor
final class NSAlertPrivateKeyCopyConfirmer: PrivateKeyCopyConfirming {
    private(set) var suppressConfirmationUntilAppRestarts = false

    nonisolated init() {}

    func confirmCopy(keyName: String) -> Bool {
        suppressConfirmationUntilAppRestarts = false

        let alert = NSAlert()
        alert.messageText = "Copy private key to clipboard?"
        alert.informativeText = "\(keyName) will be placed in the system clipboard. Any app with clipboard access can read it."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Copy")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again until app restarts"

        let didConfirm = alert.runModal() == .alertFirstButtonReturn
        suppressConfirmationUntilAppRestarts = didConfirm && alert.suppressionButton?.state == .on
        return didConfirm
    }
}

protocol PrivateKeyCopyConfirmationProviding {
    var privateKeyCopyConfirmer: any PrivateKeyCopyConfirming { get }
}
