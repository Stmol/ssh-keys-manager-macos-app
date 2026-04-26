import SwiftUI

struct SSHConfigEntryList: View {
    let entries: [SSHConfigEntry]
    let isLoading: Bool
    let errorMessage: String?
    let isConfigFileMissing: Bool
    @Binding var selectedEntryID: SSHConfigEntry.ID?

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)

                    Text("Loading SSH config...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                AppEmptyStateView(
                    content: AppEmptyStateContent(
                        title: "Unable to Load Config",
                        message: errorMessage,
                        systemImage: "exclamationmark.triangle"
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            if entries.isEmpty || isConfigFileMissing {
                                Spacer(minLength: 0)
                            } else {
                                ForEach(entries) { entry in
                                    SSHConfigRow(entry: entry, isSelected: selectedEntryID == entry.id)
                                        .onTapGesture {
                                            selectedEntryID = entry.id
                                        }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                    }
                    .scrollContentBackground(.hidden)
                    .scrollBounceBehavior(.always)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
