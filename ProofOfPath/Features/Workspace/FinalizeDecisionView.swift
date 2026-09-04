//
//  FinalizeDecisionView.swift
//  ProofOfPath
//
//  Recording the choice. A reason is required; the option must still exist.
//

import SwiftUI

struct FinalizeDecisionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID

    @State private var selectedOptionID: UUID?
    @State private var whyThisOption = ""
    @State private var keyEvidenceIDs: Set<UUID> = []
    @State private var acceptedTradeOffs = ""
    @State private var acceptedRisks = ""
    @State private var confidence = 3
    @State private var decisionDate = Date()
    @State private var reviewDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var gapsAcknowledgement = ""
    @State private var showValidation = false
    @State private var showConfirm = false
    @State private var loaded = false

    private var decision: Decision? { store.state.decision(id: decisionID) }

    private var report: ReadinessReport? {
        guard let decision else { return nil }
        return store.readiness(for: decision, selectedOptionID: selectedOptionID)
    }

    private var selectedOption: DecisionOption? { decision?.option(id: selectedOptionID) }

    private var reasonError: String? {
        guard showValidation, whyThisOption.popIsBlank else { return nil }
        return "A reason is required. This is the single most valuable thing you can leave your future self."
    }

    private var selectionError: String? {
        guard showValidation, selectedOptionID == nil else { return nil }
        return "Choose the option you are going with."
    }

    private var gapsError: String? {
        guard showValidation, report?.requiresGapAcknowledgement == true, gapsAcknowledgement.popIsBlank else { return nil }
        return "Explain why you are proceeding with these gaps."
    }

    private var reviewDateError: String? {
        reviewDate < decisionDate ? "The review date cannot be before the decision date." : nil
    }

    private var canFinalize: Bool {
        guard let report, report.canFinalize else { return false }
        guard selectedOptionID != nil, !whyThisOption.popIsBlank, reviewDateError == nil else { return false }
        if report.requiresGapAcknowledgement && gapsAcknowledgement.popIsBlank { return false }
        return true
    }

    var body: some View {
        Group {
            if let decision {
                content(decision)
            } else {
                POPEmptyState(icon: "questionmark.folder", title: "Decision not found",
                              message: "This decision was deleted.", actionTitle: "Back", action: { dismiss() })
                    .background(POPColor.canvas.ignoresSafeArea())
            }
        }
        .onAppear { hydrate() }
    }

    private func content(_ decision: Decision) -> some View {
        // Built once per render — the readiness report internally builds a
        // scoreboard, so recomputing it per subview would be wasteful.
        let report = store.readiness(for: decision, selectedOptionID: selectedOptionID)
        let scoreboard = store.scoreboard(for: decision)

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                CoinStrikeFeatureBanner(asset: "CoinStrikeFinalize")

                if !report.blockers.isEmpty {
                    POPBanner(
                        kind: .danger,
                        message: "This decision cannot be finalized yet.",
                        detail: report.blockers.map { "\($0.title): \($0.message)" }.joined(separator: "\n")
                    )
                }

                optionPicker(decision, scoreboard: scoreboard)

                POPTextEditor(
                    label: "Why This Option?",
                    text: $whyThisOption,
                    placeholder: "What decided it? Write it as if explaining to someone who was not part of the process.",
                    isRequired: true,
                    errorText: reasonError,
                    characterLimit: 1200,
                    minHeight: 120
                )

                keyEvidencePicker(decision)

                POPTextEditor(
                    label: "Accepted Trade-Offs",
                    text: $acceptedTradeOffs,
                    placeholder: "What are you giving up by choosing this?",
                    hint: "Naming these now stops them from feeling like surprises later.",
                    characterLimit: 800,
                    minHeight: 92
                )

                POPTextEditor(
                    label: "Accepted Risks",
                    text: $acceptedRisks,
                    placeholder: "Which risks are you knowingly carrying?",
                    characterLimit: 800,
                    minHeight: 92
                )

                if !decision.risks.filter({ $0.state == .accepted || $0.category == .critical }).isEmpty {
                    riskReminder(decision)
                }

                confidencePicker

                VStack(alignment: .leading, spacing: 10) {
                    POPSectionHeader(title: "Dates", icon: "calendar")
                    POPDateField(
                        label: "Decision Date",
                        date: Binding(get: { decisionDate }, set: { decisionDate = $0 ?? Date() })
                    )
                    POPDateField(
                        label: "Outcome Review Date",
                        date: Binding(get: { reviewDate }, set: { reviewDate = $0 ?? Date() }),
                        hint: "When you will come back and compare expectation with reality.",
                        errorText: reviewDateError
                    )
                }

                if report.requiresGapAcknowledgement {
                    gapsCard(report)
                }

                actions(report: report)

                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 10)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationTitle("Finalize Decision")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Finalize this decision?", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Finalize") { finalize() }
        } message: {
            Text("A read-only snapshot of your criteria, weights, ratings and evidence is saved. You can reopen the decision later, but the snapshot never changes.")
        }
    }

    // MARK: Option picker

    private func optionPicker(_ decision: Decision, scoreboard: DecisionScoreboard) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Selected Option", subtitle: "Options that break a hard constraint cannot be chosen.", icon: "checkmark.seal")

            if decision.comparableOptions.isEmpty {
                POPInlineNote(text: "There are no options to choose from.", icon: "exclamationmark.triangle.fill", tint: POPColor.danger)
            } else {
                ForEach(decision.comparableOptions) { option in
                    let score = scoreboard.score(for: option.id)
                    let blocked = score?.isDisqualified ?? false
                    Button(action: {
                        guard !blocked else {
                            Haptics.error()
                            return
                        }
                        Haptics.selection()
                        selectedOptionID = option.id
                    }) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: selectedOptionID == option.id ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(selectedOptionID == option.id ? POPColor.success : POPColor.hairline)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.displayName)
                                    .font(POPFont.calloutMedium)
                                    .foregroundStyle(blocked ? POPColor.inkTertiary : POPColor.ink)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 6) {
                                    if let score, score.evaluatedWeight > 0 {
                                        POPBadge(text: "Score \(POPFormat.score(score.weightedScore))", compact: true)
                                    }
                                    if scoreboard.leaderID == option.id {
                                        POPBadge(text: "Leader", icon: "crown.fill",
                                                 color: POPColor.graphite, soft: POPColor.brandYellow, compact: true)
                                    }
                                    if blocked {
                                        POPBadge(text: "Disqualified", icon: "lock.slash",
                                                 color: POPColor.danger, soft: POPColor.dangerSoft, compact: true)
                                    } else if score?.failsMustHave == true {
                                        POPBadge(text: "Fails a must-have", icon: "exclamationmark.circle",
                                                 color: POPColor.danger, soft: POPColor.dangerSoft, compact: true)
                                    }
                                }
                                if blocked, let score {
                                    Text(score.constraintResults.first { $0.outcome == .violates }?.explanation ?? "")
                                        .font(POPFont.caption)
                                        .foregroundStyle(POPColor.danger)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selectedOptionID == option.id ? POPColor.successSoft : POPColor.surface))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selectedOptionID == option.id ? POPColor.success.opacity(0.5) : POPColor.hairline,
                                          lineWidth: selectedOptionID == option.id ? 1.5 : 1))
                        .opacity(blocked ? 0.6 : 1)
                    }
                    .buttonStyle(POPPressStyle())
                    .disabled(blocked)
                }
            }

            if let selectionError {
                POPInlineNote(text: selectionError, icon: "exclamationmark.circle.fill", tint: POPColor.danger)
            }

            if let selectedOption, selectedOption.status == .rejected {
                POPBanner(kind: .danger, message: "This option is marked Rejected.",
                          detail: "Restore it in the Options workspace before finalizing.")
            }
        }
        .popCard()
    }

    // MARK: Key evidence

    private func keyEvidencePicker(_ decision: Decision) -> some View {
        let items = store.state.evidence(forDecision: decisionID)
        return VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(
                title: "Key Evidence",
                subtitle: "The handful of items that actually moved the decision.",
                icon: "paperclip"
            )
            if items.isEmpty {
                POPInlineNote(text: "No evidence attached to this decision.")
            } else {
                ForEach(items) { item in
                    Button(action: {
                        Haptics.selection()
                        if keyEvidenceIDs.contains(item.id) {
                            keyEvidenceIDs.remove(item.id)
                        } else {
                            keyEvidenceIDs.insert(item.id)
                        }
                    }) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: keyEvidenceIDs.contains(item.id) ? "checkmark.square.fill" : "square")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(keyEvidenceIDs.contains(item.id) ? POPColor.brandOrange : POPColor.hairline)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayTitle)
                                    .font(POPFont.calloutMedium)
                                    .foregroundStyle(POPColor.ink)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 6) {
                                    POPBadge(text: item.verification.title, color: item.verification.color,
                                             soft: item.verification.softColor, compact: true)
                                    ConfidenceMarker(level: item.confidence, showLabel: false)
                                }
                            }
                            Spacer(minLength: 0)
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

    // MARK: Risk reminder

    private func riskReminder(_ decision: Decision) -> some View {
        let relevant = decision.risks.filter { $0.state == .accepted || $0.category == .critical }
        return VStack(alignment: .leading, spacing: 9) {
            POPSectionHeader(title: "Risks on the record", subtitle: "Recorded separately from your written summary above.", icon: "exclamationmark.triangle")
            ForEach(relevant) { risk in
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
        .popCard()
    }

    // MARK: Confidence

    private var confidencePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            POPSectionHeader(title: "Confidence in Decision", subtitle: "How sure are you, right now, before the outcome is known?", icon: "gauge.medium")
            POPRatingPicker(rating: Binding(
                get: { confidence },
                set: { confidence = $0 ?? confidence }
            ), scaleMax: 5, allowsClear: false)
        }
        .popCard()
    }

    // MARK: Gaps

    private func gapsCard(_ report: ReadinessReport) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Proceed with Known Gaps", icon: "hand.raised")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(report.warnings) { warning in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(POPColor.brandOrange)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(warning.title)
                                .font(POPFont.calloutMedium)
                                .foregroundStyle(POPColor.ink)
                            Text(warning.message)
                                .font(POPFont.caption)
                                .foregroundStyle(POPColor.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.warningSoft))

            POPTextEditor(
                label: "Why are you comfortable proceeding?",
                text: $gapsAcknowledgement,
                placeholder: "e.g. The remaining unknowns are small enough that they cannot change the ranking.",
                isRequired: true,
                errorText: gapsError,
                characterLimit: 600,
                minHeight: 100
            )
        }
        .popCard()
    }

    // MARK: Actions

    private func actions(report: ReadinessReport) -> some View {
        VStack(spacing: 10) {
            POPPrimaryButton(title: "Finalize Decision", icon: "checkmark.seal", isEnabled: canFinalize) {
                showConfirm = true
            }
            HStack(spacing: 10) {
                POPSecondaryButton(title: "Save as Draft", icon: "tray.and.arrow.down") {
                    saveDraft()
                }
                POPSecondaryButton(title: "Back to Compare", icon: "tablecells") {
                    dismiss()
                }
            }
            if !canFinalize {
                POPInlineNote(
                    text: blockReason(report: report),
                    icon: "info.circle",
                    tint: POPColor.inkSecondary
                )
            }
        }
    }

    private func blockReason(report: ReadinessReport) -> String {
        if !report.blockers.isEmpty {
            return "Fix the blocking checks in Decision Readiness first."
        }
        if selectedOptionID == nil { return "Choose an option to finalize." }
        if whyThisOption.popIsBlank { return "Write why you chose it." }
        if reviewDateError != nil { return "Fix the review date." }
        if report.requiresGapAcknowledgement && gapsAcknowledgement.popIsBlank {
            return "Acknowledge the known gaps in writing."
        }
        return ""
    }

    // MARK: Persistence

    private func hydrate() {
        guard !loaded, let decision else { return }
        loaded = true
        if let final = decision.finalDecision {
            selectedOptionID = final.selectedOptionID
            whyThisOption = final.whyThisOption
            keyEvidenceIDs = Set(final.keyEvidenceIDs)
            acceptedTradeOffs = final.acceptedTradeOffs
            acceptedRisks = final.acceptedRisks
            confidence = final.confidence
            decisionDate = final.decisionDate
            reviewDate = final.outcomeReviewDate
            gapsAcknowledgement = final.proceedWithGapsReason
        } else {
            // Pre-select the current leader as a starting point, never as a decision.
            selectedOptionID = store.scoreboard(for: decision).leaderID
        }
    }

    private func buildRecord() -> FinalDecision {
        var record = decision?.finalDecision ?? FinalDecision()
        record.selectedOptionID = selectedOptionID
        record.whyThisOption = whyThisOption.popTrimmed
        record.keyEvidenceIDs = Array(keyEvidenceIDs)
        record.acceptedTradeOffs = acceptedTradeOffs.popTrimmed
        record.acceptedRisks = acceptedRisks.popTrimmed
        record.confidence = confidence
        record.decisionDate = decisionDate
        record.outcomeReviewDate = reviewDate
        record.proceedWithGapsReason = gapsAcknowledgement.popTrimmed
        return record
    }

    private func saveDraft() {
        store.send(.saveFinalDecisionDraft(decisionID: decisionID, decisionRecord: buildRecord()))
    }

    private func finalize() {
        guard canFinalize else {
            showValidation = true
            Haptics.error()
            return
        }
        store.send(.finalizeDecision(decisionID: decisionID, decisionRecord: buildRecord()))
        dismiss()
    }
}
