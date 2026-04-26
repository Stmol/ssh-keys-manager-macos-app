import Foundation

enum SSHConfigSortOrder: String, SortOrderOption {
    case original
    case hostAscending
    case hostDescending
    case hostNameAscending
    case hostNameDescending

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .original:
            return "Default"
        case .hostAscending:
            return "Host A-Z"
        case .hostDescending:
            return "Host Z-A"
        case .hostNameAscending:
            return "HostName A-Z"
        case .hostNameDescending:
            return "HostName Z-A"
        }
    }
}

extension [SSHConfigEntry] {
    func sortedBy(_ order: SSHConfigSortOrder) -> [SSHConfigEntry] {
        guard order != .original else {
            return self
        }

        return sorted { lhs, rhs in
            switch order {
            case .original:
                return false
            case .hostAscending:
                return lhs.host.localizedStandardCompare(rhs.host) == .orderedAscending
            case .hostDescending:
                return lhs.host.localizedStandardCompare(rhs.host) == .orderedDescending
            case .hostNameAscending:
                return lhs.hostName.localizedStandardCompare(rhs.hostName) == .orderedAscending
            case .hostNameDescending:
                return lhs.hostName.localizedStandardCompare(rhs.hostName) == .orderedDescending
            }
        }
    }
}
