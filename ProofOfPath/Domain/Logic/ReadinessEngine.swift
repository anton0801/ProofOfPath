//
//  ReadinessEngine.swift
//  ProofOfPath
//
//  The gate in front of "Finalize Decision".
//

import SwiftUI

enum ReadinessSeverity: String, Hashable {
    case passed
    case warning
    case blocked

    var order: Int {
        switch self {
        case .blocked: return 0
        case .warning: return 1
        case .passed: return 2
        }
    }
}

struct ReadinessCheck: Identifiable, Hashable {
    let id: String
    let title: String
    let severity: ReadinessSeverity
    let message: String
    /// Section to jump to when the user taps the check.
    let destination: WorkspaceSection?

    var icon: String {
        switch severity {
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .blocked: return "lock.fill"
        }
    }

    var color: Color {
        switch severity {
        case .passed: return POPColor.success
        case .warning: return POPColor.brandOrange
        case .blocked: return POPColor.danger
        }
    }

    var softColor: Color {
        switch severity {
        case .passed: return POPColor.successSoft
        case .warning: return POPColor.warningSoft
        case .blocked: return POPColor.dangerSoft
        }
    }
}

struct ReadinessReport {
    let checks: [ReadinessCheck]

    var blockers: [ReadinessCheck] { checks.filter { $0.severity == .blocked } }
    var warnings: [ReadinessCheck] { checks.filter { $0.severity == .warning } }
    var passed: [ReadinessCheck] { checks.filter { $0.severity == .passed } }

    var state: ReadinessState {
        if !blockers.isEmpty { return .blocked }
        if !warnings.isEmpty { return .needsAttention }
        return .ready
    }

    var canFinalize: Bool { blockers.isEmpty }

    /// Warnings must be explicitly accepted before finalizing.
    var requiresGapAcknowledgement: Bool { !warnings.isEmpty }

    var sorted: [ReadinessCheck] {
        checks.sorted { lhs, rhs in
            if lhs.severity.order != rhs.severity.order { return lhs.severity.order < rhs.severity.order }
            return lhs.title < rhs.title
        }
    }
}

enum ReadinessEngine {

