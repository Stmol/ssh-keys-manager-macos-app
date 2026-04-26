import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case keys
    case config
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .keys:
            "Keys"
        case .config:
            "Config"
        case .settings:
            "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .keys:
            "key.horizontal"
        case .config:
            "doc.text.magnifyingglass"
        case .settings:
            "gearshape"
        }
    }

    var accessibilityLabel: String {
        "\(title) tab"
    }

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .keys:
            "1"
        case .config:
            "2"
        case .settings:
            "3"
        }
    }
}
