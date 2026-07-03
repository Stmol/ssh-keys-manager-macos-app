import SwiftUI

struct AddSSHConfigHostView: View {
    let configPath: String
    let identityFileOptions: [SSHConfigIdentityFileOption]
    let onSave: (SSHConfigHostSaveRequest) async throws -> Void

    var body: some View {
        SSHConfigHostEditorView(
            mode: .add,
            configPath: configPath,
            identityFileOptions: identityFileOptions,
            initialHost: "",
            initialProperties: [
                .init(name: "HostName"),
                .init(name: "User"),
                .init(name: "Port"),
                .init(name: "IdentityFile")
            ],
            onSave: onSave
        )
    }
}

struct EditSSHConfigHostView: View {
    let entry: SSHConfigEntry
    let configPath: String
    let identityFileOptions: [SSHConfigIdentityFileOption]
    let onSave: (SSHConfigHostSaveRequest) async throws -> Void

    var body: some View {
        SSHConfigHostEditorView(
            mode: .edit,
            configPath: configPath,
            identityFileOptions: identityFileOptions,
            initialHost: entry.host,
            initialProperties: entry.editableProperties,
            onSave: onSave
        )
    }
}

private enum SSHConfigHostEditorMode {
    case add
    case edit

    var title: String {
        switch self {
        case .add:
            return "Add Host Entry"
        case .edit:
            return "Edit Host Entry"
        }
    }

    var saveTitle: String {
        switch self {
        case .add:
            return "Add Host"
        case .edit:
            return "Save Changes"
        }
    }

    var helperText: String {
        switch self {
        case .add:
            return "The new Host block will be appended to the end of the config file with a blank line before it."
        case .edit:
            return "Changes will replace the selected Host block in the config file."
        }
    }
}

private enum SSHConfigPropertyMoveDirection {
    case up
    case down
}

private struct SSHConfigHostEditorView: View {
    private let modalHorizontalPadding: CGFloat = 24

    let mode: SSHConfigHostEditorMode
    let configPath: String
    let identityFileOptions: [SSHConfigIdentityFileOption]
    let onSave: (SSHConfigHostSaveRequest) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var host: String
    @State private var properties: [SSHConfigHostPropertyValue]
    @State private var submitController = AsyncActionController()
    @State private var moveControlSnapshot: [SSHConfigHostPropertyValue.ID: SSHConfigPropertyMoveAvailability] = [:]
    @State private var moveControlResetTask: Task<Void, Never>?

