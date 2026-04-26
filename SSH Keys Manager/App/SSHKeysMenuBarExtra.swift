import AppKit

final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var model: AppModel
    private var showApp: () -> Void

    init(model: AppModel, showApp: @escaping () -> Void) {
        self.model = model
        self.showApp = showApp
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        configureButton()
        menu.delegate = self
        statusItem.menu = menu

        Task {
            await model.keysCoordinator.loadIfNeeded()
        }
    }

    func update(model: AppModel, showApp: @escaping () -> Void) {
        self.model = model
        self.showApp = showApp
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()

        Task {
            await model.keysCoordinator.loadIfNeeded()
            rebuildMenu()
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }

        let image = NSImage(systemSymbolName: "key.horizontal.fill", accessibilityDescription: "SSH Keys Manager")
            ?? NSImage(systemSymbolName: "key.fill", accessibilityDescription: "SSH Keys Manager")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true

        button.image = image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "SSH Keys Manager"
    }

    @MainActor
    private func rebuildMenu() {
        menu.removeAllItems()

        if model.recentKeys.isEmpty {
            let emptyItem = NSMenuItem(title: "No SSH keys found", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for key in model.recentKeys {
                menu.addItem(menuItem(for: key))
            }
        }

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open App", action: #selector(openAppWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let quitItem = NSMenuItem(title: "Quit App", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func menuItem(for key: SSHKeyItem) -> NSMenuItem {
        let item = NSMenuItem(title: key.menuBarTitle, action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let publicKeyItem = NSMenuItem(
            title: "Copy Public Key",
            action: #selector(copyPublicKey(_:)),
            keyEquivalent: ""
        )
        publicKeyItem.target = self
        publicKeyItem.representedObject = MenuBarKeyCommand(key: key)
        publicKeyItem.isEnabled = key.publicKeyPath != nil
        submenu.addItem(publicKeyItem)

        let privateKeyItem = NSMenuItem(
            title: "Copy Private Key",
            action: #selector(copyPrivateKey(_:)),
            keyEquivalent: ""
        )
        privateKeyItem.target = self
        privateKeyItem.representedObject = MenuBarKeyCommand(key: key)
        privateKeyItem.isEnabled = key.privateKeyPath != nil
        submenu.addItem(privateKeyItem)

        item.submenu = submenu
        return item
    }

    @objc private func copyPublicKey(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? MenuBarKeyCommand else {
            return
        }

        Task {
            await model.keysCoordinator.copyPublicKey(for: command.key)
        }
    }

    @objc private func copyPrivateKey(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? MenuBarKeyCommand else {
            return
        }

        Task {
            await model.keysCoordinator.copyPrivateKey(for: command.key)
        }
    }

    @objc private func openAppWindow() {
        showApp()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

private final class MenuBarKeyCommand {
    let key: SSHKeyItem

    init(key: SSHKeyItem) {
        self.key = key
    }
}

private extension SSHKeyItem {
    var menuBarTitle: String {
        "\(name) - \(menuBarFileName)"
    }

    var menuBarFileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
}
