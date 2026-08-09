//
//  ProgressEngine.swift
//  ProofOfPath
//
//  Drives the Home card: how far along a decision is and what to do next.
//  Every percentage below is the share of concrete steps actually completed.
//

import Foundation

struct ProgressStep: Identifiable, Hashable {
    let id: String
    let title: String
    let isDone: Bool
    let destination: WorkspaceSection
    /// What the user should do if this step is not done.
    let actionLabel: String
}

struct DecisionProgress {
    let steps: [ProgressStep]
    let unverifiedClaimCount: Int
    let missingEvidenceCount: Int
    let optionCount: Int
    let nextStep: ProgressStep?

    var completedCount: Int { steps.filter(\.isDone).count }
    var fraction: Double {
        steps.isEmpty ? 0 : Double(completedCount) / Double(steps.count)
    }
    var percent: Int { Int((fraction * 100).rounded()) }

    var nextActionLabel: String {
        nextStep?.actionLabel ?? "Review the decision summary"
    }

    var nextActionDestination: WorkspaceSection {
        nextStep?.destination ?? .decision
    }
}

enum ProgressEngine {

    static func progress(for decision: Decision, evidence: [Evidence], scaleMax: Int) -> DecisionProgress {
        let criteria = decision.sortedCriteria
        let options = decision.comparableOptions
        let decisionEvidence = evidence.filter { $0.decisionID == decision.id }

        let hasBrief = !decision.title.popIsBlank && !decision.desiredOutcome.popIsBlank
        let hasCriteria = !criteria.isEmpty
        let weightsBalanced = hasCriteria && decision.isWeightBalanced
        let hasTwoOptions = options.count >= 2
        let hasEvidence = !decisionEvidence.isEmpty

        var evaluatedPairs = 0
        var totalPairs = 0
        for option in options {
            for criterion in criteria {
                totalPairs += 1
                let evaluation = option.evaluation(for: criterion.id)
                if ScoringEngine.normalized(evaluation: evaluation, criterion: criterion, scaleMax: scaleMax) != nil {
                    evaluatedPairs += 1
                }
            }
        }
        let allEvaluated = totalPairs > 0 && evaluatedPairs == totalPairs

        let claimsResolved = decision.openClaims.isEmpty
        let risksReviewed = decision.risks.allSatisfy { !$0.needsAttentionBeforeFinalizing }
        let isFinalized = decision.status == .finalized && decision.finalDecision?.isDraft == false
        let outcomeReviewed = decision.outcomeReview?.isComplete == true

        var steps: [ProgressStep] = [
            ProgressStep(id: "brief", title: "Decision brief", isDone: hasBrief,
                         destination: .brief, actionLabel: "Complete the decision brief"),
            ProgressStep(id: "criteria", title: "Criteria defined", isDone: hasCriteria,
                         destination: .criteria, actionLabel: "Add your first criterion"),
            ProgressStep(id: "weights", title: "Weights balanced", isDone: weightsBalanced,
                         destination: .criteria, actionLabel: "Balance criteria weights to 100%"),
            ProgressStep(id: "options", title: "Two or more options", isDone: hasTwoOptions,
                         destination: .options, actionLabel: options.isEmpty ? "Add your first option" : "Add a second option to compare"),
            ProgressStep(id: "evaluations", title: "All options evaluated", isDone: allEvaluated,
                         destination: .options, actionLabel: totalPairs == 0 ? "Add criteria and options first" : "Evaluate \(totalPairs - evaluatedPairs) remaining \(totalPairs - evaluatedPairs == 1 ? "cell" : "cells")"),
            ProgressStep(id: "evidence", title: "Evidence attached", isDone: hasEvidence,
                         destination: .evidence, actionLabel: "Attach your first piece of evidence"),
            ProgressStep(id: "claims", title: "Claims resolved", isDone: claimsResolved,
                         destination: .evidence, actionLabel: "Resolve \(decision.openClaims.count) open \(decision.openClaims.count == 1 ? "claim" : "claims")"),
            ProgressStep(id: "risks", title: "Risks reviewed", isDone: risksReviewed,
                         destination: .risks, actionLabel: "Add a plan for critical risks"),
            ProgressStep(id: "finalized", title: "Decision recorded", isDone: isFinalized,
                         destination: .decision, actionLabel: "Record your final decision")
        ]

        if isFinalized {
            steps.append(ProgressStep(id: "outcome", title: "Outcome reviewed", isDone: outcomeReviewed,
                                      destination: .decision, actionLabel: "Complete the outcome review"))
        }

        // Missing evidence = option/criterion cells with a rating but no supporting evidence.
        var missingEvidence = 0
        for option in options {
            for criterion in criteria {
                let evaluation = option.evaluation(for: criterion.id)
                guard ScoringEngine.normalized(evaluation: evaluation, criterion: criterion, scaleMax: scaleMax) != nil else { continue }
                let hasSupport = decisionEvidence.contains { $0.supports(optionID: option.id, criterionID: criterion.id) }
                if !hasSupport { missingEvidence += 1 }
            }
        }

        let next = steps.first { !$0.isDone }

        return DecisionProgress(
            steps: steps,
            unverifiedClaimCount: decision.openClaims.count,
            missingEvidenceCount: missingEvidence,
            optionCount: decision.options.count,
            nextStep: next
        )
    }

    // MARK: Home buckets

    static func bucket(for decision: Decision, evidence: [Evidence], scaleMax: Int) -> Set<HomeBucket> {
        var buckets: Set<HomeBucket> = []
        guard decision.status != .archived else { return buckets }

        if decision.status == .active || decision.status == .draft || decision.status == .paused {
            buckets.insert(.active)
        }

        let decisionEvidence = evidence.filter { $0.decisionID == decision.id }
        let progress = progress(for: decision, evidence: evidence, scaleMax: scaleMax)

        if decision.status == .active || decision.status == .draft {
            // Only meaningful once there is something to attach evidence to —
            // a brand-new decision needs criteria first, not evidence.
            let hasSomethingToBack = !decision.criteria.isEmpty && !decision.comparableOptions.isEmpty
            if (hasSomethingToBack && (decisionEvidence.isEmpty || progress.missingEvidenceCount > 0))
                || !decision.openClaims.isEmpty {
                buckets.insert(.needsEvidence)
            }
            if decision.isWeightBalanced,
               decision.comparableOptions.count >= 2,
               !decision.criteria.isEmpty {
                buckets.insert(.readyToCompare)
            }
        }

        if decision.isReviewDue { buckets.insert(.reviewDue) }

        if decision.status == .finalized,
           let finalizedAt = decision.finalDecision?.finalizedAt,
           POPFormat.daysUntil(Date(), from: finalizedAt) <= 60 {
            buckets.insert(.recentlyCompleted)
        }

        return buckets
    }

    // MARK: Deadline flags

    enum DeadlineFlag: Hashable {
        case none
        case approaching(Int)
        case overdue(Int)

        var isNotable: Bool {
            if case .none = self { return false }
            return true
        }
    }

    static func deadlineFlag(for decision: Decision, leadDays: Int = 7) -> DeadlineFlag {
        guard decision.status == .active || decision.status == .draft || decision.status == .paused,
              let deadline = decision.deadline else { return .none }
        let days = POPFormat.daysUntil(deadline)
        if days < 0 { return .overdue(-days) }
        if days <= leadDays { return .approaching(days) }
        return .none
    }
}
