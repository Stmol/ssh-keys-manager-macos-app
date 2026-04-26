import Foundation

enum SSHKeyListKind: String, CaseIterable, Identifiable {
    case completePairs
    case otherKeys

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .completePairs:
            return "Complete Pairs"
        case .otherKeys:
            return "Other Files"
        }
    }
}
