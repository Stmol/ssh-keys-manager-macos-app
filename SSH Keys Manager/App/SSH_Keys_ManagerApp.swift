//
//  SSH_Keys_ManagerApp.swift
//  SSH Keys Manager
//
//  Created by Stmol on 22.04.2026.
import AppKit
import SwiftUI

@main
struct SSH_Keys_ManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear {
                    appDelegate.configureStatusItem(model: model)
                }
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenuController: StatusMenuController?
    private weak var model: AppModel?

    func configureStatusItem(model: AppModel) {
        self.model = model
        let showApp: () -> Void = { [weak self] in
            self?.showAppWindow()
        }

        if let statusMenuController {
            statusMenuController.update(model: model, showApp: showApp)
        } else {
            statusMenuController = StatusMenuController(model: model, showApp: showApp)
        }

        installWindowDelegates()
    }

    @MainActor
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        model?.isMinimizeToMenuBarEnabled != true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showAppWindow()
        return true
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard notification.object is NSWindow else {
            return
        }

        installWindowDelegates()
    }

    private func installWindowDelegates() {
        for window in NSApp.windows where canControlMinimizeBehavior(for: window) {
            let miniaturizeButton = window.standardWindowButton(.miniaturizeButton)
            miniaturizeButton?.target = self
            miniaturizeButton?.action = #selector(miniaturizeButtonClicked(_:))
        }
    }

    private func canControlMinimizeBehavior(for window: NSWindow) -> Bool {
        window.styleMask.contains(.miniaturizable) && !(window is NSPanel)
    }

    private func showAppWindow() {
        NSApp.setActivationPolicy(.regular)

        DispatchQueue.main.async { [weak self] in
            self?.presentAppWindow()
        }
    }

    private func presentAppWindow() {
        if let window = NSApp.windows.first(where: canControlMinimizeBehavior(for:)) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }

            window.makeKeyAndOrderFront(nil)
        }

        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideWindowToMenuBar(_ window: NSWindow) {
        window.orderOut(nil)
        NSApp.hide(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    @MainActor
    @objc private func miniaturizeButtonClicked(_ sender: NSButton) {
        guard let window = sender.window else {
            return
        }

        guard model?.isMinimizeToMenuBarEnabled == true else {
            window.miniaturize(nil)
            return
        }

        hideWindowToMenuBar(window)
    }
}
