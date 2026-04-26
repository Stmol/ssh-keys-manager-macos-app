import SwiftUI

struct AppShellView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderTabsView(model: model)
            Divider()
            SelectedTabContentView(model: model)
        }
        .background(.background)
        .notificationOverlay($model.notification)
    }
}

private struct SelectedTabContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.selectedTab {
            case .keys:
                SSHKeysView(model: model)
            case .config:
                SSHConfigView(model: model)
            case .settings:
                SettingsView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
