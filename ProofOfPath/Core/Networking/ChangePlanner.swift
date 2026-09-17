//
//  ChangePlanner.swift
//  ProofOfPath
//
//  Turns "state before" and "state after" an intent into REST operations.
//

import Foundation

/// What one user action has to send to the server.
struct ChangePlan: Equatable {
    var operations: [APIOperation] = []
    /// Files the new state references that the old one did not, keyed by name.
    /// They are uploaded before the operations run.
    var uploads: [String: EvidenceAttachment] = [:]

    var isEmpty: Bool { operations.isEmpty }
}

/// The reducer stays pure and knows nothing about HTTP. After it produces the
/// next state, the planner diffs it against the last server-confirmed state
/// and emits create-or-replace (`PUT`) and `DELETE` operations for exactly the
/// records that changed. The whole plan is sent as one `POST /batch`, so the
/// server stores all of it or none of it.
///
/// Order matters inside a batch: records are written parents first so every
/// reference already exists, and deletions run last so nothing written earlier
/// in the batch can point at a record that is already gone. The server's
/// cascades then remove whatever hung off a deleted record, exactly as the
/// reducer already did locally.
enum ChangePlanner {

    static func plan(from old: AppData, to new: AppData) throws -> ChangePlan {
        var writer = Writer()

        if old.settings != new.settings {
            try writer.put(.settings, "/settings", new.settings)
        }

        let oldDecisions = Dictionary(new: old.decisions)
        let oldEvidence = Dictionary(new: old.evidence)
        let newDecisionIDs = Set(new.decisions.map(\.id))

        for decision in new.decisions {
            let before = oldDecisions[decision.id]
            let d = decision.id.uuidString
            if before.map(Self.core) != Self.core(decision) {
                try writer.put(.decisions, "/decisions/\(d)", Self.core(decision))
            }
            try writer.diff(.constraints, before?.hardConstraints, decision.hardConstraints,
                            put: { "/decisions/\(d)/constraints/\($0.id.uuidString)" },
                            delete: { "/constraints/\($0.uuidString)" })
            try writer.diff(.criteria, before?.criteria, decision.criteria,
                            put: { "/decisions/\(d)/criteria/\($0.id.uuidString)" },
                            delete: { "/criteria/\($0.uuidString)" })
            try writer.diff(.options, before?.options.map(Self.optionCore), decision.options.map(Self.optionCore),
                            put: { "/decisions/\(d)/options/\($0.id.uuidString)" },
                            delete: { "/options/\($0.uuidString)" })

            let oldOptions = Dictionary(new: before?.options ?? [])
            for option in decision.options {
                let oldEvaluations = Dictionary((oldOptions[option.id]?.evaluations ?? []).map { ($0.criterionID, $0) },
                                                uniquingKeysWith: { _, last in last })
                let newEvaluations = Dictionary(option.evaluations.map { ($0.criterionID, $0) },
                                                uniquingKeysWith: { _, last in last })
                let path = { (criterionID: UUID) in "/options/\(option.id.uuidString)/evaluations/\(criterionID.uuidString)" }
                for evaluation in option.evaluations where oldEvaluations[evaluation.criterionID] != evaluation {
                    try writer.put(.evaluations, path(evaluation.criterionID), evaluation)
                }
                // Evaluations of a deleted option or criterion go with it on the server.
                let criterionIDs = Set(decision.criteria.map(\.id))
                for criterionID in oldEvaluations.keys where newEvaluations[criterionID] == nil && criterionIDs.contains(criterionID) {
                    writer.delete(.evaluations, path(criterionID))
                }
            }

            try writer.diff(.claims, before?.claims, decision.claims,
                            put: { "/decisions/\(d)/claims/\($0.id.uuidString)" },
                            delete: { "/claims/\($0.uuidString)" })
            try writer.diff(.risks, before?.risks, decision.risks,
                            put: { "/decisions/\(d)/risks/\($0.id.uuidString)" },
                            delete: { "/risks/\($0.uuidString)" })
            try writer.diff(.scenarios, before?.scenarios, decision.scenarios,
                            put: { "/decisions/\(d)/scenarios/\($0.id.uuidString)" },
                            delete: { "/scenarios/\($0.uuidString)" })
            try writer.diff(.followUps, before?.followUpTasks, decision.followUpTasks,
                            put: { "/decisions/\(d)/follow-ups/\($0.id.uuidString)" },
                            delete: { "/follow-ups/\($0.uuidString)" })
            try writer.diff(.acceptedUnknowns, before?.acceptedUnknowns, decision.acceptedUnknowns,
                            put: { "/decisions/\(d)/accepted-unknowns/\($0.id.uuidString)" },
                            delete: { "/accepted-unknowns/\($0.uuidString)" })

            if before?.finalDecision != decision.finalDecision {
                if let final = decision.finalDecision {
                    try writer.put(.finalDecision, "/decisions/\(d)/final-decision", final)
                } else {
                    writer.delete(.finalDecision, "/decisions/\(d)/final-decision")
                }
            }
            if before?.outcomeReview != decision.outcomeReview {
                if let review = decision.outcomeReview {
                    try writer.put(.outcomeReview, "/decisions/\(d)/outcome-review", review)
                } else {
                    writer.delete(.outcomeReview, "/decisions/\(d)/outcome-review")
                }
            }

            // Snapshots and the activity log are append-only.
            let oldSnapshotIDs = Set(before?.snapshots.map(\.id) ?? [])
            for snapshot in decision.snapshots where !oldSnapshotIDs.contains(snapshot.id) {
                try writer.post(.snapshots, "/decisions/\(d)/snapshots", snapshot)
            }
            let oldActivity = Set(before?.activity.map(\.id) ?? [])
            let newActivity = Set(decision.activity.map(\.id))
            for event in decision.activity where !oldActivity.contains(event.id) {
                try writer.post(.activity, "/decisions/\(d)/activity", event)
            }
            for event in before?.activity ?? [] where !newActivity.contains(event.id) {
                writer.delete(.activity, "/activity/\(event.id.uuidString)")
            }

            for option in decision.options {
                if let image = option.imageFileName, oldOptions[option.id]?.imageFileName != image {
                    writer.upload(EvidenceAttachment(fileName: image, originalName: "\(option.displayName) image",
                                                     byteSize: 0, isImage: true))
                }
            }
        }

        for decision in old.decisions where !newDecisionIDs.contains(decision.id) {
            writer.delete(.decisions, "/decisions/\(decision.id.uuidString)")
        }

        try writer.diff(.evidence, old.evidence, new.evidence,
                        put: { "/evidence/\($0.id.uuidString)" },
                        delete: { "/evidence/\($0.uuidString)" })
        for item in new.evidence {
            if let attachment = item.attachment, oldEvidence[item.id]?.attachment?.fileName != attachment.fileName {
                writer.upload(attachment)
            }
        }

        // A file already referenced before this action is already on the server.
        for name in Self.referencedFiles(in: old) {
            writer.uploads.removeValue(forKey: name)
        }
        return ChangePlan(operations: writer.ordered(), uploads: writer.uploads)
    }

