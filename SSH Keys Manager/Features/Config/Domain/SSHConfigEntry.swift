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
}
