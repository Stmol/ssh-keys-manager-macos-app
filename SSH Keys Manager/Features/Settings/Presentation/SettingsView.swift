import AppKit
import SwiftUI

private enum SettingsViewMetrics {
    static let sectionContentPadding: CGFloat = 22
    static let sectionInnerSpacing: CGFloat = 22
}

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ReadOnlyModeCard(model: model)
                MinimizeToMenuBarCard(model: model)
                SSHConfigFormattingCard(model: model)
                SSHConfigBackupsCard(model: model)
                SSHDirectoryCard(model: model)
                ExternalToolsCard(model: model)
                HStack {
                    Spacer()
                    SettingsFooterAttribution()
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            model.workspaceCoordinator.refreshSSHKeygenStatus()
        }
    }
}

private struct SettingsFooterAttribution: View {
    @State private var heartScale: CGFloat = 1
    @State private var isLinkHovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Vibecoded with ")

            Image(systemName: "heart.fill")
                .foregroundStyle(Color(red: 0.64, green: 0.12, blue: 0.20))
                .scaleEffect(heartScale)
                .padding(.horizontal, 2)

            Text(" by ")

            Link("Stmol", destination: URL(string: "https://github.com/Stmol")!)
                .underline()
                .foregroundStyle(.tint)
                .onHover { hovering in
                    guard hovering != isLinkHovered else {
                        return
                    }

                    isLinkHovered = hovering

                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }

            Text(" and AI. Free & Open Source.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .onAppear {
            animateHeartBeat()
        }
    }

    private func animateHeartBeat() {
        heartScale = 1

        withAnimation(.easeInOut(duration: 0.18)) {
            heartScale = 1.26
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeInOut(duration: 0.12)) {
                heartScale = 1.06
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            withAnimation(.easeInOut(duration: 0.16)) {
                heartScale = 1.22
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
            withAnimation(.easeInOut(duration: 0.22)) {
                heartScale = 1
            }
        }
    }
}

private struct MinimizeToMenuBarCard: View {
    @Bindable var model: AppModel

    var body: some View {
        InfoCard(padding: SettingsViewMetrics.sectionContentPadding) {
            HStack(alignment: .top, spacing: 14) {
                MinimizeToMenuBarIcon()
                MinimizeToMenuBarContent(model: model)
            }
        }
    }
}

private struct MinimizeToMenuBarIcon: View {
    var body: some View {
        Image(systemName: "menubar.dock.rectangle")
            .font(.title2)
            .foregroundStyle(.tint)
            .frame(width: 32)
    }
}

private struct MinimizeToMenuBarContent: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Minimize to Menu Bar")
                    .font(.headline)
                Text("Hides the Dock icon and keeps the app available from the menu bar when the yellow window button is clicked.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: $model.isMinimizeToMenuBarEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Hide the app in the menu bar instead of minimizing it to the Dock")
        }
    }
}

private struct ReadOnlyModeCard: View {
    @Bindable var model: AppModel

    var body: some View {
        InfoCard(padding: SettingsViewMetrics.sectionContentPadding) {
            HStack(alignment: .top, spacing: 14) {
                ReadOnlyModeIcon()
                ReadOnlyModeContent(model: model)
            }
        }
    }
}

private struct ReadOnlyModeIcon: View {
    var body: some View {
        Image(systemName: "shield")
            .font(.title2)
            .foregroundStyle(.tint)
            .frame(width: 32)
    }
}

private struct ReadOnlyModeContent: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Read-only")
                    .font(.headline)
                Text("Prevents editing, overwriting, renaming, or deleting existing SSH files.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: $model.isReadOnlyModeEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Allow viewing, copying, and creating new key files while blocking destructive file changes.")
        }
    }
}

private struct SSHDirectoryCard: View {
    @Bindable var model: AppModel

    var body: some View {
        InfoCard(padding: SettingsViewMetrics.sectionContentPadding) {
            HStack(alignment: .top, spacing: 14) {
                SSHDirectoryIcon()
                SSHDirectoryContent(model: model)
            }
        }
    }
}

private struct SSHDirectoryIcon: View {
    var body: some View {
        Image(systemName: "folder.badge.gearshape")
            .font(.title2)
            .foregroundStyle(.tint)
            .frame(width: 32)
    }
}

private struct SSHDirectoryContent: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsViewMetrics.sectionInnerSpacing) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SSH Keys Directory")
                    .font(.headline)
                Text("The app lists and manages SSH keys from this directory.")
                    .foregroundStyle(.secondary)
            }

            SSHDirectoryPathRow(model: model)
        }
    }
}

private struct SSHDirectoryPathRow: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SSHDirectoryPathLabel(path: SSHWorkspacePath.displayPath(for: model.sshDirectoryPath))
            Spacer(minLength: 0)

            if model.isChangingSSHDirectory {
                ProgressView()
                    .controlSize(.small)
            }

            ChooseFolderButton(isDisabled: model.isChangingSSHDirectory) {
                chooseFolder()
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose SSH Directory"
        panel.message = "Select the directory that contains SSH keys and the SSH config file."
        panel.prompt = "Use Directory"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: model.sshDirectoryPath, isDirectory: true)

        guard panel.runModal() == .OK, let selectedURL = panel.urls.first else {
            return
        }

        Task {
            await model.workspaceCoordinator.changeSSHDirectory(to: selectedURL.path)
        }
    }
}

private struct SSHDirectoryPathLabel: View {
    let path: String

