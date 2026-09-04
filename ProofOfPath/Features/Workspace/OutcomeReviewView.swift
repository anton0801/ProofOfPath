//
//  OutcomeReviewView.swift
//  ProofOfPath
//
//  Expectation vs reality. The original decision is never changed.
//

import SwiftUI

struct OutcomeReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID

    @State private var expectedOutcome = ""
    @State private var actualOutcome = ""
    @State private var satisfaction: SatisfactionLevel?
    @State private var budgetAccuracy: AccuracyLevel?
    @State private var timelineAccuracy: AccuracyLevel?
    @State private var occurredRiskIDs: Set<UUID> = []
    @State private var unexpectedBenefits = ""
    @State private var unexpectedProblems = ""
    @State private var wouldChooseAgain: RepeatAnswer?
    @State private var whatDifferently = ""
    @State private var showValidation = false
    @State private var loaded = false

    private var decision: Decision? { store.state.decision(id: decisionID) }
    private var isComplete: Bool { decision?.outcomeReview?.isComplete == true }

    private var canComplete: Bool { satisfaction != nil && wouldChooseAgain != nil }

    var body: some View {
        Group {
            // Stays reachable after a reopen so an existing review is never hidden.
            if let decision, let final = decision.finalDecision,
               final.isDraft == false || decision.outcomeReview != nil {
                content(decision: decision, final: final)
            } else if decision != nil {
                POPEmptyState(
                    icon: "checkmark.circle.badge.questionmark",
                    title: "Not finalized yet",
                    message: "The outcome review opens once a final decision has been recorded.",
                    actionTitle: "Back",
                    action: { dismiss() }
                )
                .background(POPColor.canvas.ignoresSafeArea())
            } else {
                POPEmptyState(icon: "questionmark.folder", title: "Decision not found",
                              message: "This decision was deleted.", actionTitle: "Back", action: { dismiss() })
                    .background(POPColor.canvas.ignoresSafeArea())
            }
        }
        .onAppear { hydrate() }
    }

    private func content(decision: Decision, final: FinalDecision) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                CoinStrikeFeatureBanner(asset: "CoinStrikeOutcome")
                header(decision: decision, final: final)

                if isComplete {
                    POPBanner(
                        kind: .success,
                        message: "This review is complete.",
                        detail: "You can still update it. Your original decision record is untouched either way."
                    )
                }

                POPTextEditor(
                    label: "Expected Outcome",
                    text: $expectedOutcome,
                    placeholder: "What did you expect at the time?",
                    hint: "Pre-filled from the desired outcome you wrote at the start — edit if you remember it differently.",
                    characterLimit: 800,
                    minHeight: 100
                )

                POPTextEditor(
                    label: "Actual Outcome",
                    text: $actualOutcome,
                    placeholder: "What actually happened?",
                    characterLimit: 800,
                    minHeight: 100
                )

                satisfactionCard
                accuracyCard(decision)
                risksCard(decision)

                POPTextEditor(
                    label: "Unexpected Benefits",
                    text: $unexpectedBenefits,
                    placeholder: "Anything good you did not see coming?",
                    characterLimit: 600,
                    minHeight: 84
                )

                POPTextEditor(
                    label: "Unexpected Problems",
                    text: $unexpectedProblems,
                    placeholder: "Anything that went wrong that was not on your risk list?",
                    characterLimit: 600,
                    minHeight: 84
                )

                repeatCard

                POPTextEditor(
                    label: "What Would You Do Differently?",
                    text: $whatDifferently,
                    placeholder: "The single most useful thing you can write for your next decision.",
                    characterLimit: 800,
                    minHeight: 100
                )

                comparisonCard(decision, final: final)
                actions

                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 10)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationTitle("Outcome Review")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private func header(decision: Decision, final: FinalDecision) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                Image(systemName: "checkmark.circle.badge.questionmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(POPColor.brandOrange)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(POPColor.warningSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text(decision.selectedOption?.displayName ?? "Option no longer available")
                        .font(POPFont.title)
                        .foregroundStyle(POPColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Decided \(POPFormat.date(final.decisionDate)) · review due \(POPFormat.date(final.outcomeReviewDate))")
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                }
                Spacer(minLength: 0)
            }
            POPInlineNote(text: "This review sits next to the decision. It never rewrites what you decided or why.")
        }
        .popCard()
    }

    // MARK: Satisfaction

    private var satisfactionCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Overall Satisfaction", subtitle: "Required.", icon: "hand.thumbsup")
            VStack(spacing: 7) {
                ForEach(SatisfactionLevel.allCases) { level in
                    Button(action: {
                        Haptics.selection()
                        satisfaction = level
                    }) {
                        HStack(spacing: 9) {
                            Image(systemName: level.icon)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(level.color)
                            Text(level.title)
                                .font(POPFont.calloutMedium)
                                .foregroundStyle(POPColor.ink)
                            Spacer(minLength: 0)
                            if satisfaction == level {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(level.color)
                            }
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(satisfaction == level ? level.color.opacity(0.12) : POPColor.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(satisfaction == level ? level.color.opacity(0.45) : POPColor.hairline,
                                          lineWidth: satisfaction == level ? 1.4 : 1))
                    }
                    .buttonStyle(POPPressStyle())
                }
            }
            if showValidation && satisfaction == nil {
                POPInlineNote(text: "Choose a satisfaction level.", icon: "exclamationmark.circle.fill", tint: POPColor.danger)
            }
        }
        .popCard()
    }

    // MARK: Accuracy

    private func accuracyCard(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            POPSectionHeader(title: "Estimate Accuracy", subtitle: "How close were your original expectations?", icon: "target")

            VStack(alignment: .leading, spacing: 8) {
                Text("Budget Accuracy")
                    .font(POPFont.captionMedium)
                    .foregroundStyle(POPColor.inkSecondary)
                accuracyPicker(selection: $budgetAccuracy)
                if let minValue = decision.budgetMin, let maxValue = decision.budgetMax {
                    POPInlineNote(text: "You planned \(POPFormat.money(minValue, currencyCode: decision.currencyCode)) – \(POPFormat.money(maxValue, currencyCode: decision.currencyCode)).")
                } else if let maxValue = decision.budgetMax {
                    POPInlineNote(text: "You planned up to \(POPFormat.money(maxValue, currencyCode: decision.currencyCode)).")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Timeline Accuracy")
                    .font(POPFont.captionMedium)
                    .foregroundStyle(POPColor.inkSecondary)
                accuracyPicker(selection: $timelineAccuracy)
                if let deadline = decision.deadline {
                    POPInlineNote(text: "Your deadline was \(POPFormat.date(deadline)).")
                }
            }
        }
        .popCard()
    }

    private func accuracyPicker(selection: Binding<AccuracyLevel?>) -> some View {
        VStack(spacing: 6) {
            ForEach(AccuracyLevel.allCases) { level in
                Button(action: {
                    Haptics.selection()
                    selection.wrappedValue = selection.wrappedValue == level ? nil : level
                }) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(level.color)
                            .frame(width: 8, height: 8)
                        Text(level.title)
                            .font(POPFont.callout)
                            .foregroundStyle(POPColor.ink)
                        Spacer(minLength: 0)
                        if selection.wrappedValue == level {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(level.color)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(selection.wrappedValue == level ? level.color.opacity(0.1) : POPColor.surfaceMuted))
                }
                .buttonStyle(POPPressStyle())
            }
        }
    }

    // MARK: Risks

    private func risksCard(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Which Risks Occurred?", subtitle: "Ticking one marks that risk as Occurred.", icon: "exclamationmark.triangle")
            if decision.risks.isEmpty {
                POPInlineNote(text: "No risks were recorded for this decision.")
            } else {
                ForEach(decision.risks) { risk in
                    Button(action: {
                        Haptics.selection()
                        if occurredRiskIDs.contains(risk.id) {
                            occurredRiskIDs.remove(risk.id)
                        } else {
                            occurredRiskIDs.insert(risk.id)
                        }
                    }) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: occurredRiskIDs.contains(risk.id) ? "checkmark.square.fill" : "square")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(occurredRiskIDs.contains(risk.id) ? POPColor.danger : POPColor.hairline)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(risk.displayTitle)
                                    .font(POPFont.calloutMedium)
                                    .foregroundStyle(POPColor.ink)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(risk.category.title) · predicted \(risk.likelihood.title.lowercased()) likelihood")
                                    .font(POPFont.caption)
                                    .foregroundStyle(POPColor.inkSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(occurredRiskIDs.contains(risk.id) ? POPColor.dangerSoft : POPColor.surfaceMuted))
                    }
                    .buttonStyle(POPPressStyle())
                }
            }
        }
        .popCard()
    }

    // MARK: Repeat

    private var repeatCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Would You Choose It Again?", subtitle: "Required.", icon: "arrow.triangle.2.circlepath")
            HStack(spacing: 8) {
                ForEach(RepeatAnswer.allCases) { answer in
                    Button(action: {
                        Haptics.selection()
                        wouldChooseAgain = answer
                    }) {
                        VStack(spacing: 5) {
                            Image(systemName: answer.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(wouldChooseAgain == answer ? answer.color : POPColor.inkTertiary)
                            Text(answer.title)
                                .font(POPFont.captionMedium)
                                .foregroundStyle(wouldChooseAgain == answer ? POPColor.ink : POPColor.inkSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(wouldChooseAgain == answer ? answer.color.opacity(0.12) : POPColor.surface))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(wouldChooseAgain == answer ? answer.color.opacity(0.45) : POPColor.hairline,
                                          lineWidth: wouldChooseAgain == answer ? 1.5 : 1))
                    }
                    .buttonStyle(POPPressStyle())
                }
            }
            if showValidation && wouldChooseAgain == nil {
                POPInlineNote(text: "Answer this question.", icon: "exclamationmark.circle.fill", tint: POPColor.danger)
            }
        }
        .popCard()
    }

    // MARK: Comparison

    private func comparisonCard(_ decision: Decision, final: FinalDecision) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Prediction vs Reality", subtitle: "Built from what you recorded then and now.", icon: "arrow.left.arrow.right")

            comparisonRow(
                label: "Confidence at the time",
                expected: "\(final.confidence) of 5",
                actual: satisfaction.map { "Satisfaction: \($0.title)" } ?? "Not answered yet",
                tint: satisfaction?.color ?? POPColor.inkTertiary
            )
            POPDivider()
            comparisonRow(
                label: "Budget",
                expected: budgetExpectation(decision),
                actual: budgetAccuracy?.title ?? "Not answered yet",
                tint: budgetAccuracy?.color ?? POPColor.inkTertiary
            )
            POPDivider()
            comparisonRow(
                label: "Timeline",
                expected: decision.deadline.map { POPFormat.date($0) } ?? "No deadline set",
                actual: timelineAccuracy?.title ?? "Not answered yet",
                tint: timelineAccuracy?.color ?? POPColor.inkTertiary
            )
            POPDivider()
            comparisonRow(
                label: "Risks",
                expected: "\(decision.risks.count) recorded",
                actual: "\(occurredRiskIDs.count) actually occurred",
                tint: occurredRiskIDs.isEmpty ? POPColor.success : POPColor.danger
            )
        }
        .popCard()
    }

    private func budgetExpectation(_ decision: Decision) -> String {
        switch (decision.budgetMin, decision.budgetMax) {
        case (nil, nil): return "No budget set"
        case (let minValue?, nil): return "From \(POPFormat.money(minValue, currencyCode: decision.currencyCode))"
        case (nil, let maxValue?): return "Up to \(POPFormat.money(maxValue, currencyCode: decision.currencyCode))"
        case (let minValue?, let maxValue?):
            return "\(POPFormat.money(minValue, currencyCode: decision.currencyCode)) – \(POPFormat.money(maxValue, currencyCode: decision.currencyCode))"
        }
    }

    private func comparisonRow(label: String, expected: String, actual: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(POPFont.micro)
                .foregroundStyle(POPColor.inkTertiary)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Expected")
                        .font(.system(size: 10))
                        .foregroundStyle(POPColor.inkTertiary)
                    Text(expected)
                        .font(POPFont.callout)
                        .foregroundStyle(POPColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(POPColor.inkTertiary)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Actual")
                        .font(.system(size: 10))
                        .foregroundStyle(POPColor.inkTertiary)
                    Text(actual)
                        .font(POPFont.callout)
                        .foregroundStyle(tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 10) {
            POPPrimaryButton(
                title: isComplete ? "Update Review" : "Complete Outcome Review",
                icon: "checkmark.circle",
                isEnabled: canComplete
            ) {
                complete()
            }
            POPSecondaryButton(title: "Save Draft Review", icon: "tray.and.arrow.down") {
                saveDraft()
            }
            POPSecondaryButton(title: "Update Later", icon: "clock", tint: POPColor.inkSecondary) {
                dismiss()
            }
            if !canComplete {
                POPInlineNote(text: "Overall Satisfaction and “Would you choose it again?” are both required to complete the review.")
            }
        }
    }

    // MARK: Persistence

    private func hydrate() {
        guard !loaded, let decision else { return }
        loaded = true
        if let review = decision.outcomeReview {
            expectedOutcome = review.expectedOutcome
            actualOutcome = review.actualOutcome
            satisfaction = review.satisfaction
            budgetAccuracy = review.budgetAccuracy
            timelineAccuracy = review.timelineAccuracy
            occurredRiskIDs = Set(review.occurredRiskIDs)
            unexpectedBenefits = review.unexpectedBenefits
            unexpectedProblems = review.unexpectedProblems
            wouldChooseAgain = review.wouldChooseAgain
            whatDifferently = review.whatWouldYouDoDifferently
        } else {
            expectedOutcome = decision.desiredOutcome
            occurredRiskIDs = Set(decision.risks.filter { $0.state == .occurred }.map(\.id))
        }
    }

    private func buildReview() -> OutcomeReview {
        var review = decision?.outcomeReview ?? OutcomeReview()
        review.expectedOutcome = expectedOutcome.popTrimmed
        review.actualOutcome = actualOutcome.popTrimmed
        review.satisfaction = satisfaction
        review.budgetAccuracy = budgetAccuracy
        review.timelineAccuracy = timelineAccuracy
        review.occurredRiskIDs = Array(occurredRiskIDs)
        review.unexpectedBenefits = unexpectedBenefits.popTrimmed
        review.unexpectedProblems = unexpectedProblems.popTrimmed
        review.wouldChooseAgain = wouldChooseAgain
        review.whatWouldYouDoDifferently = whatDifferently.popTrimmed
        return review
    }

    private func saveDraft() {
        store.send(.saveOutcomeReviewDraft(decisionID: decisionID, review: buildReview()))
    }

    private func complete() {
        guard canComplete else {
            showValidation = true
            Haptics.error()
            return
        }
        store.send(.completeOutcomeReview(decisionID: decisionID, review: buildReview()))
        dismiss()
    }
}
