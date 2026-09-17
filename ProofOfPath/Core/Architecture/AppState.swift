//
//  AppState.swift
//  ProofOfPath
//
//  MVI — the single, immutable Model. Views render it; Intents replace it.
//

import Foundation

/// The user's records as one document: what the server's bootstrap returns,
/// what the offline cache holds and what a backup file contains.
struct AppData: Codable, Hashable {
    var decisions: [Decision] = []
    var evidence: [Evidence] = []
    var settings: AppSettings = AppSettings()
    var schemaVersion: Int = AppData.currentSchemaVersion

    /// 3: constraint checks use the API's flat `{"type": …}` shape. Versions 1
    /// and 2 still import; their checks are converted when decoded.
    static let currentSchemaVersion = 3
}

/// Transient, non-persisted UI feedback.
struct Toast: Identifiable, Equatable {
    enum Style: Equatable {
        case success
        case info
        case warning
        case error
    }

    let id = UUID()
    let message: String
    var style: Style = .info
    var detail: String?
}

struct AppState: Equatable {

    // Confirmed by the server (and mirrored in the offline cache)
    var decisions: [Decision] = []
    var evidence: [Evidence] = []
    var settings: AppSettings = AppSettings()

    // Runtime only
    var isLoaded: Bool = false
    var toast: Toast?
    var lastError: String?
    /// Bumped every time an option list changes so views can re-check constraints.
    var constraintRecheckNotice: String?

    // MARK: - Selectors

    func decision(id: UUID?) -> Decision? {
        guard let id else { return nil }
        return decisions.first { $0.id == id }
    }

    func evidenceItem(id: UUID?) -> Evidence? {
        guard let id else { return nil }
        return evidence.first { $0.id == id }
    }

    func evidence(forDecision decisionID: UUID) -> [Evidence] {
        evidence
            .filter { $0.decisionID == decisionID }
            .sorted { $0.dateCollected > $1.dateCollected }
    }

    var activeDecisions: [Decision] {
        decisions
            .filter { $0.status == .active || $0.status == .draft || $0.status == .paused }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var archivedDecisions: [Decision] {
        decisions
            .filter { $0.status == .archived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var finalizedDecisions: [Decision] {
        decisions
            .filter { $0.status == .finalized }
            .sorted { ($0.finalDecision?.finalizedAt ?? $0.updatedAt) > ($1.finalDecision?.finalizedAt ?? $1.updatedAt) }
    }

    /// Everything except archived, most recently touched first.
    var visibleDecisions: [Decision] {
        decisions
            .filter { $0.status != .archived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var scaleMax: Int { max(2, settings.ratingScaleMax) }

    /// One pass over every decision, producing all five Home buckets.
    /// Computing them together avoids re-deriving progress once per bucket.
    func allBuckets() -> [HomeBucket: [Decision]] {
        var result: [HomeBucket: [Decision]] = [:]
        for decision in decisions {
            for bucket in ProgressEngine.bucket(for: decision, evidence: evidence, scaleMax: scaleMax) {
                result[bucket, default: []].append(decision)
            }
        }
        for (bucket, list) in result {
            result[bucket] = sortBucket(list, bucket: bucket)
        }
        return result
    }

    func buckets(_ bucket: HomeBucket) -> [Decision] {
        sortBucket(
            decisions.filter { ProgressEngine.bucket(for: $0, evidence: evidence, scaleMax: scaleMax).contains(bucket) },
            bucket: bucket
        )
    }

    private func sortBucket(_ list: [Decision], bucket: HomeBucket) -> [Decision] {
        list
            .sorted { lhs, rhs in
                switch bucket {
                case .recentlyCompleted:
                    return (lhs.finalDecision?.finalizedAt ?? lhs.updatedAt) > (rhs.finalDecision?.finalizedAt ?? rhs.updatedAt)
                case .reviewDue:
                    return (lhs.finalDecision?.outcomeReviewDate ?? .distantFuture) < (rhs.finalDecision?.outcomeReviewDate ?? .distantFuture)
                default:
                    // Nearest deadline first, then most recently updated.
                    let lhsDeadline = lhs.deadline ?? .distantFuture
                    let rhsDeadline = rhs.deadline ?? .distantFuture
                    if lhsDeadline != rhsDeadline { return lhsDeadline < rhsDeadline }
                    return lhs.updatedAt > rhs.updatedAt
                }
            }
    }

    var hasAnyDecision: Bool { !decisions.isEmpty }

    var data: AppData {
        get {
            var payload = AppData()
            payload.decisions = decisions
            payload.evidence = evidence
            payload.settings = settings
            return payload
        }
        set {
            decisions = newValue.decisions
            evidence = newValue.evidence
            settings = newValue.settings
        }
    }
}
