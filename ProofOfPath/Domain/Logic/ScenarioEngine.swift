//
//  ScenarioEngine.swift
//  ProofOfPath
//
//  "What if my priorities were different?" The baseline is never overwritten.
//

import Foundation

struct ScenarioChange: Identifiable, Hashable {
    var id: String { label }
    let label: String
    let detail: String
}

struct ScenarioOutcome {
    let scenarioID: UUID?
    let scenarioName: String
    let scoreboard: DecisionScoreboard
    let excludedOptionIDs: Set<UUID>
    let budgetLimit: Double?

    var leaderID: UUID? { scoreboard.leaderID }
}

struct ScenarioComparison {
    let baseline: ScenarioOutcome
    let scenario: ScenarioOutcome
    let leaderChanged: Bool
    let baselineLeaderName: String?
    let scenarioLeaderName: String?
    let changes: [ScenarioChange]
    /// Plain-language summary shown under "What Changed?".
    let explanation: String
    /// Score deltas keyed by option id.
    let scoreDeltas: [UUID: Double]
}

enum ScenarioEngine {

    // MARK: Baseline

    static func baseline(decision: Decision, evidence: [Evidence], scaleMax: Int) -> ScenarioOutcome {
        ScenarioOutcome(
            scenarioID: nil,
            scenarioName: "Baseline",
            scoreboard: ScoringEngine.scoreboard(decision: decision, evidence: evidence, scaleMax: scaleMax),
            excludedOptionIDs: [],
            budgetLimit: decision.budgetMax
        )
    }

    // MARK: Scenario run

    static func run(scenario: Scenario, decision: Decision, evidence: [Evidence], scaleMax: Int) -> ScenarioOutcome {
        let excluded = Set(scenario.excludedOptionIDs)
        let scoreboard = ScoringEngine.scoreboard(
            decision: decision,
            evidence: evidence,
            scaleMax: scaleMax,
            weightOverrides: scenario.weightOverrides.isEmpty ? nil : scenario.weightOverrides,
            excludedOptionIDs: excluded,
            budgetLimit: scenario.budgetLimit
        )
        return ScenarioOutcome(
            scenarioID: scenario.id,
            scenarioName: scenario.displayName,
            scoreboard: scoreboard,
            excludedOptionIDs: excluded,
            budgetLimit: scenario.budgetLimit
        )
    }

    // MARK: Comparison

