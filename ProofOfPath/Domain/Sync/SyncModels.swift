//
//  SyncModels.swift
//  ProofOfPath
//
//  Everything the app needs to become client-server later, present and inert now.
//
//  The app is local-only today: `LocalBackend` is the single implementation and
//  it never talks to a network. These types exist so that turning sync on is a
//  matter of adding a second backend, not of migrating everybody's data.
//
//  Every field added to an existing persisted model is stored as an Optional
//  with a non-optional accessor. Swift's synthesized decoder does NOT fall back
//  to a property's default value when a key is missing, so a non-optional field
//  would make every file written by an earlier build fail to decode.
//

import Foundation

// MARK: - Sync state of a single record

enum SyncState: String, Codable, Hashable {
    /// Created on this device and never sent anywhere.
    case localOnly
    /// Changed locally, waiting to be pushed.
    case pendingUpload
    /// Matches what the server last confirmed.
    case synced
    /// Server and device both changed it; a human has to choose.
    case conflicted

    var needsUpload: Bool { self == .localOnly || self == .pendingUpload }

    var title: String {
        switch self {
        case .localOnly: return "On this device"
        case .pendingUpload: return "Waiting to sync"
        case .synced: return "Synced"
        case .conflicted: return "Needs review"
        }
    }
}

/// Per-record bookkeeping the server will need.
struct SyncMetadata: Codable, Hashable {
    /// Identifier assigned by the server. Nil until the record is first pushed.
    var remoteID: String?
    /// Server revision this device last saw. Used for optimistic concurrency.
    var revision: Int = 0
    var lastSyncedAt: Date?
    var state: SyncState = .localOnly
    /// Set when the local copy diverged from a newer server copy.
    var conflictDetectedAt: Date?

    static let local = SyncMetadata()

    /// Marks the record as changed locally, without losing its server identity.
    mutating func markDirty() {
        if state == .synced || state == .conflicted { state = .pendingUpload }
    }
}

// MARK: - Deletions

enum SyncEntityKind: String, Codable, Hashable {
    case decision
    case evidence
}

/// A deletion that still has to be reported to the server.
///
/// Without tombstones a deletion is invisible to sync: the record simply stops
/// being in the payload, and the server would treat that as "no change" and push
/// it straight back. These have to exist from the first release, because a
/// deletion that happened before tombstones existed can never be recovered.
struct Tombstone: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var entityID: UUID
    var kind: SyncEntityKind
    var remoteID: String?
    var deletedAt: Date = Date()
    /// Cleared once the server confirms it.
    var acknowledged: Bool = false
}

// MARK: - Outbox

enum MutationOperation: String, Codable, Hashable {
    case upsert
    case delete
}

/// One queued change, at aggregate granularity.
///
/// Recording whole `AppIntent`s was the other option, but replaying intents
/// against a server that has moved on is far harder to reason about than
/// sending the current shape of an aggregate. The intent log stays the local
/// audit trail; the outbox is what the transport consumes.
struct PendingMutation: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var entityID: UUID
    var kind: SyncEntityKind
    var operation: MutationOperation
    var queuedAt: Date = Date()
    /// Bumped when a push fails, so a poisoned record can be parked.
    var attemptCount: Int = 0
    var lastError: String?
}

// MARK: - Account

enum AccountMode: String, Codable, Hashable {
    /// No server involved. Everything lives on this device.
    case local
    /// Signed in to a ProofPath account.
    case signedIn

    var title: String {
        switch self {
        case .local: return "On this device"
        case .signedIn: return "Synced to your account"
        }
    }
}

/// Identity and sync status. Anonymous and local until a server exists.
struct AccountState: Codable, Hashable {
    var mode: AccountMode = .local
    /// Server-side user identifier once signed in.
    var userID: String?
    /// Stable per-install identifier. Generated locally, useful immediately for
    /// distinguishing devices in a future multi-device merge.
    var deviceID: String = UUID().uuidString
    var lastSuccessfulSyncAt: Date?
    var lastSyncError: String?

    var isSyncing: Bool { mode == .signedIn }
}

// MARK: - Transport result

/// What a backend reports back after a sync attempt.
enum SyncOutcome: Equatable {
    /// No server is configured — the normal result while the app is local-only.
    case notConfigured
    case upToDate
    case applied(pushed: Int, pulled: Int)
    case failed(String)

    var isSuccess: Bool {
        switch self {
        case .upToDate, .applied: return true
        case .notConfigured, .failed: return false
        }
    }
}

enum SyncError: LocalizedError {
    case notConfigured
    case notSignedIn
    case transport(String)
    case conflict(entityID: UUID)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "No server is configured for this build."
        case .notSignedIn: return "Sign in before syncing."
        case .transport(let detail): return "The server could not be reached. \(detail)"
        case .conflict: return "This record changed on another device."
        }
    }
}
