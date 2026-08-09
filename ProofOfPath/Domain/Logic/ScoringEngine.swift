//
//  ScoringEngine.swift
//  ProofOfPath
//
//  Every number the app shows must be explainable from what the user entered.
//  Nothing here invents data.
//

import Foundation

// MARK: - Must-have outcome

enum MustHaveOutcome: String, Hashable {
    case met
    case failed
    case unknown
    case noThreshold

    var title: String {
        switch self {
        case .met: return "Meets"
        case .failed: return "Does Not Meet"
        case .unknown: return "Not Checked"
        case .noThreshold: return "No Threshold Set"
        }
    }
}

struct MustHaveResult: Identifiable, Hashable {
    var id: UUID { criterion.id }
    let criterion: Criterion
    let outcome: MustHaveOutcome
    let explanation: String
}

// MARK: - Per-cell result

struct CellScore: Hashable {
    let criterionID: UUID
    /// 0...1 after normalisation, nil when not evaluated.
    let normalized: Double?
    let status: EvaluationStatus
    let confidence: ConfidenceLevel?
    let supportingEvidence: Int
    let contradictingEvidence: Int
    let rawDisplay: String
    let rating: Int?
}

// MARK: - Per-option result

struct OptionScore: Identifiable, Hashable {
    var id: UUID { optionID }
    let optionID: UUID
    /// 0...100, renormalised over the criteria that were actually evaluated.
    let weightedScore: Double
    /// Sum of the weights of evaluated criteria (percent).
    let evaluatedWeight: Double
    /// Sum of all criteria weights (percent).
    let totalWeight: Double
    let unevaluatedCriteriaIDs: [UUID]
    let mustHaveResults: [MustHaveResult]
    let constraintResults: [ConstraintResult]
    let cells: [UUID: CellScore]
    /// Fraction 0...1 of criteria backed by at least one supporting evidence item.
    let evidenceCoverage: Double
    /// Average confidence over evaluated criteria, 0...1.
    let confidenceIndex: Double
    let conflictCount: Int

    var isDisqualified: Bool {
        constraintResults.contains { $0.outcome == .violates }
    }

    var failsMustHave: Bool {
        mustHaveResults.contains { $0.outcome == .failed }
    }

    /// Cannot be a leader regardless of score.
    var isEligibleLeader: Bool { !isDisqualified && !failsMustHave }

    var isComplete: Bool { unevaluatedCriteriaIDs.isEmpty }

    var incompleteMessage: String? {
        guard !unevaluatedCriteriaIDs.isEmpty else { return nil }
        let count = unevaluatedCriteriaIDs.count
        return "Score is incomplete because \(count) \(count == 1 ? "criterion has" : "criteria have") not been evaluated."
    }

    var uncheckedMustHaves: [MustHaveResult] {
        mustHaveResults.filter { $0.outcome == .unknown || $0.outcome == .noThreshold }
    }
}

// MARK: - Whole-decision result

struct DecisionScoreboard {
    let scores: [OptionScore]
    let leaderID: UUID?
    let totalWeight: Double
    let isWeightBalanced: Bool

    func score(for optionID: UUID) -> OptionScore? {
        scores.first { $0.optionID == optionID }
    }

    var ranked: [OptionScore] {
        scores.sorted { lhs, rhs in
            if lhs.isEligibleLeader != rhs.isEligibleLeader { return lhs.isEligibleLeader }
            if abs(lhs.weightedScore - rhs.weightedScore) > 0.001 { return lhs.weightedScore > rhs.weightedScore }
            return lhs.optionID.uuidString < rhs.optionID.uuidString
        }
    }
}

// MARK: - Engine

enum ScoringEngine {

    // MARK: Normalisation

    /// Converts one evaluation into a 0...1 value using the criterion's own rules.
    /// Returns nil when the user has not recorded a judgement.
    static func normalized(evaluation: Evaluation?, criterion: Criterion, scaleMax: Int) -> Double? {
        guard let evaluation else { return nil }
        switch criterion.kind {
        case .yesNo:
            guard let value = evaluation.boolValue else { return nil }
            return value ? 1.0 : 0.0
        case .ratingScale, .descriptive, .higherIsBetter, .lowerIsBetter:
            guard let rating = evaluation.rating else { return nil }
            let upper = max(2, scaleMax)
            let clamped = min(max(rating, 1), upper)
            return Double(clamped - 1) / Double(upper - 1)
        }
    }

    // MARK: Evaluation status (derived, never stored)