    static func compare(
        scenario: Scenario,
        decision: Decision,
        evidence: [Evidence],
        scaleMax: Int
    ) -> ScenarioComparison {

        let base = baseline(decision: decision, evidence: evidence, scaleMax: scaleMax)
        let run = run(scenario: scenario, decision: decision, evidence: evidence, scaleMax: scaleMax)

        var changes: [ScenarioChange] = []

        // Weight changes
        for criterion in decision.sortedCriteria {
            let newWeight = scenario.weight(for: criterion)
            if abs(newWeight - criterion.weight) > 0.01 {
                let direction = newWeight > criterion.weight ? "increased" : "decreased"
                changes.append(ScenarioChange(
                    label: criterion.displayName,
                    detail: "Importance \(direction) from \(POPFormat.percent(criterion.weight)) to \(POPFormat.percent(newWeight))"
                ))
            }
        }

        // Budget
        if let limit = scenario.budgetLimit {
            let baseLimit = decision.budgetMax
            if baseLimit == nil || abs((baseLimit ?? 0) - limit) > 0.01 {
                changes.append(ScenarioChange(
                    label: "Budget limit",
                    detail: baseLimit == nil
                        ? "Set to \(POPFormat.money(limit, currencyCode: decision.currencyCode))"
                        : "Changed from \(POPFormat.money(baseLimit ?? 0, currencyCode: decision.currencyCode)) to \(POPFormat.money(limit, currencyCode: decision.currencyCode))"
                ))
            }
        }

        // Deadline
        if let deadline = scenario.deadline {
            if let original = decision.deadline {
                if Calendar.current.compare(deadline, to: original, toGranularity: .day) != .orderedSame {
                    changes.append(ScenarioChange(
                        label: "Deadline",
                        detail: "Moved from \(POPFormat.date(original)) to \(POPFormat.date(deadline))"
                    ))
                }
            } else {
                changes.append(ScenarioChange(label: "Deadline", detail: "Set to \(POPFormat.date(deadline))"))
            }
        }

        // Exclusions
        if !scenario.excludedOptionIDs.isEmpty {
            let names = scenario.excludedOptionIDs
                .compactMap { decision.option(id: $0)?.displayName }
                .joined(separator: ", ")
            if !names.isEmpty {
                changes.append(ScenarioChange(label: "Excluded options", detail: names))
            }
        }

        if !scenario.additionalConstraint.popIsBlank {
            changes.append(ScenarioChange(label: "Additional constraint", detail: scenario.additionalConstraint.popTrimmed))
        }

        // Score deltas
        var deltas: [UUID: Double] = [:]
        for score in run.scoreboard.scores {
            let baseScore = base.scoreboard.score(for: score.optionID)?.weightedScore ?? 0
            deltas[score.optionID] = score.weightedScore - baseScore
        }

        let baseLeaderName = base.leaderID.flatMap { decision.option(id: $0)?.displayName }
        let runLeaderName = run.leaderID.flatMap { decision.option(id: $0)?.displayName }
        let leaderChanged = base.leaderID != run.leaderID

        let explanation = buildExplanation(
            leaderChanged: leaderChanged,
            baseLeaderName: baseLeaderName,
            runLeaderName: runLeaderName,
            changes: changes,
            scenario: scenario,
            decision: decision,
            run: run
        )

        return ScenarioComparison(
            baseline: base,
            scenario: run,
            leaderChanged: leaderChanged,
            baselineLeaderName: baseLeaderName,
            scenarioLeaderName: runLeaderName,
            changes: changes,
            explanation: explanation,
            scoreDeltas: deltas
        )
    }

    private static func buildExplanation(
        leaderChanged: Bool,
        baseLeaderName: String?,
        runLeaderName: String?,
        changes: [ScenarioChange],
        scenario: Scenario,
        decision: Decision,
        run: ScenarioOutcome
    ) -> String {

        if changes.isEmpty {
            return "This scenario does not change anything yet. Adjust weights, the budget, the deadline or exclude an option to see a different result."
        }

        // Prefer the single largest weight change as the explanation.
        var primaryReason: String?
        var largestDelta = 0.0
        for criterion in decision.sortedCriteria {
            let newWeight = scenario.weight(for: criterion)
            let delta = abs(newWeight - criterion.weight)
            if delta > largestDelta {
                largestDelta = delta
                let direction = newWeight > criterion.weight ? "increased" : "decreased"
                primaryReason = "\(criterion.displayName) importance \(direction) from \(POPFormat.percent(criterion.weight)) to \(POPFormat.percent(newWeight))"
            }
        }
        if primaryReason == nil, !scenario.excludedOptionIDs.isEmpty {
            let names = scenario.excludedOptionIDs.compactMap { decision.option(id: $0)?.displayName }.joined(separator: ", ")
            primaryReason = "\(names) \(scenario.excludedOptionIDs.count == 1 ? "was" : "were") excluded"
        }
        if primaryReason == nil, let limit = scenario.budgetLimit {
            primaryReason = "the budget limit was set to \(POPFormat.money(limit, currencyCode: decision.currencyCode))"
        }

        guard let reason = primaryReason else {
            return changes.map { "\($0.label): \($0.detail)" }.joined(separator: "\n")
        }

        if leaderChanged {
            if let runLeaderName {
                if let baseLeaderName {
                    return "\(runLeaderName) becomes the leader instead of \(baseLeaderName) because \(reason)."
                }
                return "\(runLeaderName) becomes the leader because \(reason)."
            }
            if run.scoreboard.scores.isEmpty {
                return "No option is left to compare in this scenario because \(reason)."
            }
            return "No single leader remains because \(reason)."
        }

        if let runLeaderName {
            return "\(runLeaderName) stays the leader even though \(reason)."
        }
        return "There is still no clear leader even though \(reason)."
    }

    // MARK: Presets

