//
//  ConnectivityMonitor.swift
//  ProofOfPath
//

import Foundation
import Network

/// Reports when the device gains or loses a network path, so the app can
/// reconnect as soon as the internet is back instead of waiting for a retry.
final class ConnectivityMonitor: @unchecked Sendable {

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.proofofpath.connectivity")
    private var lastSatisfied: Bool?

    /// Called on the main actor with `true` when a usable path appears.
    func start(_ onChange: @escaping @MainActor (Bool) -> Void) {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let satisfied = path.status == .satisfied
            guard satisfied != self.lastSatisfied else { return }
            self.lastSatisfied = satisfied
            Task { @MainActor in onChange(satisfied) }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
