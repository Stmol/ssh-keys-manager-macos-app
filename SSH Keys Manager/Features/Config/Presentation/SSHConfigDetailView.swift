import SwiftUI

struct SSHConfigDetailView: View {
    let entry: SSHConfigEntry?
    let emptyState: AppEmptyStateContent
    let onEdit: (SSHConfigEntry) -> Void
    let onDelete: (SSHConfigEntry) -> Void

    var body: some View {
        if let entry {
            SSHConfigDetailForm(entry: entry, onEdit: onEdit, onDelete: onDelete)
        } else {
            AppEmptyStateView(content: emptyState)
        }
    }
}

private struct SSHConfigDetailForm: View {
    private let contentSpacing: CGFloat = 14

    let entry: SSHConfigEntry
    let onEdit: (SSHConfigEntry) -> Void
    let onDelete: (SSHConfigEntry) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                SSHConfigTitleSection(entry: entry)
                SSHConfigFieldsSection(entry: entry)
                SSHConfigActionsSection(entry: entry, onEdit: onEdit, onDelete: onDelete)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct SSHConfigTitleSection: View {
    let entry: SSHConfigEntry

    var body: some View {
        InfoCard {
            DetailTitle(
                title: entry.host,
                subtitle: entry.hostName,
                systemImage: "doc.text.magnifyingglass"
            )
        }
    }
}

private struct SSHConfigFieldsSection: View {
    private let detailLabelWidth: CGFloat = 110

    let entry: SSHConfigEntry

    var body: some View {
        InfoCard(spacing: 8, padding: 16) {
            ForEach(entry.fields) { field in
                DetailField(
                    title: field.name,
                    value: field.value,
                    isMonospaced: true,
                    truncatesValue: true,
                    labelWidth: detailLabelWidth,
                    copyHelpText: supportsCopy(field.name) ? "Copy \(field.name) to clipboard" : nil
                )
            }
        }
    }

    private func supportsCopy(_ title: String) -> Bool {
        SSHConfigHostPropertyDefinition.isIdentityFilePropertyName(title)
    }
}

private struct SSHConfigActionsSection: View {
    let entry: SSHConfigEntry
    let onEdit: (SSHConfigEntry) -> Void
    let onDelete: (SSHConfigEntry) -> Void

    var body: some View {
        InfoCard(spacing: 12, padding: 16) {
            HStack {
                AppButton("Edit Entry", systemImage: "pencil") {
                    onEdit(entry)
                }

                AppButton("Delete Entry", systemImage: "trash", tone: .destructive) {
                    onDelete(entry)
                }
            }
        }
    }
}