    static func report(
        for decision: Decision,
        evidence: [Evidence],
        scaleMax: Int,
        selectedOptionID: UUID? = nil
    ) -> ReadinessReport {

        var checks: [ReadinessCheck] = []
        let criteria = decision.sortedCriteria
        let options = decision.comparableOptions
        let scoreboard = ScoringEngine.scoreboard(decision: decision, evidence: evidence, scaleMax: scaleMax)

        // 1. Criteria exist
        if criteria.isEmpty {
            checks.append(ReadinessCheck(
                id: "criteria.exist",
                title: "Evaluation Criteria",
                severity: .blocked,
                message: "Add at least one criterion before finalizing.",
                destination: .criteria
            ))
        } else {
            // 2. Criteria balanced
            if decision.isWeightBalanced {
                checks.append(ReadinessCheck(
                    id: "criteria.balanced",
                    title: "Criteria Balanced",
                    severity: .passed,
                    message: "Weights add up to exactly 100%.",
                    destination: .criteria
                ))
            } else {
                let total = decision.totalWeight
                let message = total > 100
                    ? "Criteria weights exceed 100%. Reduce one or more values. Current total: \(POPFormat.percent(total))."
                    : "Assign the remaining weight before comparing options. \(POPFormat.percent(100 - total)) left."
                checks.append(ReadinessCheck(
                    id: "criteria.balanced",
                    title: "Criteria Balanced",
                    severity: .blocked,
                    message: message,
                    destination: .criteria
                ))
            }
        }

        // 3. At least two options
        if options.isEmpty {
            checks.append(ReadinessCheck(
                id: "options.count",
                title: "At Least Two Options",
                severity: .blocked,
                message: "Add options to compare. A decision needs something to choose between.",
                destination: .options
            ))
        } else if options.count == 1 {
            checks.append(ReadinessCheck(
                id: "options.count",
                title: "At Least Two Options",
                severity: .warning,
                message: "Only one option is in the comparison. A single option cannot really be compared.",
                destination: .options
            ))
        } else {
            checks.append(ReadinessCheck(
                id: "options.count",
                title: "At Least Two Options",
                severity: .passed,
                message: "\(options.count) options are in the comparison.",
                destination: .options
            ))
        }

        // 4. Must-haves checked
        let mustHaves = criteria.filter { $0.importance == .mustHave }
        if mustHaves.isEmpty {
            checks.append(ReadinessCheck(
                id: "musthave.checked",
                title: "Must-Haves Checked",
                severity: .warning,
                message: "No criterion is marked as Must Have. Nothing acts as a hard requirement.",
                destination: .criteria
            ))
        } else {
            let unchecked = scoreboard.scores.flatMap(\.uncheckedMustHaves)
            let failing = scoreboard.scores.filter(\.failsMustHave)
            if !unchecked.isEmpty {
                let missingThreshold = mustHaves.filter { POPFormat.parseNumber($0.minimumAcceptableValue) == nil && $0.kind != .yesNo }
                let message = missingThreshold.isEmpty
                    ? "\(unchecked.count) must-have \(unchecked.count == 1 ? "check has" : "checks have") no data yet."
                    : "\(missingThreshold.count) must-have \(missingThreshold.count == 1 ? "criterion has" : "criteria have") no acceptable value, so \(missingThreshold.count == 1 ? "it cannot" : "they cannot") be checked."
                checks.append(ReadinessCheck(
                    id: "musthave.checked",
                    title: "Must-Haves Checked",
                    severity: .warning,
                    message: message,
                    destination: .criteria
                ))
            } else {
                checks.append(ReadinessCheck(
                    id: "musthave.checked",
                    title: "Must-Haves Checked",
                    severity: .passed,
                    message: failing.isEmpty
                        ? "Every option was checked against all must-have criteria."
                        : "\(failing.count) \(failing.count == 1 ? "option does" : "options do") not meet the must-have requirements.",
                    destination: .options
                ))
            }
        }

        // 5. Serious risks reviewed
        let unresolvedCritical = decision.risks.filter { $0.needsAttentionBeforeFinalizing }
        let seriousRisks = decision.risks.filter { $0.category != .monitor && $0.state == .open }
        let seriousWithoutPlan = seriousRisks.filter { !$0.hasMitigation && $0.acceptWithoutMitigationReason.popIsBlank }

        if !unresolvedCritical.isEmpty {
            checks.append(ReadinessCheck(
                id: "risks.critical",
                title: "Critical Risks Reviewed",
                severity: .warning,
                message: "\(unresolvedCritical.count) high-likelihood, high-impact \(unresolvedCritical.count == 1 ? "risk needs" : "risks need") a mitigation plan or a written acceptance.",
                destination: .risks
            ))
        } else if !seriousWithoutPlan.isEmpty {
            checks.append(ReadinessCheck(
                id: "risks.critical",
                title: "Critical Risks Reviewed",
                severity: .warning,
                message: "\(seriousWithoutPlan.count) of \(seriousRisks.count) open \(seriousRisks.count == 1 ? "risk" : "risks") above Monitor level \(seriousWithoutPlan.count == 1 ? "has" : "have") no mitigation plan yet.",
                destination: .risks
            ))
        } else {
            checks.append(ReadinessCheck(
                id: "risks.critical",
                title: "Critical Risks Reviewed",
                severity: .passed,
                message: seriousRisks.isEmpty
                    ? (decision.risks.isEmpty ? "No risks recorded." : "No open risk is above Monitor level.")
                    : "All \(seriousRisks.count) open \(seriousRisks.count == 1 ? "risk" : "risks") above Monitor level \(seriousRisks.count == 1 ? "has" : "have") a plan or an explicit acceptance.",
                destination: .risks
            ))
        }

        // 6. Open claims
        let openClaims = decision.openClaims
        if openClaims.isEmpty {
            checks.append(ReadinessCheck(
                id: "claims.open",
                title: "Open Claims",
                severity: .passed,
                message: decision.claims.isEmpty ? "No claims recorded." : "Every claim has been resolved.",
                destination: .evidence
            ))
        } else {
            checks.append(ReadinessCheck(
                id: "claims.open",
                title: "Open Claims",
                severity: .warning,
                message: "\(openClaims.count) \(openClaims.count == 1 ? "claim is" : "claims are") still unverified.",
                destination: .evidence
            ))
        }

        // 7. Evidence coverage
        let decisionEvidence = evidence.filter { $0.decisionID == decision.id }
        if criteria.isEmpty || options.isEmpty {
            checks.append(ReadinessCheck(
                id: "evidence.coverage",
                title: "Evidence Coverage",
                severity: .warning,
                message: "Add criteria and options before evidence coverage can be measured.",
                destination: .evidence
            ))
        } else {
            let averageCoverage = scoreboard.scores.isEmpty
                ? 0
                : scoreboard.scores.map(\.evidenceCoverage).reduce(0, +) / Double(scoreboard.scores.count)
            if decisionEvidence.isEmpty {
                checks.append(ReadinessCheck(
                    id: "evidence.coverage",
                    title: "Evidence Coverage",
                    severity: .warning,
                    message: "No evidence has been attached to this decision. Every rating is currently an opinion.",
                    destination: .evidence
                ))
            } else if averageCoverage < 0.5 {
                checks.append(ReadinessCheck(
                    id: "evidence.coverage",
                    title: "Evidence Coverage",
                    severity: .warning,
                    message: "Only \(Int((averageCoverage * 100).rounded()))% of ratings are backed by supporting evidence.",
                    destination: .evidence
                ))
            } else {
                checks.append(ReadinessCheck(
                    id: "evidence.coverage",
                    title: "Evidence Coverage",
                    severity: .passed,
                    message: "\(Int((averageCoverage * 100).rounded()))% of ratings are backed by supporting evidence.",
                    destination: .evidence
                ))
            }
        }

        // 8. Budget fit
        if decision.budgetMin == nil && decision.budgetMax == nil {
            checks.append(ReadinessCheck(
                id: "budget.fit",
                title: "Budget Fit",
                severity: .warning,
                message: "No budget range was set, so budget fit cannot be checked.",
                destination: .brief
            ))
        } else {
            let overBudget = options.filter { CostEngine.budgetFit(for: $0, decision: decision) == .above }
            let unknownCost = options.filter { $0.estimatedCost == nil }
            if !overBudget.isEmpty {
                checks.append(ReadinessCheck(
                    id: "budget.fit",
                    title: "Budget Fit",
                    severity: .warning,
                    message: "\(overBudget.count) \(overBudget.count == 1 ? "option is" : "options are") above the budget range.",
                    destination: .options
                ))
            } else if !unknownCost.isEmpty {
                checks.append(ReadinessCheck(
                    id: "budget.fit",
                    title: "Budget Fit",
                    severity: .warning,
                    message: "\(unknownCost.count) \(unknownCost.count == 1 ? "option has" : "options have") no price, so budget fit is unknown.",
                    destination: .options
                ))
            } else {
                checks.append(ReadinessCheck(
                    id: "budget.fit",
                    title: "Budget Fit",
                    severity: .passed,
                    message: "Every option sits inside the budget range.",
                    destination: .options
                ))
            }
        }

        // 9. Selected option must not violate a hard constraint (blocking).
        if let selectedOptionID, let option = decision.option(id: selectedOptionID) {
            let violations = ConstraintEngine.violations(for: option, decision: decision)
            if !violations.isEmpty {
                checks.append(ReadinessCheck(
                    id: "selection.constraints",
                    title: "Selected Option Constraints",
                    severity: .blocked,
                    message: "\(option.displayName) violates \(violations.count) hard \(violations.count == 1 ? "constraint" : "constraints") and cannot be finalized.",
                    destination: .brief
                ))
            } else {
                checks.append(ReadinessCheck(
                    id: "selection.constraints",
                    title: "Selected Option Constraints",
                    severity: .passed,
                    message: "\(option.displayName) meets every hard constraint.",
                    destination: .brief
                ))
            }
            if option.status == .rejected {
                checks.append(ReadinessCheck(
                    id: "selection.rejected",
                    title: "Selected Option Status",
                    severity: .blocked,
                    message: "\(option.displayName) is marked as Rejected. Restore it or pick another option.",
                    destination: .options
                ))
            }
        }

        return ReadinessReport(checks: checks)
    }
}
