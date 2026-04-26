import SwiftUI

struct DetailField: View {
    let title: String
    let value: String
    let systemImage: String?
    let isMonospaced: Bool
    let truncatesValue: Bool
    let labelWidth: CGFloat
    let copyHelpText: String?
    let onCopy: (() -> Void)?

    init(
        title: String,
        value: String,
        systemImage: String? = nil,
        isMonospaced: Bool = false,
        truncatesValue: Bool = false,
        labelWidth: CGFloat = 150,
        copyHelpText: String? = nil,
        onCopy: (() -> Void)? = nil
    ) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.isMonospaced = isMonospaced
        self.truncatesValue = truncatesValue
        self.labelWidth = labelWidth
        self.copyHelpText = copyHelpText
        self.onCopy = onCopy
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: rowHeight, alignment: .center)
            }

            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, height: rowHeight, alignment: .leading)

            Group {
                if let copyHelpText {
                    CopyableDetailValue(
                        value: value,
                        helpText: copyHelpText,
                        onCopy: onCopy
                    )
                } else {
                    Text(value)
                        .textSelection(.enabled)
                        .font(isMonospaced ? .system(.body, design: .monospaced) : .body)
                        .lineLimit(truncatesValue ? 1 : nil)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
                        .clipped(antialiased: false)
                }
            }
            .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
    }

    private var rowHeight: CGFloat {
        copyHelpText == nil ? 22 : CopyableDetailValue.rowHeight
    }
}
