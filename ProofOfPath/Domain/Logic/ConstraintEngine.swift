//
//  ConstraintEngine.swift
//  ProofOfPath
//
//  Hard constraints are pass/fail gates. Violating one disqualifies an option
//  regardless of its score.
//

import Foundation

enum ConstraintOutcome: String, Hashable {
    case meets
    case violates
    case unknown

    var title: String {
        switch self {
        case .meets: return "Meets"
        case .violates: return "Violates"
        case .unknown: return "Not Checked"
        }
    }
}

struct ConstraintResult: Identifiable, Hashable {
    var id: UUID { constraint.id }
    let constraint: HardConstraint
    let outcome: ConstraintOutcome
    /// Plain-language explanation of how the outcome was reached.
    let explanation: String
}

enum ConstraintEngine {

    static func describe(_ constraint: HardConstraint, in decision: Decision) -> String {
        switch constraint.check {
        case .maximumCost(let value):
            return "Cost must not exceed \(POPFormat.money(value, currencyCode: decision.currencyCode))"
        case .minimumCost(let value):
            return "Cost must be at least \(POPFormat.money(value, currencyCode: decision.currencyCode))"
        case .criterionAtLeast(let criterionID, let value):
            let name = decision.criterion(id: criterionID)?.displayName ?? "a removed criterion"
            return "\(name) must be at least \(POPFormat.decimal(value))"
        case .criterionAtMost(let criterionID, let value):
            let name = decision.criterion(id: criterionID)?.displayName ?? "a removed criterion"
            return "\(name) must be at most \(POPFormat.decimal(value))"
        case .criterionMustBeYes(let criterionID):
            let name = decision.criterion(id: criterionID)?.displayName ?? "a removed criterion"
            return "\(name) must be answered Yes"
        case .manual:
            return "Marked manually on each option"
        }
    }

    /// True when the constraint points at a criterion that no longer exists.
    static func isOrphaned(_ constraint: HardConstraint, in decision: Decision) -> Bool {
        guard let criterionID = constraint.check.linkedCriterionID else { return false }
        return decision.criterion(id: criterionID) == nil
    }

    static func evaluate(_ constraint: HardConstraint, option: DecisionOption, decision: Decision) -> ConstraintResult {
        let currency = decision.currencyCode

        switch constraint.check {
        case .maximumCost(let limit):
            guard let cost = option.estimatedCost else {
                return ConstraintResult(constraint: constraint, outcome: .unknown,
                                        explanation: "No estimated cost recorded for this option.")
            }
            let ok = cost <= limit + 0.0001
            return ConstraintResult(
                constraint: constraint,
                outcome: ok ? .meets : .violates,
                explanation: "\(POPFormat.money(cost, currencyCode: currency)) \(ok ? "is within" : "exceeds") the limit of \(POPFormat.money(limit, currencyCode: currency))."
            )

        case .minimumCost(let floor):
            guard let cost = option.estimatedCost else {
                return ConstraintResult(constraint: constraint, outcome: .unknown,
                                        explanation: "No estimated cost recorded for this option.")
            }
            let ok = cost >= floor - 0.0001
            return ConstraintResult(
                constraint: constraint,
                outcome: ok ? .meets : .violates,
                explanation: "\(POPFormat.money(cost, currencyCode: currency)) \(ok ? "meets" : "is below") the minimum of \(POPFormat.money(floor, currencyCode: currency))."
            )

        case .criterionAtLeast(let criterionID, let threshold):
            return compareCriterion(constraint: constraint, option: option, decision: decision,
                                    criterionID: criterionID, threshold: threshold, mustBeAtLeast: true)

        case .criterionAtMost(let criterionID, let threshold):
            return compareCriterion(constraint: constraint, option: option, decision: decision,
                                    criterionID: criterionID, threshold: threshold, mustBeAtLeast: false)

        case .criterionMustBeYes(let criterionID):
            guard let criterion = decision.criterion(id: criterionID) else {
                return ConstraintResult(constraint: constraint, outcome: .unknown,
                                        explanation: "The linked criterion was removed. Edit this constraint.")
            }
            guard let value = option.evaluation(for: criterionID)?.boolValue else {
                return ConstraintResult(constraint: constraint, outcome: .unknown,
                                        explanation: "\(criterion.displayName) has not been answered for this option.")
            }
            return ConstraintResult(
                constraint: constraint,
                outcome: value ? .meets : .violates,
                explanation: "\(criterion.displayName) is answered \(value ? "Yes" : "No")."
            )

        case .manual:
            let status = option.manualStatus(for: constraint.id)
            switch status {
            case .meets:
                return ConstraintResult(constraint: constraint, outcome: .meets, explanation: "You marked this option as meeting the constraint.")
            case .fails:
                return ConstraintResult(constraint: constraint, outcome: .violates, explanation: "You marked this option as failing the constraint.")
            case .unknown:
                return ConstraintResult(constraint: constraint, outcome: .unknown, explanation: "You have not marked this option yet.")
            }
        }
    }

    private static func compareCriterion(
        constraint: HardConstraint,
        option: DecisionOption,
        decision: Decision,
        criterionID: UUID,
        threshold: Double,
        mustBeAtLeast: Bool
    ) -> ConstraintResult {
        guard let criterion = decision.criterion(id: criterionID) else {
            return ConstraintResult(constraint: constraint, outcome: .unknown,
                                    explanation: "The linked criterion was removed. Edit this constraint.")
        }
        guard let evaluation = option.evaluation(for: criterionID) else {
            return ConstraintResult(constraint: constraint, outcome: .unknown,
                                    explanation: "\(criterion.displayName) has not been evaluated for this option.")
        }
        let measured: Double?
        if let numeric = evaluation.numericValue {
            measured = numeric
        } else if let rating = evaluation.rating, !criterion.kind.expectsNumericValue {
            measured = Double(rating)
        } else {
            measured = nil
        }
        guard let measured else {
            return ConstraintResult(constraint: constraint, outcome: .unknown,
                                    explanation: "No numeric value recorded for \(criterion.displayName).")
        }
        let ok = mustBeAtLeast ? measured >= threshold - 0.0001 : measured <= threshold + 0.0001
        let comparison = mustBeAtLeast ? "at least" : "at most"
        return ConstraintResult(
            constraint: constraint,
            outcome: ok ? .meets : .violates,
            explanation: "\(criterion.displayName) is \(POPFormat.decimal(measured)); required \(comparison) \(POPFormat.decimal(threshold))."
        )
    }

    // MARK: - Aggregation

    static func results(for option: DecisionOption, decision: Decision) -> [ConstraintResult] {
        decision.hardConstraints.map { evaluate($0, option: option, decision: decision) }
    }

    static func violations(for option: DecisionOption, decision: Decision) -> [ConstraintResult] {
        results(for: option, decision: decision).filter { $0.outcome == .violates }
    }

    static func isDisqualified(_ option: DecisionOption, decision: Decision) -> Bool {
        !violations(for: option, decision: decision).isEmpty
    }

    /// Options that stopped meeting the hard constraints — used for the
    /// "2 options no longer meet your hard constraints" notice.
    static func disqualifiedOptions(in decision: Decision) -> [DecisionOption] {
        decision.comparableOptions.filter { isDisqualified($0, decision: decision) }
    }
}