    init(
        mode: SSHConfigHostEditorMode,
        configPath: String,
        identityFileOptions: [SSHConfigIdentityFileOption],
        initialHost: String,
        initialProperties: [SSHConfigHostPropertyValue],
        onSave: @escaping (SSHConfigHostSaveRequest) async throws -> Void
    ) {
        self.mode = mode
        self.configPath = configPath
        self.identityFileOptions = identityFileOptions
        self.onSave = onSave
        _host = State(initialValue: initialHost)
        _properties = State(initialValue: initialProperties)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DetailTitle(
                title: mode.title,
                subtitle: configPath,
                systemImage: "server.rack"
            )

            VStack(alignment: .leading, spacing: 12) {
                AppFormTextField("Host alias", text: $host)

                Text(mode.helperText)
                    .appSheetSupportingText()
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Text("Properties")
                        .font(.headline)

                    Spacer()

                    AddSSHConfigPropertyMenu(
                        definitions: availablePropertyDefinitions
                    ) { definition in
                        properties.append(.init(name: definition.name))
                    }
                    .disabled(submitController.isPerforming || availablePropertyDefinitions.isEmpty)
                }
                .padding(.horizontal, modalHorizontalPadding)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(properties.enumerated()), id: \.element.id) { index, property in
                            let moveAvailability = moveAvailability(for: property.id, at: index)
                            SSHConfigPropertyEditorRow(
                                property: binding(for: property),
                                propertyDefinitions: propertyDefinitions(for: property),
                                identityFileOptions: identityFileOptions,
                                canMoveUp: moveAvailability.canMoveUp,
                                canMoveDown: moveAvailability.canMoveDown,
                                onMoveUp: {
                                    moveProperty(withID: property.id, direction: .up)
                                },
                                onMoveDown: {
                                    moveProperty(withID: property.id, direction: .down)
                                },
                                onDelete: {
                                    removeProperty(withID: property.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, modalHorizontalPadding)
                    .padding(.vertical, 2)
                    .animation(propertyReorderAnimation, value: properties.map(\.id))
                }
                .frame(minHeight: 220, maxHeight: 320)
            }
            .padding(.horizontal, -modalHorizontalPadding)

            if let errorMessage = submitController.errorMessage {
                Text(errorMessage)
                    .appSheetSupportingText()
                    .foregroundStyle(.red)
            }

            HStack {
                if submitController.isPerforming {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                AppButton("Cancel", action: dismiss.callAsFunction)
                    .disabled(submitController.isPerforming)

                AppButton(mode.saveTitle, tone: .primary, action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(modalHorizontalPadding)
        .frame(width: 660)
        .disabled(submitController.isPerforming)
        .onDisappear {
            moveControlResetTask?.cancel()
            moveControlResetTask = nil
            submitController.cancel()
        }
    }

    private var canSave: Bool {
        !submitController.isPerforming
            && !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasUniquePropertyNames
    }

    private var propertyReorderAnimation: Animation {
        .spring(response: 0.3, dampingFraction: 0.88)
    }

    private var availablePropertyDefinitions: [SSHConfigHostPropertyDefinition] {
        let selectedNames = selectedPropertyNames()
        return SSHConfigHostPropertyDefinition.all.filter { definition in
            !selectedNames.contains(normalizedPropertyName(definition.name))
        }
    }

    private var hasUniquePropertyNames: Bool {
        let names = properties.map { normalizedPropertyName($0.name) }
        return Set(names).count == names.count
    }

    private func propertyDefinitions(for property: SSHConfigHostPropertyValue) -> [SSHConfigHostPropertyDefinition] {
        let currentName = normalizedPropertyName(property.name)
        let unavailableNames = selectedPropertyNames(excluding: property.id)

        return SSHConfigHostPropertyDefinition.all.filter { definition in
            let definitionName = normalizedPropertyName(definition.name)
            return definitionName == currentName || !unavailableNames.contains(definitionName)
        }
    }

    private func selectedPropertyNames(excluding excludedID: SSHConfigHostPropertyValue.ID? = nil) -> Set<String> {
        Set(
            properties
                .filter { $0.id != excludedID }
                .map { normalizedPropertyName($0.name) }
        )
    }

    private func normalizedPropertyName(_ name: String) -> String {
        SSHConfigHostPropertyDefinition.normalizedPropertyName(name)
    }

    private func binding(for property: SSHConfigHostPropertyValue) -> Binding<SSHConfigHostPropertyValue> {
        Binding(
            get: {
                properties.first { $0.id == property.id } ?? property
            },
            set: { updatedProperty in
                guard let index = properties.firstIndex(where: { $0.id == property.id }) else {
                    return
                }

                properties[index] = updatedProperty
            }
        )
    }

    private func removeProperty(withID id: SSHConfigHostPropertyValue.ID) {
        properties.removeAll { $0.id == id }
    }

    private func moveAvailability(
        for id: SSHConfigHostPropertyValue.ID,
        at index: Int
    ) -> SSHConfigPropertyMoveAvailability {
        moveControlSnapshot[id] ?? SSHConfigPropertyMoveAvailability(
            canMoveUp: index > 0,
            canMoveDown: index < properties.index(before: properties.endIndex)
        )
    }

    private func moveProperty(withID id: SSHConfigHostPropertyValue.ID, direction: SSHConfigPropertyMoveDirection) {
        guard let sourceIndex = properties.firstIndex(where: { $0.id == id }) else {
            return
        }

        let destinationIndex: Int
        switch direction {
        case .up:
            guard sourceIndex > 0 else {
                return
            }
            destinationIndex = properties.index(before: sourceIndex)
        case .down:
            guard sourceIndex < properties.index(before: properties.endIndex) else {
                return
            }
            destinationIndex = properties.index(after: sourceIndex)
        }

        moveControlSnapshot = Dictionary(
            uniqueKeysWithValues: properties.enumerated().map { index, property in
                (
                    property.id,
                    SSHConfigPropertyMoveAvailability(
                        canMoveUp: index > 0,
                        canMoveDown: index < properties.index(before: properties.endIndex)
                    )
                )
            }
        )
        moveControlResetTask?.cancel()

        withAnimation(propertyReorderAnimation) {
            properties.swapAt(sourceIndex, destinationIndex)
        }

        moveControlResetTask = Task {
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                moveControlSnapshot = [:]
                moveControlResetTask = nil
            }
        }
    }

    private func save() {
        guard canSave else {
            return
        }

        let request = SSHConfigHostSaveRequest(host: host, properties: properties)

        submitController.run(
            operation: {
                try await onSave(request)
            },
            onSuccess: dismiss.callAsFunction
        )
    }
}

private extension SSHConfigEntry {
    var editableProperties: [SSHConfigHostPropertyValue] {
        fields
            .filter { $0.normalizedName != "host" }
            .map { SSHConfigHostPropertyValue(name: $0.name, value: $0.value) }
    }
}

private struct SSHConfigPropertyMoveAvailability {
    let canMoveUp: Bool
    let canMoveDown: Bool
}

private struct AddSSHConfigPropertyMenu: View {
    let definitions: [SSHConfigHostPropertyDefinition]
    let onSelect: (SSHConfigHostPropertyDefinition) -> Void

    var body: some View {
        AppFormMenuButton(
            title: "Add Property",
            systemImage: "plus.circle",
            items: menuItems,
            help: "Add SSH config property",
            onSelect: onSelect
        )
        .frame(width: 190)
    }

    private var menuItems: [AppFormMenuItem<SSHConfigHostPropertyDefinition>] {
        definitions.map {
            AppFormMenuItem(title: $0.name, value: $0)
        }
    }
}

private struct SSHConfigPropertyEditorRow: View {
    private let propertyPickerWidth: CGFloat = 190
    private let moveControlsWidth: CGFloat = 12
    private let identityButtonWidth: CGFloat = 64

    @Binding var property: SSHConfigHostPropertyValue
    let propertyDefinitions: [SSHConfigHostPropertyDefinition]
    let identityFileOptions: [SSHConfigIdentityFileOption]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                SSHConfigPropertyMoveControls(
                    canMoveUp: canMoveUp,
                    canMoveDown: canMoveDown,
                    onMoveUp: onMoveUp,
                    onMoveDown: onMoveDown
                )
                .frame(width: moveControlsWidth)

                AppFormMenuPicker(
                    selection: $property.name,
                    items: propertyMenuItems,
                    help: "Select SSH config property"
                )
                .frame(width: propertyPickerWidth)
            }
            .frame(height: AppFormControlMetrics.height, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                if SSHConfigHostPropertyDefinition.isIdentityFilePropertyName(property.name) {
                    HStack(alignment: .top, spacing: 10) {
                        AppFormTextField("Value", text: $property.value)

                        AppFormIconMenuButton(
                            leadingSystemImage: "key.horizontal",
                            items: identityFileMenuItems,
                            help: identityFileMenuHelp,
                            onSelect: { option in
                                property.value = option.value
                            }
                        )
                        .frame(width: identityButtonWidth)
                        .disabled(identityFileOptions.isEmpty)
                    }
                } else {
                    AppFormTextField("Value", text: $property.value)
                }

                Text(property.definition.comment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            AppFormPlainIconButton(
                systemImage: "minus.circle",
                help: "Remove property",
                action: onDelete
            )
            .padding(.top, 6)
            .accessibilityLabel("Remove \(property.name)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var propertyMenuItems: [AppFormMenuItem<String>] {
        propertyDefinitions.map {
            AppFormMenuItem(title: $0.name, value: $0.name)
        }
    }

    private var identityFileMenuItems: [AppFormMenuItem<SSHConfigIdentityFileOption>] {
        identityFileOptions.map { option in
            AppFormMenuItem(
                title: SSHConfigIdentityFileMenuPresentation.menuTitle(
                    for: option,
                    allOptions: identityFileOptions
                ),
                value: option
            )
        }
    }

    private var identityFileMenuHelp: String {
        if identityFileOptions.isEmpty {
            return "No loaded private keys available"
        }

        return "Select loaded private key path"
    }
}

private struct SSHConfigPropertyMoveControls: View {
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            moveButton(
                systemName: "chevron.up",
                help: "Move property up",
                isVisible: canMoveUp,
                action: onMoveUp
            )

            moveButton(
                systemName: "chevron.down",
                help: "Move property down",
                isVisible: canMoveDown,
                action: onMoveDown
            )
        }
    }

    @ViewBuilder
    private func moveButton(
        systemName: String,
        help: String,
        isVisible: Bool,
        action: @escaping () -> Void
    ) -> some View {
        AppFormPlainIconButton(systemImage: systemName, help: help, action: action)
            .disabled(!isVisible)
    }
}

enum SSHConfigIdentityFileMenuPresentation {
    static func menuTitle(
        for option: SSHConfigIdentityFileOption,
        allOptions: [SSHConfigIdentityFileOption]
    ) -> String {
        let duplicateNames = Set(
            Dictionary(grouping: allOptions, by: { SSHConfigHostPropertyDefinition.normalizedPropertyName($0.keyName) })
                .filter { $0.value.count > 1 }
                .map(\.key)
        )

        if duplicateNames.contains(SSHConfigHostPropertyDefinition.normalizedPropertyName(option.keyName)) {
            return "\(option.keyName) • \(option.value)"
        }

        return option.keyName
    }
}
