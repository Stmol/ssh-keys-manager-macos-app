import Foundation

struct SSHConfigIdentityFileOption: Identifiable, Hashable, Sendable {
    let keyName: String
    let value: String

    var id: String {
        value
    }
}

enum SSHConfigIdentityFileCatalog {
    static func options(
        keys: [SSHKeyItem],
        otherKeys: [SSHKeyItem],
        homeDirectoryPath: String
    ) -> [SSHConfigIdentityFileOption] {
        let sortedOptions = (keys + otherKeys)
            .compactMap { key -> SSHConfigIdentityFileOption? in
                guard let privateKeyPath = key.privateKeyPath else {
                    return nil
                }

                return SSHConfigIdentityFileOption(
                    keyName: key.name,
                    value: sshFriendlyPath(privateKeyPath, homeDirectoryPath: homeDirectoryPath)
                )
            }
            .sorted { lhs, rhs in
                let nameComparison = lhs.keyName.localizedCaseInsensitiveCompare(rhs.keyName)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }

                let pathComparison = lhs.value.localizedCaseInsensitiveCompare(rhs.value)
                if pathComparison != .orderedSame {
                    return pathComparison == .orderedAscending
                }

                return lhs.value < rhs.value
            }

        var seenPaths = Set<String>()
        return sortedOptions.filter { option in
            seenPaths.insert(option.value).inserted
        }
    }

    private static func sshFriendlyPath(_ path: String, homeDirectoryPath: String) -> String {
        guard !homeDirectoryPath.isEmpty else {
            return path
        }

        if path == homeDirectoryPath {
            return "~"
        }

        let homePrefix = "\(homeDirectoryPath)/"
        guard path.hasPrefix(homePrefix) else {
            return path
        }

        return "~\(path.dropFirst(homeDirectoryPath.count))"
    }
}

struct SSHConfigHostPropertyDefinition: Identifiable, Hashable, Sendable {
    let name: String
    let comment: String

    var id: String {
        name
    }

    static let all: [SSHConfigHostPropertyDefinition] = [
        .init(name: "HostName", comment: "Real IP address or DNS name"),
        .init(name: "Port", comment: "SSH port, defaults to 22"),
        .init(name: "User", comment: "Remote user name"),
        .init(name: "IdentityFile", comment: "Private key path"),
        .init(name: "IdentitiesOnly", comment: "Use only configured identities"),
        .init(name: "PasswordAuthentication", comment: "Allow password authentication"),
        .init(name: "PubkeyAuthentication", comment: "Allow public key authentication"),
        .init(name: "KbdInteractiveAuthentication", comment: "Keyboard-interactive auth"),
        .init(name: "PreferredAuthentications", comment: "Authentication method order"),
        .init(name: "CertificateFile", comment: "Authentication certificate"),
        .init(name: "PKCS11Provider", comment: "Smart card provider"),
        .init(name: "ProxyCommand", comment: "Command used as proxy"),
        .init(name: "ProxyJump", comment: "Jump host chain"),
        .init(name: "LocalForward", comment: "Local port forwarding"),
        .init(name: "RemoteForward", comment: "Remote port forwarding"),
        .init(name: "DynamicForward", comment: "Local SOCKS proxy"),
        .init(name: "ServerAliveInterval", comment: "Keepalive interval in seconds"),
        .init(name: "ServerAliveCountMax", comment: "Missed keepalive limit"),
        .init(name: "ConnectTimeout", comment: "Connection timeout in seconds"),
        .init(name: "ForwardAgent", comment: "Forward ssh-agent"),
        .init(name: "AddKeysToAgent", comment: "Auto-add keys to agent"),
        .init(name: "IdentityAgent", comment: "Agent socket path or none"),
        .init(name: "ForwardX11", comment: "Forward X11"),
        .init(name: "ForwardX11Trusted", comment: "Trusted X11 forwarding"),
        .init(name: "XAuthLocation", comment: "xauth path"),
        .init(name: "StrictHostKeyChecking", comment: "Host key checking mode"),
        .init(name: "CheckHostIP", comment: "Check IP in known_hosts"),
        .init(name: "HostKeyAlias", comment: "known_hosts alias"),
        .init(name: "HostKeyAlgorithms", comment: "Allowed host key algorithms"),
        .init(name: "KnownHostsCommand", comment: "Known hosts command"),
        .init(name: "UpdateHostKeys", comment: "Update host keys"),
        .init(name: "VerifyHostKeyDNS", comment: "Verify keys via DNS SSHFP"),
        .init(name: "Ciphers", comment: "Allowed ciphers"),
        .init(name: "MACs", comment: "Allowed MAC algorithms"),
        .init(name: "KexAlgorithms", comment: "Key exchange algorithms"),
        .init(name: "HostbasedKeyTypes", comment: "Host-based auth key types"),
        .init(name: "PubkeyAcceptedKeyTypes", comment: "Accepted public key types"),
        .init(name: "SetEnv", comment: "Set remote environment variable"),
        .init(name: "SendEnv", comment: "Send local environment variables"),
        .init(name: "AcceptEnv", comment: "Server-side accepted variables"),
        .init(name: "ControlMaster", comment: "Multiplexing master mode"),
        .init(name: "ControlPath", comment: "Multiplexing socket path"),
        .init(name: "ControlPersist", comment: "Keep master connection open"),
        .init(name: "Compression", comment: "Enable compression"),
        .init(name: "LogLevel", comment: "SSH log level"),
        .init(name: "BatchMode", comment: "Disable interactive prompts"),
        .init(name: "RequestTTY", comment: "Request a TTY"),
        .init(name: "RemoteCommand", comment: "Remote command instead of shell"),
        .init(name: "EscapeChar", comment: "SSH escape character"),
        .init(name: "ExitOnForwardFailure", comment: "Exit if forwarding fails"),
        .init(name: "GSSAPIAuthentication", comment: "Kerberos/GSSAPI auth"),
        .init(name: "Tunnel", comment: "SSH tunnel mode"),
        .init(name: "TunnelDevice", comment: "Tunnel devices"),
        .init(name: "AddressFamily", comment: "inet, inet6, or any"),
        .init(name: "BindAddress", comment: "Local bind address"),
        .init(name: "BindInterface", comment: "Local bind interface"),
        .init(name: "NumberOfPasswordPrompts", comment: "Password prompt attempts"),
        .init(name: "StreamLocalBindMask", comment: "Unix socket permissions mask"),
        .init(name: "StreamLocalBindUnlink", comment: "Unlink socket before bind"),
        .init(name: "Include", comment: "Include another config file")
    ]

    private static let definitionsByName = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    static func definition(named name: String) -> SSHConfigHostPropertyDefinition {
        definitionsByName[name] ?? .init(name: name, comment: "Custom SSH config field")
    }

    static func normalizedPropertyName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isIdentityFilePropertyName(_ name: String) -> Bool {
        normalizedPropertyName(name) == "identityfile"
    }
}

struct SSHConfigHostPropertyValue: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var value: String

    init(id: UUID = UUID(), name: String, value: String = "") {
        self.id = id
        self.name = name
        self.value = value
    }

    var definition: SSHConfigHostPropertyDefinition {
        SSHConfigHostPropertyDefinition.definition(named: name)
    }
}
