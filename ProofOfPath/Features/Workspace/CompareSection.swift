//
//  CompareSection.swift
//  ProofOfPath
//

import SwiftUI

struct CompareSection: View {
    @Environment(AppStore.self) private var store
    let decisionID: UUID

    private var decision: Decision? { store.state.decision(id: decisionID) }

    var body: some View {
        if let decision {
            let scoreboard = store.scoreboard(for: decision)
            let blockers = comparisonBlockers(decision)

            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                WorkspaceSectionIntro(
                    title: "Compare",
                    subtitle: "Criteria down the side, options across the top. Every cell traces back to what you recorded.",
                    icon: "tablecells"
                )

                if !blockers.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(blockers, id: \.self) { blocker in
                            POPBanner(kind: .warning, message: blocker.message, detail: blocker.detail)
                        }
                    }
                }

                leaderCard(decision, scoreboard: scoreboard)
                rankingCard(decision, scoreboard: scoreboard)

                VStack(spacing: 10) {
                    NavigationLink(value: AppRoute.comparisonMatrix(decisionID)) {
                        primaryLinkLabel(title: "Open Comparison Matrix", icon: "tablecells")
                    }
                    NavigationLink(value: AppRoute.scenarioLab(decisionID)) {
                        secondaryLinkLabel(title: "Scenario Lab", icon: "flask")
                    }
                    NavigationLink(value: AppRoute.costView(decisionID)) {
                        secondaryLinkLabel(title: "Total Cost View", icon: "banknote")
                    }
                }
            }
        }
    }

    private struct ComparisonBlocker: Hashable {
        let message: String
        let detail: String?
    }

    private func comparisonBlockers(_ decision: Decision) -> [ComparisonBlocker] {
        var result: [ComparisonBlocker] = []
        if decision.criteria.isEmpty {
            result.append(ComparisonBlocker(message: "No criteria yet.",
                                            detail: "Add criteria before comparing — there is nothing to compare against."))
        } else if !decision.isWeightBalanced {
            result.append(ComparisonBlocker(
                message: decision.totalWeight > 100
                    ? "Criteria weights exceed 100%. Reduce one or more values."
                    : "Assign the remaining weight before comparing options.",
                detail: "Current total: \(POPFormat.percent(decision.totalWeight)). Scores are still shown, but they are not final until this is exactly 100%."))
        }
        if decision.comparableOptions.count < 2 {
            result.append(ComparisonBlocker(
                message: decision.comparableOptions.isEmpty ? "No options to compare." : "Only one option in the comparison.",
                detail: "A comparison needs at least two options that are not rejected."))
        }
        return result
    }

    // MARK: Leader

    private func leaderCard(_ decision: Decision, scoreboard: DecisionScoreboard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            POPSectionHeader(title: "Current Leader", icon: "crown")

            if let leaderID = scoreboard.leaderID, let option = decision.option(id: leaderID),
               let score = scoreboard.score(for: leaderID) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(option.displayName)
                            .font(POPFont.title)
                            .foregroundStyle(POPColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if !option.providerOrBrand.popIsBlank {
                            Text(option.providerOrBrand)
                                .font(POPFont.caption)
                                .foregroundStyle(POPColor.inkSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 1) {
                        Text(POPFormat.score(score.weightedScore))
                            .font(POPFont.numericLarge)
                            .foregroundStyle(POPColor.ink)
                            .monospacedDigit()
                        Text("of 100")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(POPColor.inkTertiary)
                    }
                }

                if let incomplete = score.incompleteMessage {
                    POPInlineNote(text: incomplete, icon: "exclamationmark.circle", tint: POPColor.brandOrange)
                }

                let runnerUp = scoreboard.ranked.first { $0.optionID != leaderID && $0.isEligibleLeader }
                if let runnerUp, let runnerOption = decision.option(id: runnerUp.optionID) {
                    POPInlineNote(
                        text: "Ahead of \(runnerOption.displayName) by \(POPFormat.score(score.weightedScore - runnerUp.weightedScore)) points.",
                        icon: "arrow.up.right"
                    )
                }
            } else {
                POPEmptyState(
                    icon: "questionmark.circle",
                    title: "No clear leader",
                    message: leaderEmptyMessage(decision, scoreboard: scoreboard),
                    compact: true
                )
            }
        }
        .popCard()
    }

    private func leaderEmptyMessage(_ decision: Decision, scoreboard: DecisionScoreboard) -> String {
        if decision.comparableOptions.isEmpty { return "Add options to compare." }
        let eligible = scoreboard.scores.filter { $0.isEligibleLeader && $0.evaluatedWeight > 0 }
        if eligible.isEmpty {
            let disqualified = scoreboard.scores.filter { $0.isDisqualified || $0.failsMustHave }.count
            if disqualified == scoreboard.scores.count && disqualified > 0 {
                return "Every option either breaks a hard constraint or fails a must-have criterion."
            }
            return "No option has been evaluated on any criterion yet."
        }
        return "Two or more options are exactly tied. The app does not break ties for you."
    }

    // MARK: Ranking

    private func rankingCard(_ decision: Decision, scoreboard: DecisionScoreboard) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Ranking", subtitle: "Weighted score across evaluated criteria only.", icon: "list.number")

            if scoreboard.scores.isEmpty {
                POPInlineNote(text: "Nothing to rank yet.")
            } else {
                ForEach(Array(scoreboard.ranked.enumerated()), id: \.element.optionID) { index, score in
                    if let option = decision.option(id: score.optionID) {
                        HStack(spacing: 11) {
                            Text("\(index + 1)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(score.isEligibleLeader ? POPColor.ink : POPColor.inkTertiary)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(index == 0 && score.isEligibleLeader ? POPColor.brandYellow : POPColor.surfaceMuted))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.displayName)
                                    .font(POPFont.calloutMedium)
                                    .foregroundStyle(score.isEligibleLeader ? POPColor.ink : POPColor.inkTertiary)
                                    .lineLimit(1)
                                POPMeter(
                                    value: score.weightedScore / 100,
                                    tint: score.isEligibleLeader ? POPColor.brandYellow : POPColor.hairline,
                                    height: 6
                                )
                                if !score.isEligibleLeader {
                                    Text(score.isDisqualified ? "Disqualified by a hard constraint" : "Does Not Meet Must-Have Requirements")
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(POPColor.danger)
                                }
                            }

                            Text(score.evaluatedWeight > 0 ? POPFormat.score(score.weightedScore) : "—")
                                .font(POPFont.numeric)
                                .foregroundStyle(score.isEligibleLeader ? POPColor.ink : POPColor.inkTertiary)
                                .monospacedDigit()
                                .frame(width: 46, alignment: .trailing)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .popCard()
    }

    // MARK: Link labels

    private func primaryLinkLabel(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
            Text(title).font(POPFont.cardTitle)
        }
        .foregroundStyle(POPColor.graphite)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.brandYellow))
    }

    private func secondaryLinkLabel(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
            Text(title).font(POPFont.cardTitle)
        }
        .foregroundStyle(POPColor.graphite)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.surface))
        .overlay(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
            .strokeBorder(POPColor.graphite.opacity(0.24), lineWidth: 1.4))
    }
}
