import Foundation

struct SSHConfigEntry: Identifiable, Hashable {
    let id: String
    let host: String
    let lineNumber: Int
    let fields: [SSHConfigField]
    let sourceFingerprint: String

    nonisolated init(
        id: String,
        host: String,
        lineNumber: Int = 0,
        fields: [SSHConfigField],
        sourceFingerprint: String = ""
    ) {
        self.id = id
        self.host = host
        self.lineNumber = lineNumber
        self.fields = fields
        self.sourceFingerprint = sourceFingerprint
    }

    var hostName: String {
        fields.first { $0.normalizedName == "hostname" }?.value ?? host
    }

    var user: String? {
        fields.first { $0.normalizedName == "user" }?.value
    }

    static func fuzzyMatches(query: String, in entry: SSHConfigEntry) -> Bool {
        guard !query.isEmpty else { return true }

        if SSHKeyItem.fuzzyMatch(query: query, in: entry.hostName) { return true }
        if SSHKeyItem.fuzzyMatch(query: query, in: entry.host) { return true }

        for field in entry.fields where field.normalizedName == "identityfile" {
            if SSHKeyItem.fuzzyMatch(query: query, in: field.value) { return true }
        }

        if let user = entry.user, SSHKeyItem.fuzzyMatch(query: query, in: user) { return true }

        return false
    }
}
