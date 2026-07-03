import Foundation

struct SSHConfigHostSaveRequest: Hashable, Sendable {
    var host: String
    var properties: [SSHConfigHostPropertyValue]

    nonisolated var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var writableProperties: [SSHConfigHostPropertyValue] {
        properties.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
