import Foundation
import Network

// Watches connectivity so the app can act the moment the network returns.
//
// The case this exists for: as a login item the app starts during the post-reboot
// login rush, before Wi-Fi is up. Without this, the first token refresh fails and
// nothing ever tries again.
@MainActor
final class NetworkMonitor {

    static let shared = NetworkMonitor()

    private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private var listeners: [() -> Void] = []

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in NetworkMonitor.shared.apply(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "com.adergunov.harmonic.network"))
    }

    /// Registers a handler fired on every offline → online transition.
    func onCameOnline(_ handler: @escaping () -> Void) {
        listeners.append(handler)
    }

    // MARK: - Private

    private func apply(online: Bool) {
        let wasOffline = !isOnline
        isOnline = online
        guard online, wasOffline else { return }
        listeners.forEach { $0() }
    }
}
