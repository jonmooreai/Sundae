import Foundation
import Network
import Observation

/// Tells the app when the network comes back so a dump queued offline can post.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    /// Called on the main actor whenever reachability flips, with the new value.
    var onChange: ((Bool) -> Void)?
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
                self.onChange?(online)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.sundae.app.network"))
    }
}
