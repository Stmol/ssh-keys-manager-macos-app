import Foundation
import Network

enum SSHConfigHostReachabilityStatus: Equatable, Sendable {
    case checking
    case reachable
    case unreachable
    case error
}

struct SSHHostReachabilityTarget: Equatable, Sendable {
    nonisolated let host: String
    nonisolated let port: UInt16
}

enum SSHHostReachabilityResolution: Equatable, Sendable {
    case unsupported
    case invalidConfiguration(String)
    case target(SSHHostReachabilityTarget)
}

enum SSHHostReachabilityCheckResult: Equatable, Sendable {
    case reachable
    case unreachable
    case error(String)
}

protocol SSHHostReachabilityChecking: Sendable {
    nonisolated func check(target: SSHHostReachabilityTarget, timeout: Duration) async -> SSHHostReachabilityCheckResult
}

struct SSHHostReachabilityChecker: SSHHostReachabilityChecking {
    nonisolated func check(target: SSHHostReachabilityTarget, timeout: Duration) async -> SSHHostReachabilityCheckResult {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(target.host),
                port: NWEndpoint.Port(rawValue: target.port) ?? .ssh,
                using: .tcp
            )
            let queue = DispatchQueue(label: "SSHHostReachabilityChecker.\(target.host).\(target.port)")
            let state = ReachabilityContinuationState()

            let finish: @Sendable (SSHHostReachabilityCheckResult) -> Void = { result in
                connection.stateUpdateHandler = nil
                connection.cancel()
                state.resume(continuation: continuation, result: result)
            }

            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    finish(.reachable)
                case .failed(let error):
                    finish(Self.classify(error))
                default:
                    break
                }
            }

            Task {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }

                finish(.unreachable)
            }

            connection.start(queue: queue)
        }
    }

    nonisolated static func classify(_ error: NWError) -> SSHHostReachabilityCheckResult {
        switch error {
        case .dns:
            return .unreachable
        case .posix(let code):
            switch code {
            case .ETIMEDOUT, .ECONNREFUSED, .EHOSTUNREACH, .ENETUNREACH, .EHOSTDOWN, .ENETDOWN, .ECONNRESET:
                return .unreachable
            default:
                return .error(error.localizedDescription)
            }
        default:
            return .error(error.localizedDescription)
        }
    }
}

enum SSHHostReachabilityResolver {
    nonisolated static func resolveTarget(for entry: SSHConfigEntry) -> SSHHostReachabilityResolution {
        let hostTokens = entry.host
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard hostTokens.count == 1, let hostAlias = hostTokens.first, isSupportedHostAlias(hostAlias) else {
            return .unsupported
        }

        let resolvedHost = entry.reachabilityHostName ?? hostAlias
        guard !resolvedHost.isEmpty else {
            return .invalidConfiguration("HostName is empty for \(hostAlias)")
        }

        guard isSupportedResolvedHost(resolvedHost) else {
            return .unsupported
        }

        guard let port = resolvePort(for: entry) else {
            return .invalidConfiguration("Port is invalid for \(hostAlias)")
        }

        return .target(SSHHostReachabilityTarget(host: resolvedHost, port: port))
    }

    private nonisolated static func isSupportedHostAlias(_ hostAlias: String) -> Bool {
        !hostAlias.contains("*")
            && !hostAlias.contains("?")
            && !hostAlias.contains("!")
    }

    private nonisolated static func isSupportedResolvedHost(_ resolvedHost: String) -> Bool {
        !resolvedHost.contains("%")
            && resolvedHost.split(whereSeparator: \.isWhitespace).count == 1
    }

    private nonisolated static func resolvePort(for entry: SSHConfigEntry) -> UInt16? {
        guard let rawPort = entry.port else {
            return 22
        }

        guard let port = UInt16(rawPort), port > 0 else {
            return nil
        }

        return port
    }
}

private final class ReachabilityContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var didResume = false

    nonisolated init() {}

    nonisolated func resume(
        continuation: CheckedContinuation<SSHHostReachabilityCheckResult, Never>,
        result: SSHHostReachabilityCheckResult
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard !didResume else {
            return
        }

        didResume = true
        continuation.resume(returning: result)
    }
}

private extension SSHConfigEntry {
    nonisolated var reachabilityHostName: String? {
        let hostName = fields
            .first { $0.normalizedName == "hostname" }?
            .value
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let hostName, !hostName.isEmpty else {
            return nil
        }

        return hostName
    }

    nonisolated var port: String? {
        let port = fields
            .first { $0.normalizedName == "port" }?
            .value
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let port, !port.isEmpty else {
            return nil
        }

        return port
    }
}