    static func status(
        evaluation: Evaluation?,
        option: DecisionOption,
        criterion: Criterion,
        evidence: [Evidence]
    ) -> EvaluationStatus {
        guard let evaluation, !evaluation.isEmpty else { return .notEvaluated }

        let counts = evidenceCounts(option: option, criterion: criterion, evidence: evidence)
        // Outdated and contradicted items are not treated as live evidence on
        // either side — they are on the record, but they no longer carry weight.
        if counts.contradicting > 0 { return .conflictingEvidence }
        if counts.supporting > 0 { return .evidenceSupported }
        // Spec: a rating without an explanation or evidence is never "supported".
        return .preliminary
    }

    /// Live supporting / contradicting counts for one option-criterion cell.
    static func evidenceCounts(
        option: DecisionOption,
        criterion: Criterion,
        evidence: [Evidence]
    ) -> (supporting: Int, contradicting: Int) {
        var supporting = 0
        var contradicting = 0
        for item in evidence where !item.verification.isWeak {
            for link in item.links where link.optionID == option.id && link.criterionID == criterion.id {
                switch link.relation {
                case .supports: supporting += 1
                case .contradicts: contradicting += 1
                case .context: break
                }
            }
        }
        return (supporting, contradicting)
    }

    // MARK: Must-have gate

    static func mustHaveResult(criterion: Criterion, option: DecisionOption, scaleMax: Int) -> MustHaveResult {
        let evaluation = option.evaluation(for: criterion.id)
        let threshold = POPFormat.parseNumber(criterion.minimumAcceptableValue)

        switch criterion.kind {
        case .yesNo:
            guard let value = evaluation?.boolValue else {
                return MustHaveResult(criterion: criterion, outcome: .unknown,
                                      explanation: "Not answered yet.")
            }
            return MustHaveResult(criterion: criterion, outcome: value ? .met : .failed,
                                  explanation: value ? "Answered Yes." : "Answered No, and this criterion is a Must Have.")

        case .higherIsBetter, .lowerIsBetter:
            guard let threshold else {
                return MustHaveResult(criterion: criterion, outcome: .noThreshold,
                                      explanation: "Set an acceptable value so this Must Have can be checked.")
            }
            guard let measured = evaluation?.numericValue else {
                return MustHaveResult(criterion: criterion, outcome: .unknown,
                                      explanation: "No measured value recorded.")
            }
            let ok = criterion.kind == .higherIsBetter ? measured >= threshold - 0.0001 : measured <= threshold + 0.0001
            let requirement = criterion.kind == .higherIsBetter ? "at least" : "no more than"
            return MustHaveResult(
                criterion: criterion,
                outcome: ok ? .met : .failed,
                explanation: "Measured \(POPFormat.decimal(measured)); requires \(requirement) \(POPFormat.decimal(threshold))."
            )

        case .ratingScale, .descriptive:
            guard let threshold else {
                return MustHaveResult(criterion: criterion, outcome: .noThreshold,
                                      explanation: "Set a minimum acceptable rating so this Must Have can be checked.")
            }
            guard let rating = evaluation?.rating else {
                return MustHaveResult(criterion: criterion, outcome: .unknown,
                                      explanation: "Not rated yet.")
            }
            let ok = Double(rating) >= threshold - 0.0001
            return MustHaveResult(
                criterion: criterion,
                outcome: ok ? .met : .failed,
                explanation: "Rated \(rating) of \(scaleMax); requires at least \(POPFormat.decimal(threshold))."
            )
        }
    }

    // MARK: Raw value display

    static func rawDisplay(evaluation: Evaluation?, criterion: Criterion) -> String {
        guard let evaluation else { return "—" }
        switch criterion.kind {
        case .yesNo:
            guard let value = evaluation.boolValue else { return "—" }
            return value ? "Yes" : "No"
        case .higherIsBetter, .lowerIsBetter:
            if !evaluation.measuredValue.popIsBlank { return evaluation.measuredValue.popTrimmed }
            if let numeric = evaluation.numericValue { return POPFormat.decimal(numeric) }
            return "—"
        case .ratingScale, .descriptive:
            if !evaluation.measuredValue.popIsBlank { return evaluation.measuredValue.popTrimmed }
            if let rating = evaluation.rating { return "\(rating)" }
            return "—"
        }
    }

    // MARK: Main scoring

