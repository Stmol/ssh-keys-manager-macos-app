import Foundation

@MainActor
extension AppModel {
    func invalidateConfigHostReachability() {
        configHostReachabilityTask?.cancel()
        configHostReachabilityTask = nil
        configHostCheckGeneration += 1
        isCheckingConfigHosts = false
        configHostStatuses = [:]
    }

    func showConfigReachabilityErrorSummary(count: Int) {
        guard count > 0 else {
            return
        }

        let noun = count == 1 ? "host" : "hosts"
        showNotification("Could not fully check \(count) \(noun)", kind: .warning)
    }
}