    /// Builds a starting scenario from a preset. All values stay editable.
    static func makeScenario(preset: ScenarioPreset, decision: Decision, evidence: [Evidence], scaleMax: Int) -> Scenario {
        var scenario = Scenario()
        scenario.preset = preset
        scenario.name = preset.title

        switch preset {
        case .lowerBudget:
            if let maxBudget = decision.budgetMax {
                scenario.budgetLimit = (maxBudget * 0.75).rounded()
            } else {
                let costs = decision.comparableOptions.compactMap(\.estimatedCost)
                if let lowest = costs.min(), let highest = costs.max(), highest > lowest {
                    scenario.budgetLimit = (lowest + (highest - lowest) * 0.4).rounded()
                }
            }
            scenario.weightOverrides = shiftWeights(
                toward: { $0.kind == .lowerIsBetter || matchesKeyword($0, ["cost", "price", "budget", "fee"]) },
                by: 20,
                decision: decision
            )

        case .urgentDecision:
            if let deadline = decision.deadline {
                scenario.deadline = Calendar.current.date(byAdding: .day, value: -14, to: deadline)
            } else {
                scenario.deadline = Calendar.current.date(byAdding: .day, value: 14, to: Date())
            }
            scenario.weightOverrides = shiftWeights(
                toward: { matchesKeyword($0, ["availab", "delivery", "speed", "time", "lead"]) },
                by: 20,
                decision: decision
            )

        case .qualityFirst:
            scenario.weightOverrides = shiftWeights(
                toward: { matchesKeyword($0, ["quality", "durab", "build", "reliab", "warrant", "support"]) },
                by: 20,
                decision: decision
            )

        case .lowestRisk:
            let risky = Set(decision.risks
                .filter { $0.category == .critical && $0.state != .reduced }
                .compactMap(\.optionID))
            scenario.excludedOptionIDs = decision.comparableOptions
                .filter { risky.contains($0.id) }
                .map(\.id)
            scenario.additionalConstraint = risky.isEmpty
                ? "No option carries a critical risk yet — nothing was excluded."
                : "Options carrying a critical risk are excluded."

        case .custom:
            break
        }

        return scenario
    }

    private static func matchesKeyword(_ criterion: Criterion, _ keywords: [String]) -> Bool {
        let haystack = (criterion.name + " " + criterion.details).lowercased()
        return keywords.contains { haystack.contains($0) }
    }

    /// Moves `points` of weight into the matching criteria, taking it proportionally
    /// from the rest. Total always stays at the original total.
    private static func shiftWeights(
        toward predicate: (Criterion) -> Bool,
        by points: Double,
        decision: Decision
    ) -> [String: Double] {
        let criteria = decision.sortedCriteria
        guard !criteria.isEmpty else { return [:] }

        let targets = criteria.filter(predicate)
        let others = criteria.filter { !predicate($0) }
        guard !targets.isEmpty, !others.isEmpty else { return [:] }

        let donorTotal = others.reduce(0) { $0 + $1.weight }
        // Never take more than the donors can give.
        let movable = min(points, max(0, donorTotal - Double(others.count) * 1.0))
        guard movable > 0.01 else { return [:] }

        var result: [String: Double] = [:]
        let perTarget = movable / Double(targets.count)
        for criterion in targets {
            result[criterion.id.uuidString] = (criterion.weight + perTarget).rounded(toPlaces: 1)
        }
        for criterion in others {
            let share = donorTotal > 0 ? criterion.weight / donorTotal : 0
            result[criterion.id.uuidString] = max(0, criterion.weight - movable * share).rounded(toPlaces: 1)
        }

        // Correct rounding drift so the scenario total matches the original total.
        let originalTotal = criteria.reduce(0) { $0 + $1.weight }
        let newTotal = criteria.reduce(0.0) { $0 + (result[$1.id.uuidString] ?? $1.weight) }
        let drift = originalTotal - newTotal
        if abs(drift) > 0.001, let firstTarget = targets.first {
            let key = firstTarget.id.uuidString
            result[key] = max(0, (result[key] ?? firstTarget.weight) + drift).rounded(toPlaces: 1)
        }
        return result
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