    var body: some View {
        Text(path)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChooseFolderButton: View {
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        AppButton("Choose Folder...", systemImage: "folder", action: action)
            .disabled(isDisabled)
            .help("Choose the SSH workspace directory")
    }
}

private struct SSHConfigFormattingCard: View {
    @Bindable var model: AppModel

    var body: some View {
        InfoCard(padding: SettingsViewMetrics.sectionContentPadding) {
            HStack(alignment: .top, spacing: 14) {
                SSHConfigFormattingIcon()
                SSHConfigFormattingContent(model: model)
            }
        }
    }
}

private struct SSHConfigFormattingIcon: View {
    var body: some View {
        Image(systemName: "text.alignleft")
            .font(.title2)
            .foregroundStyle(.tint)
            .frame(width: 32)
    }
}

private struct SSHConfigFormattingContent: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SSH Config Formatting")
                    .font(.headline)
                Text("Choose the indentation used for properties inside Host blocks.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            AppFormMenuPicker(
                selection: $model.hostPropertyIndentation,
                items: SSHConfigHostPropertyIndentation.allCases.map {
                    AppFormMenuItem(title: $0.title, value: $0)
                },
                help: "Choose whether Host properties are written with 2 or 4 leading spaces"
            )
            .frame(width: 128, alignment: .leading)
        }
    }
}

private struct SSHConfigBackupsCard: View {
    @Bindable var model: AppModel

    var body: some View {
        InfoCard(padding: SettingsViewMetrics.sectionContentPadding) {
            HStack(alignment: .top, spacing: 14) {
                SSHConfigBackupsIcon()
                SSHConfigBackupsContent(model: model)
            }
        }
    }
}

private struct SSHConfigBackupsIcon: View {
    var body: some View {
        Image(systemName: "clock.arrow.circlepath")
            .font(.title2)
            .foregroundStyle(.tint)
            .frame(width: 32)
    }
}

private struct SSHConfigBackupsContent: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SSH Config Backups")
                    .font(.headline)
                Text("Keep incremental copies next to the config file before each overwrite.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            AppFormMenuPicker(
                selection: $model.configBackupLimit,
                items: (SSHConfigBackupLimit.minimum...SSHConfigBackupLimit.maximum).map {
                    AppFormMenuItem(title: backupLimitTitle(for: $0), value: $0)
                },
                help: "Choose how many config backups to keep"
            )
            .frame(width: 128, alignment: .leading)
        }
    }

    private func backupLimitTitle(for limit: Int) -> String {
        limit == 0 ? "Off" : "\(limit)"
    }
}

private struct ExternalToolsCard: View {
    @Bindable var model: AppModel

    var body: some View {
        InfoCard(padding: SettingsViewMetrics.sectionContentPadding) {
            HStack(alignment: .top, spacing: 14) {
                ExternalToolsIcon()
                ExternalToolsContent(model: model)
            }
        }
    }
}

private struct ExternalToolsIcon: View {
    var body: some View {
        Image(systemName: "terminal")
            .font(.title2)
            .foregroundStyle(.tint)
            .frame(width: 32)
    }
}

private struct ExternalToolsContent: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: SettingsViewMetrics.sectionInnerSpacing) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 12) {
                        Text("SSH Keygen Binary")
                            .font(.headline)

                        ExternalToolStatusBadge(status: model.sshKeygenStatus)

                        Spacer(minLength: 0)
                    }

                    Text("Choose the binaries used for SSH operations when they are not available at the default system path.")
                        .foregroundStyle(.secondary)
                }

                ExternalToolRow(
                    tool: .sshKeygen,
                    path: model.sshKeygenPath,
                    onChoose: chooseSSHKeygen,
                    onReset: {
                        Task {
                            await model.workspaceCoordinator.resetSSHKeygenPath()
                        }
                    }
                )
            }

            if let warningMessage = model.sshKeygenStatus.warningMessage {
                ExternalToolWarning(message: warningMessage)
            }
        }
    }

    private func chooseSSHKeygen() {
        let panel = NSOpenPanel()
        panel.title = "Choose ssh-keygen Binary"
        panel.message = "Select the ssh-keygen executable used to generate keys and change passphrases."
        panel.prompt = "Use Binary"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: model.sshKeygenPath).deletingLastPathComponent()

        guard panel.runModal() == .OK, let selectedURL = panel.urls.first else {
            return
        }

        Task {
            await model.workspaceCoordinator.setSSHKeygenPath(selectedURL.path)
        }
    }
}

private struct ExternalToolRow: View {
    let tool: ExternalTool
    let path: String
    let onChoose: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                SSHDirectoryPathLabel(path: ExternalToolPath.displayPath(for: path))
                AppButton("Choose...", systemImage: "folder", action: onChoose)
                    .help("Choose the ssh-keygen binary")
                AppButton("Reset", systemImage: "arrow.counterclockwise", action: onReset)
                    .disabled(path == tool.defaultPath)
                    .help("Reset to the default system path")
            }
        }
    }
}

private struct ExternalToolStatusBadge: View {
    let status: ExternalToolStatus

    var body: some View {
        Label(status.title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor, in: Capsule())
            .accessibilityLabel("ssh-keygen status: \(status.title)")
    }

    private var systemImage: String {
        status.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var foregroundColor: Color {
        status.isAvailable ? .green : .orange
    }

    private var backgroundColor: Color {
        foregroundColor.opacity(0.14)
    }
}

private struct ExternalToolWarning: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 18)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.22), lineWidth: 1)
        }
    }
}
