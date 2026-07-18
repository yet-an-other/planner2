import Foundation
import Network

/// The production connectivity monitor, backed by `NWPathMonitor`.
///
/// Path updates arrive event-driven on a private queue — no polling, no
/// timers, no background processing — and only an offline-to-online
/// transition is reported to the module, on the main actor. Mutable state
/// is confined to the main actor; the underlying monitor is thread-safe.
final class NWPathConnectivityMonitor: GoogleConnectionConnectivityMonitoring,
    @unchecked Sendable
{
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(
        label: "planner.google-account-connection.connectivity"
    )

    /// Whether the latest delivered path was unsatisfied. Only a return
    /// from this state counts as connectivity returning.
    private var isOffline = false

    func start(onConnectivityReturn: @escaping @MainActor () -> Void) {
        monitor.pathUpdateHandler = { [weak self] path in
            let isSatisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                if isSatisfied, self.isOffline {
                    self.isOffline = false
                    onConnectivityReturn()
                } else if !isSatisfied {
                    self.isOffline = true
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.pathUpdateHandler = nil
        monitor.cancel()
    }
}
