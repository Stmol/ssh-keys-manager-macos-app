import SwiftUI

struct SSHKeyList: View {
    let keys: [SSHKeyItem]
    let isLoading: Bool
    let errorMessage: String?
    @Binding var selectedKeyID: SSHKeyItem.ID?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading SSH keys...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                AppEmptyStateView(
                    content: AppEmptyStateContent(
                        title: "Unable to Load SSH Keys",
                        message: errorMessage,
                        systemImage: "exclamationmark.triangle"
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if keys.isEmpty {
                Spacer()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(keys) { key in
                            SSHKeyRow(key: key, isSelected: selectedKeyID == key.id)
                                .onTapGesture {
                                    selectedKeyID = key.id
                                }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .scrollBounceBehavior(.always)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
