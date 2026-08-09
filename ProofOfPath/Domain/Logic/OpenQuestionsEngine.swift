//
//  OpenQuestionsEngine.swift
//  ProofOfPath
//
//  Collects everything that is still missing before the decision can be trusted.
//  Nothing here is invented: each entry points at a concrete record.
//

import Foundation

struct OpenQuestion: Identifiable, Hashable {
    /// Stable across rebuilds so an accepted unknown keeps matching.
    let key: String
    let kind: OpenQuestionKind
    let title: String
    let detail: String
    let optionID: UUID?
    let criterionID: UUID?
    let evidenceID: UUID?
    let claimID: UUID?
    let riskID: UUID?
    let constraintID: UUID?
    /// Where "Resolve Now" should take the user.
    let destination: WorkspaceSection

    var id: String { key }

    var isBlocking: Bool { kind == .hardConstraintViolation }
}

struct OpenQuestionGroup: Identifiable, Hashable {
    var id: String { kind.rawValue }
    let kind: OpenQuestionKind
    let questions: [OpenQuestion]
}

enum OpenQuestionsEngine {

    static func questions(for decision: Decision, evidence: [Evidence], scaleMax: Int) -> [OpenQuestion] {
        var result: [OpenQuestion] = []
        let criteria = decision.sortedCriteria
        let options = decision.comparableOptions

        // 1. Criteria without an evaluation, per option.
        for option in options {
            for criterion in criteria {
                let evaluation = option.evaluation(for: criterion.id)
                let normalized = ScoringEngine.normalized(evaluation: evaluation, criterion: criterion, scaleMax: scaleMax)
                if normalized == nil {
                    result.append(OpenQuestion(
                        key: "eval:\(option.id.uuidString):\(criterion.id.uuidString)",
                        kind: .unevaluatedCriterion,
                        title: "\(option.displayName) — \(criterion.displayName)",
                        detail: "No rating recorded yet for this criterion.",
                        optionID: option.id,
                        criterionID: criterion.id,
                        evidenceID: nil,
                        claimID: nil,
                        riskID: nil,
                        constraintID: nil,
                        destination: .options
                    ))
                }
            }
        }

        // 2. Options with no price.
        for option in options where option.estimatedCost == nil {
            result.append(OpenQuestion(
                key: "cost:\(option.id.uuidString)",
                kind: .optionWithoutCost,
                title: option.displayName,
                detail: "No estimated cost recorded. Cost checks and budget fit cannot be calculated.",
                optionID: option.id,
                criterionID: nil,
                evidenceID: nil,
                claimID: nil,
                riskID: nil,
                constraintID: nil,
                destination: .options
            ))
        }

        // 3. Claims still open.
        for claim in decision.claims where claim.status.isOpen {
            let optionName = decision.option(id: claim.optionID)?.displayName
            result.append(OpenQuestion(
                key: "claim:\(claim.id.uuidString)",
                kind: .unverifiedClaim,
                title: claim.displayText.popTruncated(80),
                detail: [optionName, claim.claimedBy.popIsBlank ? nil : "Claimed by \(claim.claimedBy)", claim.status.title]
                    .compactMap { $0 }
                    .joined(separator: " · "),
                optionID: claim.optionID,
                criterionID: nil,
                evidenceID: nil,
                claimID: claim.id,
                riskID: nil,
                constraintID: nil,
                destination: .evidence
            ))
        }

        // 4. Low-confidence evidence attached to this decision.
        for item in evidence where item.decisionID == decision.id && item.confidence == .low {
            result.append(OpenQuestion(
                key: "evidence:\(item.id.uuidString)",
                kind: .lowConfidenceEvidence,
                title: item.displayTitle.popTruncated(80),
                detail: "Marked as low confidence · \(item.verification.title)",
                optionID: nil,
                criterionID: nil,
                evidenceID: item.id,
                claimID: nil,
                riskID: nil,
                constraintID: nil,
                destination: .evidence
            ))
        }

        // 5. Risks without a mitigation plan.
        for risk in decision.risks where risk.state == .open && !risk.hasMitigation && risk.category != .monitor {
            result.append(OpenQuestion(
                key: "risk:\(risk.id.uuidString)",
                kind: .riskWithoutMitigation,
                title: risk.displayTitle.popTruncated(80),
                detail: "\(risk.category.title) · Likelihood \(risk.likelihood.title), Impact \(risk.impact.title) · No mitigation plan",
                optionID: risk.optionID,
                criterionID: nil,
                evidenceID: nil,
                claimID: nil,
                riskID: risk.id,
                constraintID: nil,
                destination: .risks
            ))
        }

        // 6. Hard-constraint violations.
        for option in options {
            for constraintResult in ConstraintEngine.results(for: option, decision: decision)
            where constraintResult.outcome == .violates {
                result.append(OpenQuestion(
                    key: "constraint:\(option.id.uuidString):\(constraintResult.constraint.id.uuidString)",
                    kind: .hardConstraintViolation,
                    title: "\(option.displayName) — \(constraintResult.constraint.title.popIsBlank ? "Hard constraint" : constraintResult.constraint.title)",
                    detail: constraintResult.explanation,
                    optionID: option.id,
                    criterionID: constraintResult.constraint.check.linkedCriterionID,
                    evidenceID: nil,
                    claimID: nil,
                    riskID: nil,
                    constraintID: constraintResult.constraint.id,
                    destination: .brief
                ))
            }
        }

        return result
    }

    /// Questions the user has not explicitly accepted as unknown.
    static func unresolved(for decision: Decision, evidence: [Evidence], scaleMax: Int) -> [OpenQuestion] {
        let accepted = Set(decision.acceptedUnknowns.map(\.questionKey))
        return questions(for: decision, evidence: evidence, scaleMax: scaleMax)
            .filter { !accepted.contains($0.key) }
    }

    /// Blocking violations first, then the kinds that most often change a decision.
    private static let displayOrder: [OpenQuestionKind] = [
        .hardConstraintViolation,
        .unevaluatedCriterion,
        .unverifiedClaim,
        .riskWithoutMitigation,
        .optionWithoutCost,
        .lowConfidenceEvidence
    ]

    static func grouped(_ questions: [OpenQuestion]) -> [OpenQuestionGroup] {
        displayOrder.compactMap { kind in
            let matching = questions.filter { $0.kind == kind }
            return matching.isEmpty ? nil : OpenQuestionGroup(kind: kind, questions: matching)
        }
    }

    /// Count used on the Home card ("Missing Evidence" / unverified claims).
    static func unverifiedClaimCount(for decision: Decision) -> Int {
        decision.claims.filter { $0.status.isOpen }.count
    }
}
