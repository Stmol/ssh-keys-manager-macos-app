import SwiftUI

protocol SortOrderOption: CaseIterable, Identifiable, Equatable {
    var title: String { get }
}

struct SortOrderMenu<Option: SortOrderOption>: View {
    @Binding var sortOrder: Option
    let help: String
    let accessibilityLabel: String

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            ToolbarIcon(systemName: "arrow.up.arrow.down", isHovered: isHovered)
        }
        .buttonStyle(AppToolbarButtonStyle())
        .frame(width: 28, height: 28)
        .onHover { isHovered = isEnabled && $0 }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            SortOrderOptionsPopover(
                sortOrder: $sortOrder,
                isPresented: $isPresented
            )
        }
        .help(help)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct SortOrderOptionsPopover<Option: SortOrderOption>: View {
    @Binding var sortOrder: Option
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(Option.allCases)) { order in
                AppPopoverOptionButton(
                    title: order.title,
                    isSelected: sortOrder == order
                ) {
                    sortOrder = order
                    isPresented = false
                }
            }
        }
        .padding(.vertical, 6)
        .frame(width: 190)
    }
}
