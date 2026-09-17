//
//  DecisionSummaryView.swift
//  ProofOfPath
//
//  The final report. Export contains only real user data plus the creation date.
//

import SwiftUI

struct DecisionSummaryView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID

    @State private var showReopen = false
    @State private var reopenReason = ""
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var isExporting = false

    private var decision: Decision? { store.state.decision(id: decisionID) }

    var body: some View {
        Group {
            if let decision, let final = decision.finalDecision, final.isDraft == false {
                content(decision: decision, final: final)
            } else if decision != nil {
                POPEmptyState(
                    icon: "doc.text",
                    title: "Not finalized yet",
                    message: "The summary appears once you record a final decision.",
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
    }

    private func content(decision: Decision, final: FinalDecision) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                headline(decision: decision, final: final)
                goalCard(decision)
                reasonsCard(final)
                evidenceCard(decision, final: final)
                limitationsCard(decision, final: final)
                risksCard(decision, final: final)
                alternativesCard(decision)
                reviewCard(decision, final: final)
                actionsCard(decision)
                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 10)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationTitle("Decision Summary")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { exportURL.map { ExportFile(url: $0) } },
            set: { exportURL = $0?.url }
        )) { file in
            ShareSheet(items: [file.url])
        }
        .alert("Reopen this decision?", isPresented: $showReopen) {
            TextField("Why are you reopening it?", text: $reopenReason)
            Button("Cancel", role: .cancel) { reopenReason = "" }
            Button("Reopen") {
                let reason = reopenReason
                Task {
                    // The reason is kept if the save fails, so it is still there next time.
                    if await store.perform(.reopenDecision(decisionID: decisionID, reason: reason)) {
                        reopenReason = ""
                    }
                }
            }
        } message: {
            Text("The current version stays available in History as a read-only snapshot. New changes are saved as a new version.")
        }
        .alert("Export failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: Sections

    private func headline(decision: Decision, final: FinalDecision) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(POPColor.success)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.successSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selected Option")
                        .font(POPFont.micro)
                        .foregroundStyle(POPColor.inkTertiary)
                    Text(decision.selectedOption?.displayName ?? "Option no longer available")
                        .font(POPFont.display(24))
                        .foregroundStyle(decision.selectedOption == nil ? POPColor.danger : POPColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                POPStatTile(value: "\(final.confidence)/5", label: "Confidence", icon: "gauge.medium")
                POPStatTile(value: POPFormat.dateShort(final.decisionDate), label: "Decided", icon: "calendar")
                POPStatTile(value: "v\(final.version)", label: "Version", icon: "number")
            }
        }
        .popCard()
    }

    private func goalCard(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Decision Goal", icon: "target")
            POPKeyValueRow(label: "Decision", value: decision.displayTitle, isMultiline: true)
            POPDivider()
            POPKeyValueRow(label: "Desired Outcome", value: decision.desiredOutcome, isMultiline: true)
            if !decision.whyItMatters.popIsBlank {
                POPDivider()
                POPKeyValueRow(label: "Why It Matters", value: decision.whyItMatters, isMultiline: true)
            }
        }
        .popCard()
    }

    private func reasonsCard(_ final: FinalDecision) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Key Reasons", icon: "text.quote")
            Text(final.whyThisOption)
                .font(POPFont.body)
                .foregroundStyle(POPColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !final.acceptedTradeOffs.popIsBlank {
                POPDivider()
                POPKeyValueRow(label: "Accepted Trade-Offs", value: final.acceptedTradeOffs, isMultiline: true)
            }
        }
        .popCard()
    }

    private func evidenceCard(_ decision: Decision, final: FinalDecision) -> some View {
        let items = final.keyEvidenceIDs.compactMap { store.state.evidenceItem(id: $0) }
        return VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Strongest Evidence", icon: "paperclip")
            if items.isEmpty {
                POPInlineNote(text: "No key evidence was marked for this decision.")
            } else {
                ForEach(items) { item in
                    NavigationLink(value: AppRoute.evidenceDetail(item.id)) {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: item.type.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(POPColor.brandOrange)
                                .frame(width: 28, height: 28)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(POPColor.warningSoft))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayTitle)
                                    .font(POPFont.calloutMedium)
                                    .foregroundStyle(POPColor.ink)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(item.type.title) · \(item.verification.title)")
                                    .font(POPFont.caption)
                                    .foregroundStyle(POPColor.inkSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(POPColor.inkTertiary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.surfaceMuted))
                    }
                    .buttonStyle(POPPressStyle())
                }
            }
        }
        .popCard()
    }

    private func limitationsCard(_ decision: Decision, final: FinalDecision) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Known Limitations", subtitle: "Gaps you knowingly accepted.", icon: "hand.raised")
            if decision.acceptedUnknowns.isEmpty && final.proceedWithGapsReason.popIsBlank {
                POPInlineNote(text: "No gaps were recorded at the time of the decision.")
            } else {
                if !final.proceedWithGapsReason.popIsBlank {
                    POPKeyValueRow(label: "Proceeded with known gaps because",
                                   value: final.proceedWithGapsReason, isMultiline: true)
                }
                ForEach(decision.acceptedUnknowns) { unknown in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(unknown.label)
                            .font(POPFont.calloutMedium)
                            .foregroundStyle(POPColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(unknown.reason)
                            .font(POPFont.caption)
                            .foregroundStyle(POPColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.neutralSoft))
                }
            }
        }
        .popCard()
    }

    private func risksCard(_ decision: Decision, final: FinalDecision) -> some View {
        let accepted = decision.risks.filter { $0.state == .accepted || $0.category == .critical }
        return VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Accepted Risks", icon: "exclamationmark.triangle")
            if !final.acceptedRisks.popIsBlank {
                Text(final.acceptedRisks)
                    .font(POPFont.body)
                    .foregroundStyle(POPColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if accepted.isEmpty && final.acceptedRisks.popIsBlank {
                POPInlineNote(text: "No risks were recorded as accepted.")
            } else {
                ForEach(accepted) { risk in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: risk.category.icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(risk.category.color)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(risk.displayTitle)
                                .font(POPFont.callout)
                                .foregroundStyle(POPColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(risk.category.title) · \(risk.state.title)")
                                .font(POPFont.caption)
                                .foregroundStyle(POPColor.inkSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .popCard()
    }

    private func alternativesCard(_ decision: Decision) -> some View {
        let scoreboard = store.scoreboard(for: decision)
        let others = scoreboard.ranked.filter { $0.optionID != decision.finalDecision?.selectedOptionID }
        return VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Alternatives Considered", icon: "square.stack.3d.up")
            if others.isEmpty {
                POPInlineNote(text: "No other options were in the comparison.")
            } else {
                ForEach(others) { score in
                    if let option = decision.option(id: score.optionID) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.displayName)
                                    .font(POPFont.calloutMedium)
                                    .foregroundStyle(POPColor.ink)
                                    .lineLimit(1)
                                if !score.isEligibleLeader {
                                    Text(score.isDisqualified ? "Disqualified by a hard constraint" : "Did not meet a must-have")
                                        .font(POPFont.caption)
                                        .foregroundStyle(POPColor.danger)
                                }
                            }
                            Spacer(minLength: 0)
                            Text(score.evaluatedWeight > 0 ? POPFormat.score(score.weightedScore) : "—")
                                .font(POPFont.numeric)
                                .foregroundStyle(POPColor.inkSecondary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .popCard()
    }

    private func reviewCard(_ decision: Decision, final: FinalDecision) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Review Date", icon: "calendar.badge.clock")
            POPKeyValueRow(
                label: "Outcome review",
                value: "\(POPFormat.date(final.outcomeReviewDate)) · \(POPFormat.relativeDeadline(final.outcomeReviewDate))",
                valueColor: decision.isReviewDue ? POPColor.brandOrange : POPColor.ink
            )
            if decision.outcomeReview?.isComplete == true, let review = decision.outcomeReview {
                POPDivider()
                POPKeyValueRow(label: "Satisfaction", value: review.satisfaction?.title ?? "—",
                               valueColor: review.satisfaction?.color ?? POPColor.ink)
                POPKeyValueRow(label: "Would choose again", value: review.wouldChooseAgain?.title ?? "—",
                               valueColor: review.wouldChooseAgain?.color ?? POPColor.ink)
            }
            NavigationLink(value: AppRoute.outcomeReview(decisionID)) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.badge.questionmark").font(.system(size: 14, weight: .semibold))
                    Text(decision.outcomeReview?.isComplete == true ? "View Outcome Review" : "Complete Outcome Review")
                        .font(POPFont.calloutMedium)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(POPColor.graphite)
                .padding(11)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.surfaceSunk))
            }
        }
        .popCard()
    }

    private func actionsCard(_ decision: Decision) -> some View {
        VStack(spacing: 10) {
            POPPrimaryButton(title: "Export as PDF", icon: "square.and.arrow.up", isLoading: isExporting) {
                exportPDF(decision)
            }
            HStack(spacing: 10) {
                POPSecondaryButton(title: "Mark Purchase Completed", icon: "checkmark.circle") {
                    store.send(.markPurchaseCompleted(decisionID: decisionID))
                }
                .popRequiresConnection()
            }
            POPSecondaryButton(title: "Reopen Decision", icon: "arrow.uturn.backward", tint: POPColor.brandOrange) {
                showReopen = true
            }
            .popRequiresConnection()
            POPInlineNote(text: "The export contains only what you entered, plus the date it was created.")
        }
    }

    // MARK: Export

    private func exportPDF(_ decision: Decision) {
        #if canImport(UIKit)
        guard let final = decision.finalDecision else { return }
        isExporting = true
        defer { isExporting = false }

        var blocks: [PDFBlock] = []
        blocks.append(.title(decision.displayTitle))
        blocks.append(.subtitle("Decision summary · \(decision.categoryTitle) · Created \(POPFormat.dateTime(Date()))"))
        blocks.append(.rule)

        blocks.append(.heading("Selected Option"))
        blocks.append(.body(decision.selectedOption?.displayName ?? "Option no longer available"))
        blocks.append(.keyValue("Decision date", POPFormat.date(final.decisionDate)))
        blocks.append(.keyValue("Confidence", "\(final.confidence) of 5"))
        blocks.append(.keyValue("Version", "v\(final.version)"))

        blocks.append(.heading("Decision Goal"))
        blocks.append(.keyValue("Desired outcome", decision.desiredOutcome))
        if !decision.whyItMatters.popIsBlank {
            blocks.append(.keyValue("Why it matters", decision.whyItMatters))
        }
        if !decision.peopleAffected.popIsBlank {
            blocks.append(.keyValue("People affected", decision.peopleAffected))
        }

        blocks.append(.heading("Key Reasons"))
        blocks.append(.body(final.whyThisOption))
        if !final.acceptedTradeOffs.popIsBlank {
            blocks.append(.keyValue("Accepted trade-offs", final.acceptedTradeOffs))
        }

        let criteria = decision.sortedCriteria
        if !criteria.isEmpty {
            blocks.append(.heading("Criteria and Weights"))
            for criterion in criteria {
                blocks.append(.bullet("\(criterion.displayName) — \(POPFormat.percent(criterion.weight)) · \(criterion.importance.title)"))
            }
        }

        let scoreboard = store.scoreboard(for: decision)
        if !scoreboard.ranked.isEmpty {
            blocks.append(.heading("Options Considered"))
            for score in scoreboard.ranked {
                guard let option = decision.option(id: score.optionID) else { continue }
                var line = "\(option.displayName) — score \(score.evaluatedWeight > 0 ? POPFormat.score(score.weightedScore) : "not evaluated")"
                if score.isDisqualified { line += " (disqualified by a hard constraint)" }
                else if score.failsMustHave { line += " (does not meet must-have requirements)" }
                if let cost = option.estimatedCost {
                    line += " · \(POPFormat.money(cost, currencyCode: decision.currencyCode))"
                }
                blocks.append(.bullet(line))
            }
        }

        let keyEvidence = final.keyEvidenceIDs.compactMap { store.state.evidenceItem(id: $0) }
        if !keyEvidence.isEmpty {
            blocks.append(.heading("Strongest Evidence"))
            for item in keyEvidence {
                var line = "\(item.displayTitle) — \(item.type.title), \(item.verification.title)"
                if !item.source.popIsBlank { line += " · \(item.source)" }
                blocks.append(.bullet(line))
            }
        }

        if !decision.acceptedUnknowns.isEmpty || !final.proceedWithGapsReason.popIsBlank {
            blocks.append(.heading("Known Limitations"))
            if !final.proceedWithGapsReason.popIsBlank {
                blocks.append(.body(final.proceedWithGapsReason))
            }
            for unknown in decision.acceptedUnknowns {
                blocks.append(.bullet("\(unknown.label) — \(unknown.reason)"))
            }
        }

        let risks = decision.risks.filter { $0.state == .accepted || $0.category == .critical }
        if !risks.isEmpty || !final.acceptedRisks.popIsBlank {
            blocks.append(.heading("Accepted Risks"))
            if !final.acceptedRisks.popIsBlank { blocks.append(.body(final.acceptedRisks)) }
            for risk in risks {
                blocks.append(.bullet("\(risk.displayTitle) — \(risk.category.title), \(risk.state.title)"))
            }
        }

        blocks.append(.heading("Review"))
        blocks.append(.keyValue("Outcome review date", POPFormat.date(final.outcomeReviewDate)))
        if let review = decision.outcomeReview, review.isComplete {
            blocks.append(.keyValue("Satisfaction", review.satisfaction?.title ?? "—"))
            blocks.append(.keyValue("Would choose again", review.wouldChooseAgain?.title ?? "—"))
            if !review.actualOutcome.popIsBlank {
                blocks.append(.keyValue("Actual outcome", review.actualOutcome))
            }
            if !review.whatWouldYouDoDifferently.popIsBlank {
                blocks.append(.keyValue("What would be done differently", review.whatWouldYouDoDifferently))
            }
        }

        blocks.append(.spacer(16))
        blocks.append(.rule)
        blocks.append(.subtitle("Generated by ProofPath on \(POPFormat.dateTime(Date())). Contains only data entered by the user."))

        do {
            exportURL = try PDFComposer.makePDF(fileName: "ProofPath \(decision.displayTitle)", blocks: blocks)
        } catch {
            exportError = error.localizedDescription
        }
        #endif
    }
}

// MARK: - Share support

struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

#if canImport(UIKit)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
