//
//  DecisionSection.swift
//  ProofOfPath
//
//  The final tab: readiness, finalization, summary and outcome review.
//

import SwiftUI

struct DecisionSection: View {
    @EnvironmentObject private var store: AppStore
    let decisionID: UUID

    private var decision: Decision? { store.state.decision(id: decisionID) }

    var body: some View {
        if let decision {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                WorkspaceSectionIntro(
                    title: "Decision",
                    subtitle: decision.isFinalized
                        ? "Your recorded choice, the reasoning behind it, and the outcome review."
                        : "Check readiness, then record the choice and why you made it.",
                    icon: "checkmark.seal"
                )

                if decision.isFinalized, let final = decision.finalDecision, final.isDraft == false {
                    finalizedCard(decision, final: final)
                    outcomeCard(decision, final: final)
                } else {
                    readinessCard(decision)
                    if final(decision)?.isDraft == true {
                        draftCard(decision)
                    }
                }

                linksCard(decision)
            }
        }
    }

    private func final(_ decision: Decision) -> FinalDecision? { decision.finalDecision }

    // MARK: Readiness preview

    private func readinessCard(_ decision: Decision) -> some View {
        let report = store.readiness(for: decision, selectedOptionID: decision.finalDecision?.selectedOptionID)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: report.state.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(report.state.color)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(report.state.softColor))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Decision Readiness")
                        .font(POPFont.micro)
                        .foregroundStyle(POPColor.inkTertiary)
                    Text(report.state.title)
                        .font(POPFont.title)
                        .foregroundStyle(POPColor.ink)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                POPStatTile(value: "\(report.passed.count)", label: "Passed", icon: "checkmark.circle.fill", tint: POPColor.success)
                POPStatTile(value: "\(report.warnings.count)", label: "Warnings", icon: "exclamationmark.triangle.fill",
                            tint: report.warnings.isEmpty ? POPColor.graphite : POPColor.brandOrange)
                POPStatTile(value: "\(report.blockers.count)", label: "Blockers", icon: "lock.fill",
                            tint: report.blockers.isEmpty ? POPColor.graphite : POPColor.danger)
            }

            if let firstBlocker = report.blockers.first {
                POPBanner(kind: .danger, message: firstBlocker.title, detail: firstBlocker.message)
            }

            NavigationLink(value: AppRoute.readiness(decisionID)) {
                HStack(spacing: 8) {
                    Image(systemName: "checklist").font(.system(size: 15, weight: .semibold))
                    Text("Run Readiness Check").font(POPFont.cardTitle)
                }
                .foregroundStyle(POPColor.graphite)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.brandYellow))
            }

            NavigationLink(value: AppRoute.finalize(decisionID)) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal").font(.system(size: 15, weight: .semibold))
                    Text(report.canFinalize ? "Finalize Decision" : "Open Finalize (blocked)")
                        .font(POPFont.cardTitle)
                }
                .foregroundStyle(report.canFinalize ? POPColor.graphite : POPColor.inkTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.surface))
                .overlay(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                    .strokeBorder(POPColor.graphite.opacity(0.24), lineWidth: 1.4))
            }
        }
        .popCard()
    }

    // MARK: Draft

    private func draftCard(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            POPBanner(
                kind: .info,
                message: "You have a saved draft of the final decision.",
                detail: decision.selectedOption.map { "Currently pointing at \($0.displayName)." }
                    ?? "No option selected in the draft yet."
            )
        }
    }

    // MARK: Finalized

    private func finalizedCard(_ decision: Decision, final: FinalDecision) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(POPColor.success)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(POPColor.successSoft))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Selected Option")
                        .font(POPFont.micro)
                        .foregroundStyle(POPColor.inkTertiary)
                    Text(decision.selectedOption?.displayName ?? "Option no longer available")
                        .font(POPFont.title)
                        .foregroundStyle(decision.selectedOption == nil ? POPColor.danger : POPColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if decision.selectedOption == nil {
                POPBanner(kind: .danger, message: "The chosen option was deleted.",
                          detail: "The snapshot in History still holds the original record.")
            }

            POPDivider()
            POPKeyValueRow(label: "Decision Date", value: POPFormat.date(final.decisionDate), icon: "calendar")
            POPKeyValueRow(label: "Confidence", value: "\(final.confidence) of 5", icon: "gauge.medium")
            POPKeyValueRow(label: "Version", value: "v\(final.version)", icon: "number")
            POPDivider()
            POPKeyValueRow(label: "Why This Option?", value: final.whyThisOption, icon: "text.quote", isMultiline: true)

            NavigationLink(value: AppRoute.summary(decisionID)) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text").font(.system(size: 15, weight: .semibold))
                    Text("Open Decision Summary").font(POPFont.cardTitle)
                }
                .foregroundStyle(POPColor.graphite)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.brandYellow))
            }
        }
        .popCard()
    }

    // MARK: Outcome

    private func outcomeCard(_ decision: Decision, final: FinalDecision) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            POPSectionHeader(
                title: "Outcome Review",
                subtitle: "Compare what you expected with what actually happened.",
                icon: "checkmark.circle.badge.questionmark"
            )

            if decision.outcomeReview?.isComplete == true, let review = decision.outcomeReview {
                HStack(spacing: 10) {
                    if let satisfaction = review.satisfaction {
                        POPStatTile(value: satisfaction.shortTitle, label: "Satisfaction",
                                    icon: satisfaction.icon, tint: satisfaction.color)
                    }
                    if let repeatAnswer = review.wouldChooseAgain {
                        POPStatTile(value: repeatAnswer.title, label: "Choose again?",
                                    icon: repeatAnswer.icon, tint: repeatAnswer.color)
                    }
                }
                POPInlineNote(text: "Completed \(POPFormat.date(review.completedAt ?? Date())). Your original decision was not changed.",
                              icon: "checkmark.circle")
            } else {
                POPKeyValueRow(
                    label: "Review Date",
                    value: "\(POPFormat.date(final.outcomeReviewDate)) · \(POPFormat.relativeDeadline(final.outcomeReviewDate))",
                    valueColor: decision.isReviewDue ? POPColor.brandOrange : POPColor.ink,
                    icon: "calendar.badge.clock"
                )
                if decision.isReviewDue {
                    POPBanner(kind: .warning, message: "The outcome review is due.",
                              detail: "This is where the app earns its keep — compare expectation with reality.")
                }
            }

            NavigationLink(value: AppRoute.outcomeReview(decisionID)) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.badge.questionmark").font(.system(size: 15, weight: .semibold))
                    Text(decision.outcomeReview?.isComplete == true ? "View Outcome Review" : "Complete Outcome Review")
                        .font(POPFont.cardTitle)
                }
                .foregroundStyle(POPColor.graphite)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                    .fill(decision.isReviewDue ? POPColor.brandYellow : POPColor.surface))
                .overlay(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                    .strokeBorder(decision.isReviewDue ? Color.clear : POPColor.graphite.opacity(0.24), lineWidth: 1.4))
            }
        }
        .popCard()
    }

    // MARK: Links

    private func linksCard(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: AppRoute.openQuestions(decisionID)) {
                POPActionRowLabel(
                    title: "Open Questions",
                    subtitle: openQuestionsSubtitle(decision),
                    icon: "questionmark.circle",
                    tint: store.openQuestions(for: decision).isEmpty ? POPColor.success : POPColor.brandOrange
                )
            }
            POPDivider(inset: 41)
            NavigationLink(value: AppRoute.history(decisionID)) {
                POPActionRowLabel(
                    title: "History and Versions",
                    subtitle: "\(decision.activity.count) recorded \(decision.activity.count == 1 ? "event" : "events") · \(decision.snapshots.count) \(decision.snapshots.count == 1 ? "version" : "versions")",
                    icon: "clock.arrow.circlepath",
                    tint: POPColor.graphite
                )
            }
            POPDivider(inset: 41)
            NavigationLink(value: AppRoute.costView(decisionID)) {
                POPActionRowLabel(
                    title: "Total Cost View",
                    subtitle: "Full cost of ownership over \(decision.costHorizon.title)",
                    icon: "banknote",
                    tint: POPColor.graphite
                )
            }
        }
        .popCard(padding: 0)
        .padding(.vertical, 4)
    }

    private func openQuestionsSubtitle(_ decision: Decision) -> String {
        let count = store.openQuestions(for: decision).count
        if count == 0 { return "Nothing missing" }
        return "\(count) \(count == 1 ? "item still missing" : "items still missing")"
    }
}

// MARK: - Row label for NavigationLink

struct POPActionRowLabel: View {
    let title: String
    var subtitle: String?
    let icon: String
    var tint: Color = POPColor.brandOrange

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.13)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(POPFont.bodyMedium)
                    .foregroundStyle(POPColor.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(POPColor.inkTertiary)
        }
        .padding(POPMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
