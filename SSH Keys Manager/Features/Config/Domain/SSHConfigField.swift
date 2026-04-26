import Foundation

struct SSHConfigField: Identifiable, Hashable {
    let id: String
    let name: String
    let value: String
    let normalizedName: String

    nonisolated init(
        id: String,
        name: String,
        value: String,
        normalizedName: String
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.normalizedName = normalizedName
    }
}
