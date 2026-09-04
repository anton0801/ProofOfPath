//
//  SyncCoordinator.swift
//  ProofOfPath
//
//  Drives push/pull against whatever backend is installed.
//

import Foundation

/// Owns the sync cycle. Inert while the backend is local, so it can be wired
/// into the app now and switched on by swapping the backend later.
@MainActor
final class SyncCoordinator {

    private let backend: DecisionBackend
    private var isRunning = false

    init(backend: DecisionBackend) {
        self.backend = backend
    }

    var isEnabled: Bool { backend.isRemote }

    var storageDescription: String { backend.storageDescription }

    /// One full cycle: push what is queued, then pull what changed.
    ///
    /// Returns `.notConfigured` immediately while the app is local-only, so
    /// callers can be written now and behave correctly the day a server exists.
    @discardableResult
    func synchronize(_ data: AppData) async -> SyncOutcome {
        guard backend.isRemote else { return .notConfigured }
        guard !isRunning else { return .upToDate }
        isRunning = true
        defer { isRunning = false }

        let pushOutcome = await backend.push(data)
        if case .failed(let reason) = pushOutcome { return .failed(reason) }

        let pullOutcome = await backend.pull(since: data.account.lastSuccessfulSyncAt)
        if case .failed(let reason) = pullOutcome { return .failed(reason) }

        let pushed: Int = {
            if case .applied(let count, _) = pushOutcome { return count }
            return 0
        }()
        let pulled: Int = {
            if case .applied(_, let count) = pullOutcome { return count }
            return 0
        }()
        return (pushed == 0 && pulled == 0) ? .upToDate : .applied(pushed: pushed, pulled: pulled)
    }
}
