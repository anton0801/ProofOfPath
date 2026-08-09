//
//  InsightsView.swift
//  ProofOfPath
//
//  Personal patterns. Shown only after three decisions have both a final
//  choice and a completed outcome review.
//

import SwiftUI

struct InsightsView: View {
    @Environment(AppStore.self) private var store

    @State private var expandedInsightID: String?
    @State private var route: AppRoute?

    var body: some View {
        // Computed once per render — it walks every decision.
        let report = store.insights

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                POPScreenHeader(
                    title: "Insights",
                    subtitle: report.hasEnoughData
                        ? "Built from \(report.qualifyingDecisionCount) reviewed decisions."
                        : nil
                )

                if report.hasEnoughData {
                    disclaimer
                    ForEach(report.items) { item in
                        insightCard(item)
                    }
                } else {
                    emptyState(report)
                }
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 6)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { destination in
            if case .decision(let id) = destination {
                DecisionWorkspaceView(decisionID: id, initialSection: .decision)
            }
        }
    }

    // MARK: Empty

    private func emptyState(_ report: InsightsReport) -> some View {
        VStack(spacing: 18) {
            InsightsEmptyArtwork(completed: report.qualifyingDecisionCount)
                .frame(height: 140)

            VStack(spacing: 8) {
                Text("Complete More Outcome Reviews")
                    .font(POPFont.display(23))
                    .foregroundStyle(POPColor.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your patterns will appear after at least three decisions have both a final choice and an outcome review.")
                    .font(POPFont.body)
                    .foregroundStyle(POPColor.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                HStack {
                    Text("Qualifying decisions")
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                    Spacer()
                    Text("\(report.qualifyingDecisionCount) of \(InsightsReport.minimumDecisions)")
                        .font(POPFont.captionMedium)
                        .foregroundStyle(POPColor.ink)
                }
                POPMeter(
                    value: Double(report.qualifyingDecisionCount) / Double(InsightsReport.minimumDecisions),
                    tint: POPColor.brandOrange
                )
            }
            .popCard()

            if !pendingReviews.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    POPSectionHeader(title: "Waiting for a review", icon: "calendar.badge.clock")
                    ForEach(pendingReviews) { decision in
                        DecisionCompactRow(
                            decision: decision,
                            trailingText: decision.isReviewDue
                                ? "Review due"
                                : "Review \(POPFormat.optionalDate(decision.finalDecision?.outcomeReviewDate))"
                        ) {
                            route = .decision(decision.id)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var pendingReviews: [Decision] {
        store.state.decisions.filter { decision in
            guard let final = decision.finalDecision, final.isDraft == false else { return false }
            return decision.outcomeReview?.isComplete != true
        }
    }

    // MARK: Disclaimer

    private var disclaimer: some View {
        POPBanner(
            kind: .neutral,
            message: "These are observations about your own past decisions.",
            detail: "They describe what you recorded — they are not financial, legal or professional advice."
        )
    }

    // MARK: Insight card

    private func insightCard(_ item: InsightItem) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Button(action: {
                Haptics.tap()
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedInsightID = expandedInsightID == item.id ? nil : item.id
                }
            }) {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: item.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(POPColor.brandOrange)
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.warningSoft))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(POPFont.micro)
                            .foregroundStyle(POPColor.inkTertiary)
                        Text(item.value)
                            .font(POPFont.display(22))
                            .foregroundStyle(POPColor.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: expandedInsightID == item.id ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(POPColor.inkTertiary)
                        .padding(.top, 10)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(POPPressStyle())

            Text(item.explanation)
                .font(POPFont.callout)
                .foregroundStyle(POPColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if expandedInsightID == item.id {
                if !item.detailLines.isEmpty {
                    POPDivider()
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(item.detailLines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(POPColor.brandOrange)
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 6)
                                Text(line)
                                    .font(POPFont.caption)
                                    .foregroundStyle(POPColor.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                let related = item.relatedDecisionIDs.compactMap { store.state.decision(id: $0) }
                if !related.isEmpty {
                    POPDivider()
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Related decisions")
                            .font(POPFont.micro)
                            .foregroundStyle(POPColor.inkTertiary)
                        ForEach(related) { decision in
                            Button(action: {
                                Haptics.tap()
                                route = .decision(decision.id)
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: decision.category.icon)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(POPColor.inkSecondary)
                                    Text(decision.displayTitle)
                                        .font(POPFont.callout)
                                        .foregroundStyle(POPColor.ink)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(POPColor.inkTertiary)
                                }
                                .padding(9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(POPColor.surfaceMuted))
                            }
                            .buttonStyle(POPPressStyle())
                        }
                    }
                }
            }
        }
        .popCard()
    }
}

// MARK: - Empty artwork

struct InsightsEmptyArtwork: View {
    let completed: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(POPColor.surfaceSunk)

            HStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { index in
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(index < completed ? POPColor.success : POPColor.surface)
                            Circle()
                                .strokeBorder(index < completed ? POPColor.success : POPColor.hairline, lineWidth: 1.6)
                            Image(systemName: index < completed ? "checkmark" : "questionmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(index < completed ? POPColor.onDark : POPColor.inkTertiary)
                        }
                        .frame(width: 44, height: 44)

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(index < completed ? POPColor.brandOrange : POPColor.hairline)
                            .frame(width: 34, height: CGFloat(24 + index * 12))
                    }
                }
            }
        }
    }
}
