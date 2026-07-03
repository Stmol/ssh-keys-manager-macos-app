import Foundation

extension SSHKeyItem {
    var defaultRenameName: String {
        switch kind {
        case .completePair, .privateKey:
            return name
        case .publicKey:
            return name.hasSuffix(".pub") ? String(name.dropLast(4)) : name
        }
    }

    var defaultDuplicateName: String {
        "\(defaultRenameName)-copy"
    }

    func canUseReplacementName(_ candidate: String) -> Bool {
        let trimmedName = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty
            && trimmedName != defaultRenameName
            && trimmedName.rangeOfCharacter(from: CharacterSet(charactersIn: "/:")) == nil
            && trimmedName != "."
            && trimmedName != ".."
    }
}