    /// Every attachment and option image the data points at, snapshots included.
    static func referencedFiles(in data: AppData) -> Set<String> {
        var names = Set(data.evidence.compactMap { $0.attachment?.fileName })
        for decision in data.decisions {
            names.formUnion(decision.options.compactMap(\.imageFileName))
            for snapshot in decision.snapshots {
                names.formUnion(snapshot.evidence.compactMap { $0.attachment?.fileName })
                names.formUnion(snapshot.options.compactMap(\.imageFileName))
            }
        }
        return names
    }

    // MARK: - Resource bodies

    /// The decision's own fields. Its collections are resources of their own.
    static func core(_ decision: Decision) -> Decision {
        var core = decision
        core.hardConstraints = []
        core.criteria = []
        core.options = []
        core.claims = []
        core.risks = []
        core.scenarios = []
        core.activity = []
        core.snapshots = []
        core.acceptedUnknowns = []
        core.followUpTasks = []
        core.finalDecision = nil
        core.outcomeReview = nil
        return core
    }

    static func optionCore(_ option: DecisionOption) -> DecisionOption {
        var core = option
        core.evaluations = []
        return core
    }

    // MARK: - Writer

    /// Write order inside the batch. Deletions run after every write.
    private enum Stage: Int, CaseIterable {
        case settings, decisions, constraints, criteria, options, evaluations, evidence, claims, risks,
             scenarios, followUps, acceptedUnknowns, finalDecision, outcomeReview, snapshots, activity
    }

    private struct Writer {
        private var writes: [Stage: [APIOperation]] = [:]
        private var deletes: [Stage: [APIOperation]] = [:]
        var uploads: [String: EvidenceAttachment] = [:]
        private let encoder = POPJSON.makeEncoder()

        mutating func put<T: Encodable>(_ stage: Stage, _ path: String, _ body: T) throws {
            writes[stage, default: []].append(APIOperation(method: .put, path: path, body: try encoder.encode(body)))
        }

        mutating func post<T: Encodable>(_ stage: Stage, _ path: String, _ body: T) throws {
            writes[stage, default: []].append(APIOperation(method: .post, path: path, body: try encoder.encode(body)))
        }

        mutating func delete(_ stage: Stage, _ path: String) {
            deletes[stage, default: []].append(APIOperation(method: .delete, path: path, body: nil))
        }

        mutating func upload(_ attachment: EvidenceAttachment) {
            uploads[attachment.fileName] = attachment
        }

        /// PUT for every new or changed record, DELETE for every removed one.
        mutating func diff<T: Identifiable & Hashable & Encodable>(
            _ stage: Stage,
            _ old: [T]?,
            _ new: [T],
            put path: (T) -> String,
            delete deletePath: (UUID) -> String
        ) throws where T.ID == UUID {
            let before = Dictionary(new: old ?? [])
            for record in new where before[record.id] != record {
                try put(stage, path(record), record)
            }
            let remaining = Set(new.map(\.id))
            for record in old ?? [] where !remaining.contains(record.id) {
                delete(stage, deletePath(record.id))
            }
        }

        /// Writes parents first; deletions children first, after all writes.
        func ordered() -> [APIOperation] {
            let stages = Stage.allCases
            return stages.flatMap { writes[$0] ?? [] } + stages.reversed().flatMap { deletes[$0] ?? [] }
        }
    }
}

private extension Dictionary where Value: Identifiable, Key == Value.ID {
    /// Last one wins, so a duplicated id cannot crash the planner.
    init(new values: [Value]) {
        self.init(values.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }
}
