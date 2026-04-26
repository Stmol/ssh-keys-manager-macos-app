import Foundation

enum SSHKeySortOrder: String, SortOrderOption {
    case nameAscending
    case nameDescending
    case createdAscending
    case createdDescending

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .nameAscending:
            return "Name A-Z"
        case .nameDescending:
            return "Name Z-A"
        case .createdAscending:
            return "Created Oldest First"
        case .createdDescending:
            return "Created Newest First"
        }
    }

    var systemImage: String {
        switch self {
        case .nameAscending, .createdAscending:
            return "arrow.up"
        case .nameDescending, .createdDescending:
            return "arrow.down"
        }
    }
}

extension [SSHKeyItem] {
    func sortedBy(_ order: SSHKeySortOrder) -> [SSHKeyItem] {
        sorted { lhs, rhs in
            switch order {
            case .nameAscending:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .nameDescending:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
            case .createdAscending:
                return lhs.createdAt < rhs.createdAt
            case .createdDescending:
                return lhs.createdAt > rhs.createdAt
            }
        }
    }
}