    static func scoreboard(
        decision: Decision,
        evidence: [Evidence],
        scaleMax: Int,
        weightOverrides: [String: Double]? = nil,
        excludedOptionIDs: Set<UUID> = [],
        budgetLimit: Double? = nil
    ) -> DecisionScoreboard {

        let criteria = decision.sortedCriteria
        func weight(for criterion: Criterion) -> Double {
            if let overrides = weightOverrides, let value = overrides[criterion.id.uuidString] { return value }
            return criterion.weight
        }
        let totalWeight = criteria.reduce(0) { $0 + weight(for: $1) }

        var scores: [OptionScore] = []

        for option in decision.comparableOptions where !excludedOptionIDs.contains(option.id) {
            var cells: [UUID: CellScore] = [:]
            var weightedSum = 0.0
            var evaluatedWeight = 0.0
            var unevaluated: [UUID] = []
            var supportedCount = 0
            var confidenceSum = 0.0
            var confidenceCount = 0.0
            var conflicts = 0

            for criterion in criteria {
                let evaluation = option.evaluation(for: criterion.id)
                let normalizedValue = normalized(evaluation: evaluation, criterion: criterion, scaleMax: scaleMax)
                let cellStatus = status(evaluation: evaluation, option: option, criterion: criterion, evidence: evidence)

                let counts = evidenceCounts(option: option, criterion: criterion, evidence: evidence)

                if counts.supporting > 0 { supportedCount += 1 }
                if cellStatus == .conflictingEvidence { conflicts += 1 }

                cells[criterion.id] = CellScore(
                    criterionID: criterion.id,
                    normalized: normalizedValue,
                    status: cellStatus,
                    confidence: (evaluation?.isEmpty == false) ? evaluation?.confidence : nil,
                    supportingEvidence: counts.supporting,
                    contradictingEvidence: counts.contradicting,
                    rawDisplay: rawDisplay(evaluation: evaluation, criterion: criterion),
                    rating: evaluation?.rating
                )

                let criterionWeight = weight(for: criterion)
                if let normalizedValue {
                    weightedSum += normalizedValue * criterionWeight
                    evaluatedWeight += criterionWeight
                    if let confidence = evaluation?.confidence {
                        confidenceSum += confidence.weightFactor
                        confidenceCount += 1
                    }
                } else {
                    unevaluated.append(criterion.id)
                }
            }

            // Renormalise over the criteria that were actually evaluated.
            let finalScore = evaluatedWeight > 0 ? (weightedSum / evaluatedWeight) * 100 : 0

            let mustHaves = criteria
                .filter { $0.importance == .mustHave }
                .map { mustHaveResult(criterion: $0, option: option, scaleMax: scaleMax) }

            var constraintResults = ConstraintEngine.results(for: option, decision: decision)
            if let budgetLimit {
                let scenarioConstraint = HardConstraint(
                    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B0") ?? UUID(),
                    title: "Scenario budget",
                    details: "Applied by the active scenario",
                    check: .maximumCost(budgetLimit)
                )
                constraintResults.append(
                    ConstraintEngine.evaluate(scenarioConstraint, option: option, decision: decision)
                )
            }

            let coverage = criteria.isEmpty ? 0 : Double(supportedCount) / Double(criteria.count)
            let confidenceIndex = confidenceCount > 0 ? confidenceSum / confidenceCount : 0

            scores.append(OptionScore(
                optionID: option.id,
                weightedScore: finalScore,
                evaluatedWeight: evaluatedWeight,
                totalWeight: totalWeight,
                unevaluatedCriteriaIDs: unevaluated,
                mustHaveResults: mustHaves,
                constraintResults: constraintResults,
                cells: cells,
                evidenceCoverage: coverage,
                confidenceIndex: confidenceIndex,
                conflictCount: conflicts
            ))
        }

        // A leader must be eligible and must have at least one evaluated criterion.
        let eligible = scores.filter { $0.isEligibleLeader && $0.evaluatedWeight > 0 }
        let leader = eligible.max { lhs, rhs in
            if abs(lhs.weightedScore - rhs.weightedScore) > 0.0001 { return lhs.weightedScore < rhs.weightedScore }
            return lhs.optionID.uuidString > rhs.optionID.uuidString
        }

        // Ties are not a leader — the app should not pretend to break them.
        var leaderID = leader?.optionID
        if let leader {
            let tied = eligible.filter { abs($0.weightedScore - leader.weightedScore) < 0.0001 }
            if tied.count > 1 { leaderID = nil }
        }

        return DecisionScoreboard(
            scores: scores,
            leaderID: leaderID,
            totalWeight: totalWeight,
            isWeightBalanced: abs(totalWeight - 100) < 0.05
        )
    }

    /// Contribution of one criterion to an option's score, in points of the final 0-100 scale.
    static func contribution(cell: CellScore, weight: Double, evaluatedWeight: Double) -> Double? {
        guard let normalized = cell.normalized, evaluatedWeight > 0 else { return nil }
        return (normalized * weight / evaluatedWeight) * 100
    }
}
