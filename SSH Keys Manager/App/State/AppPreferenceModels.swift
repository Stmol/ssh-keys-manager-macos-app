import Foundation

enum SSHConfigBackupLimit {
    nonisolated static let minimum = 0
    nonisolated static let maximum = 5
    nonisolated static let `default` = 0

    nonisolated static func clamped(_ limit: Int) -> Int {
        min(max(limit, minimum), maximum)
    }
}

enum ReadOnlyModeRestrictionError: LocalizedError, Equatable {
    case unavailable

    var notificationMessage: String {
        "Operation is unavailable."
    }

    var errorDescription: String? {
        "Operation is unavailable. Exit Read-only mode to perform it."
    }
}

enum SSHConfigHostPropertyIndentation: Int, CaseIterable, Identifiable, Sendable {
    case twoSpaces = 2
    case fourSpaces = 4

    nonisolated static let `default`: Self = .fourSpaces

    nonisolated var id: Self { self }

    nonisolated var title: String {
        switch self {
        case .twoSpaces:
            "2 spaces"
        case .fourSpaces:
            "4 spaces"
        }
    }

    nonisolated var value: String {
        String(repeating: " ", count: rawValue)
    }
}
