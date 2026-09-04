//
//  DecisionBackend.swift
//  ProofOfPath
//
//  The seam between the app and wherever its data lives.
//

import Foundation

/// Everything the app needs from a data source.
///
/// `LocalBackend` is the only implementation today and never touches a network.
/// A `RemoteBackend` added later implements the same protocol, so `AppStore`
/// does not change: it keeps sending Intents and reading State.
protocol DecisionBackend: AnyObject {

    /// False for the local store; true once a server is behind it.
    var isRemote: Bool { get }

    /// Human-readable description of where data is kept, shown in Settings.
    var storageDescription: String { get }

    // MARK: Local persistence — required by every backend, including remote ones,
    // because the app must keep working offline.

    func load() -> AppData
    func save(_ data: AppData)
    func flush(_ data: AppData)
    func deleteStore()

    func exportData(_ data: AppData) throws -> URL
    func importData(from url: URL) throws -> AppData
    func purgeTemporaryExports()

    // MARK: Sync surface

    /// Sends queued local changes. Returns `.notConfigured` when local-only.
    func push(_ data: AppData) async -> SyncOutcome

    /// Fetches server changes since the given watermark.
    func pull(since watermark: Date?) async -> SyncOutcome
}

// MARK: - Local implementation

/// Wraps the on-device JSON store. The sync methods are honest no-ops: they
/// report that no server is configured rather than pretending to have synced.
final class LocalBackend: DecisionBackend {

    private let repository: DataRepository

    init(repository: DataRepository = .shared) {
        self.repository = repository
    }

    var isRemote: Bool { false }

    var storageDescription: String { "On this device" }

    func load() -> AppData { repository.load() }
    func save(_ data: AppData) { repository.save(data) }
    func flush(_ data: AppData) { repository.flush(data) }
    func deleteStore() { repository.deleteStore() }

    func exportData(_ data: AppData) throws -> URL { try repository.exportData(data) }
    func importData(from url: URL) throws -> AppData { try repository.importData(from: url) }
    func purgeTemporaryExports() { repository.purgeTemporaryExports() }

    func push(_ data: AppData) async -> SyncOutcome { .notConfigured }
    func pull(since watermark: Date?) async -> SyncOutcome { .notConfigured }
}
