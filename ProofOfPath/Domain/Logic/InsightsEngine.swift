//
//  InsightsEngine.swift
//  ProofOfPath
//
//  Personal patterns, computed only from completed decisions with an outcome
//  review. Never phrased as professional financial or legal advice.
//

import Foundation

struct InsightItem: Identifiable, Hashable {
    let id: String
    let title: String
    /// The headline figure, already formatted. Empty when there is nothing to show.
    let value: String
    /// One sentence explaining exactly where the number came from.
    let explanation: String
    let icon: String
    let relatedDecisionIDs: [UUID]
    let detailLines: [String]
}

struct InsightsReport {
    let qualifyingDecisionCount: Int
    let items: [InsightItem]
    let hasEnoughData: Bool

    static let minimumDecisions = 3
}

private struct CriterionInfluence {
    let name: String
    let average: Double
    let count: Int
}

enum InsightsEngine {

    /// A decision counts once it has a finalized choice and a completed outcome review.
    static func qualifyingDecisions(_ decisions: [Decision]) -> [Decision] {
        decisions.filter { decision in
            guard let final = decision.finalDecision, final.isDraft == false, final.selectedOptionID != nil else { return false }
            return decision.outcomeReview?.isComplete == true
        }
    }

    static func report(decisions: [Decision]) -> InsightsReport {
        let qualifying = qualifyingDecisions(decisions)
        guard qualifying.count >= InsightsReport.minimumDecisions else {
            return InsightsReport(qualifyingDecisionCount: qualifying.count, items: [], hasEnoughData: false)
        }

        var items: [InsightItem] = []

        // 1. Prediction accuracy — how often the choice would be repeated.
        let repeatAnswers = qualifying.compactMap { $0.outcomeReview?.wouldChooseAgain }
        let yesCount = repeatAnswers.filter { $0 == .yes }.count
        let probablyCount = repeatAnswers.filter { $0 == .probably }.count
        if !repeatAnswers.isEmpty {
            let rate = Double(yesCount) / Double(repeatAnswers.count) * 100
            items.append(InsightItem(
                id: "prediction.accuracy",
                title: "Prediction Accuracy",
                value: "\(Int(rate.rounded()))%",
                explanation: "In \(yesCount) of \(repeatAnswers.count) reviewed decisions you answered “Yes” to “Would you choose it again?”\(probablyCount > 0 ? " Another \(probablyCount) answered “Probably.”" : "")",
                icon: "target",
                relatedDecisionIDs: qualifying.map(\.id),
                detailLines: qualifying.compactMap { decision in
                    guard let answer = decision.outcomeReview?.wouldChooseAgain else { return nil }
                    return "\(decision.displayTitle) — \(answer.title)"
                }
            ))
        }

        // 2. Most influential criteria — highest average weight across decisions.
        var weightByName: [String: [Double]] = [:]
        var decisionsByCriterionName: [String: Set<UUID>] = [:]
        for decision in qualifying {
            for criterion in decision.criteria where !criterion.name.popIsBlank {
                let key = criterion.name.popNormalizedForCompare
                weightByName[key, default: []].append(criterion.weight)
                decisionsByCriterionName[key, default: []].insert(decision.id)
            }
        }
        var influentialAll: [CriterionInfluence] = []
        for (name, weights) in weightByName where weights.count >= 2 {
            let total: Double = weights.reduce(0, +)
            let average: Double = total / Double(weights.count)
            influentialAll.append(CriterionInfluence(name: name, average: average, count: weights.count))
        }
        influentialAll.sort { $0.average > $1.average }
        let influential = Array(influentialAll.prefix(5))
        if let top = influential.first {
            items.append(InsightItem(
                id: "criteria.influential",
                title: "Most Influential Criteria",
                value: top.name.capitalizedFirst,
                explanation: "“\(top.name.capitalizedFirst)” appeared in \(top.count) reviewed decisions with an average weight of \(POPFormat.percent(top.average)).",
                icon: "scalemass",
                relatedDecisionIDs: Array(decisionsByCriterionName[top.name] ?? []),
                detailLines: influential.map { "\($0.name.capitalizedFirst) — average weight \(POPFormat.percent($0.average)) across \($0.count) decisions" }
            ))
        }

        // 3. Common missing information — accepted unknowns by kind.
        var unknownsByKind: [OpenQuestionKind: Int] = [:]
        var decisionsByKind: [OpenQuestionKind: Set<UUID>] = [:]
        for decision in qualifying {
            for unknown in decision.acceptedUnknowns {
                unknownsByKind[unknown.kind, default: 0] += 1
                decisionsByKind[unknown.kind, default: []].insert(decision.id)
            }
        }
        if let topKind = unknownsByKind.max(by: { $0.value < $1.value }) {
            items.append(InsightItem(
                id: "missing.information",
                title: "Common Missing Information",
                value: topKind.key.title,
                explanation: "You proceeded with “\(topKind.key.title)” unresolved \(topKind.value) \(topKind.value == 1 ? "time" : "times") across \(decisionsByKind[topKind.key]?.count ?? 0) decisions.",
                icon: "questionmark.folder",
                relatedDecisionIDs: Array(decisionsByKind[topKind.key] ?? []),
                detailLines: unknownsByKind
                    .sorted { $0.value > $1.value }
                    .map { "\($0.key.title) — accepted \($0.value) \($0.value == 1 ? "time" : "times")" }
            ))
        }

        // 4. Frequently accepted risks.
        let acceptedRisks = qualifying.flatMap { decision in
            decision.risks.filter { $0.state == .accepted }.map { (decision.id, $0) }
        }
        if !acceptedRisks.isEmpty {
            let occurred = qualifying.flatMap { decision -> [Risk] in
                guard let review = decision.outcomeReview else { return [] }
                return decision.risks.filter { review.occurredRiskIDs.contains($0.id) }
            }
            items.append(InsightItem(
                id: "risks.accepted",
                title: "Frequently Accepted Risks",
                value: "\(acceptedRisks.count)",
                explanation: "You accepted \(acceptedRisks.count) \(acceptedRisks.count == 1 ? "risk" : "risks") without reducing \(acceptedRisks.count == 1 ? "it" : "them"). \(occurred.count) recorded \(occurred.count == 1 ? "risk" : "risks") actually occurred.",
                icon: "hand.raised",
                relatedDecisionIDs: Array(Set(acceptedRisks.map(\.0))),
                detailLines: acceptedRisks.map { "\($0.1.displayTitle) — \($0.1.category.title)" }
            ))
        }

        // 5. Average decision time.
        let durations: [Double] = qualifying.compactMap { decision in
            guard let finalizedAt = decision.finalDecision?.finalizedAt else { return nil }
            let days = Double(POPFormat.daysUntil(finalizedAt, from: decision.createdAt))
            return days >= 0 ? days : nil
        }
        if !durations.isEmpty {
            let average = durations.reduce(0, +) / Double(durations.count)
            items.append(InsightItem(
                id: "time.average",
                title: "Average Decision Time",
                value: "\(Int(average.rounded())) days",
                explanation: "Measured from the day each decision was created to the day it was finalized, across \(durations.count) decisions.",
                icon: "clock",
                relatedDecisionIDs: qualifying.map(\.id),
                detailLines: qualifying.compactMap { decision in
                    guard let finalizedAt = decision.finalDecision?.finalizedAt else { return nil }
                    let days = POPFormat.daysUntil(finalizedAt, from: decision.createdAt)
                    return "\(decision.displayTitle) — \(max(0, days)) days"
                }
            ))
        }

        // 6. Budget estimate accuracy.
        let budgetAnswers = qualifying.compactMap { $0.outcomeReview?.budgetAccuracy }
        if !budgetAnswers.isEmpty {
            let onTarget = budgetAnswers.filter { $0 == .asExpected }.count
            let higher = budgetAnswers.filter { $0 == .slightlyHigher || $0 == .muchHigher }.count
            let rate = Double(onTarget) / Double(budgetAnswers.count) * 100
            items.append(InsightItem(
                id: "budget.accuracy",
                title: "Budget Estimate Accuracy",
                value: "\(Int(rate.rounded()))%",
                explanation: "\(onTarget) of \(budgetAnswers.count) reviews said the cost matched what you expected.\(higher > 0 ? " \(higher) came out higher than planned." : "")",
                icon: "banknote",
                relatedDecisionIDs: qualifying.map(\.id),
                detailLines: qualifying.compactMap { decision in
                    guard let accuracy = decision.outcomeReview?.budgetAccuracy else { return nil }
                    return "\(decision.displayTitle) — \(accuracy.title)"
                }
            ))
        }

        // 7. Timeline accuracy (shown alongside budget).
        let timelineAnswers = qualifying.compactMap { $0.outcomeReview?.timelineAccuracy }
        if !timelineAnswers.isEmpty {
            let onTarget = timelineAnswers.filter { $0 == .asExpected }.count
            let rate = Double(onTarget) / Double(timelineAnswers.count) * 100
            items.append(InsightItem(
                id: "timeline.accuracy",
                title: "Timeline Estimate Accuracy",
                value: "\(Int(rate.rounded()))%",
                explanation: "\(onTarget) of \(timelineAnswers.count) reviews said the timing matched what you expected.",
                icon: "calendar",
                relatedDecisionIDs: qualifying.map(\.id),
                detailLines: qualifying.compactMap { decision in
                    guard let accuracy = decision.outcomeReview?.timelineAccuracy else { return nil }
                    return "\(decision.displayTitle) — \(accuracy.title)"
                }
            ))
        }

        // 8. Choices you would repeat.
        let repeatable = qualifying.filter { $0.outcomeReview?.wouldChooseAgain == .yes }
        if !repeatable.isEmpty {
            items.append(InsightItem(
                id: "choices.repeat",
                title: "Choices You Would Repeat",
                value: "\(repeatable.count)",
                explanation: "\(repeatable.count) of your \(qualifying.count) reviewed decisions would be made the same way again.",
                icon: "arrow.triangle.2.circlepath",
                relatedDecisionIDs: repeatable.map(\.id),
                detailLines: repeatable.map { decision in
                    let optionName = decision.selectedOption?.displayName ?? "—"
                    return "\(decision.displayTitle) — chose \(optionName)"
                }
            ))
        }

        // 9. Repeated blind spots — the same gap accepted in 2+ decisions.
        let repeatedBlindSpots = decisionsByKind.filter { $0.value.count >= 2 }
        if !repeatedBlindSpots.isEmpty {
            let sorted = repeatedBlindSpots.sorted { $0.value.count > $1.value.count }
            let top = sorted[0]
            items.append(InsightItem(
                id: "blind.spots",
                title: "Repeated Blind Spots",
                value: top.key.title,
                explanation: "You accepted “\(top.key.title)” as an unknown in \(top.value.count) separate decisions.",
                icon: "eye.trianglebadge.exclamationmark",
                relatedDecisionIDs: Array(top.value),
                detailLines: sorted.map { "\($0.key.title) — in \($0.value.count) decisions" }
            ))
        }

        return InsightsReport(
            qualifyingDecisionCount: qualifying.count,
            items: items,
            hasEnoughData: true
        )
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first = self.first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
