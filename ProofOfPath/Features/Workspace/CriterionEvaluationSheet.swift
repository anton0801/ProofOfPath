//
//  CriterionEvaluationSheet.swift
//  ProofOfPath
//
//  A rating is never "supported" without an explanation or linked evidence.
//

import SwiftUI

struct CriterionEvaluationSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var submission = POPSubmission()

    let decisionID: UUID
    let optionID: UUID
    let criterionID: UUID

    @State private var measuredValue = ""
    @State private var boolValue: Bool?
    @State private var rating: Int?
    @State private var reason = ""
    @State private var confidence: ConfidenceLevel = .medium
    @State private var showValidation = false
    @State private var showEvidencePicker = false
    @State private var showClearConfirm = false
    @State private var loaded = false

    private var decision: Decision? { store.state.decision(id: decisionID) }
    private var option: DecisionOption? { decision?.option(id: optionID) }
    private var criterion: Criterion? { decision?.criterion(id: criterionID) }
    private var scaleMax: Int { store.state.scaleMax }

    private var linkedEvidence: [Evidence] {
        store.state.evidence(forDecision: decisionID).filter { item in
            item.links.contains { $0.optionID == optionID && $0.criterionID == criterionID }
        }
    }

    private var supportingCount: Int {
        linkedEvidence.filter { $0.supports(optionID: optionID, criterionID: criterionID) }.count
    }

    private var contradictingCount: Int {
        linkedEvidence.filter { $0.contradicts(optionID: optionID, criterionID: criterionID) }.count
    }

    private var hasJudgement: Bool {
        (criterion?.kind == .yesNo) ? boolValue != nil : rating != nil
    }

    private var measuredNumeric: Double? { POPFormat.parseNumber(measuredValue) }

    private var measuredError: String? {
        guard let criterion, criterion.kind.expectsNumericValue else { return nil }
        guard showValidation, !measuredValue.popIsBlank, measuredNumeric == nil else { return nil }
        return "This criterion expects a number so it can be compared and checked against thresholds."
    }

    private var derivedStatus: EvaluationStatus {
        guard let criterion, let option else { return .notEvaluated }
        var preview = option.evaluation(for: criterionID) ?? Evaluation(criterionID: criterionID)
        preview.measuredValue = measuredValue
        preview.numericValue = measuredNumeric
        preview.boolValue = boolValue
        preview.rating = rating
        preview.reason = reason
        preview.confidence = confidence

        var previewOption = option
        if let index = previewOption.evaluations.firstIndex(where: { $0.criterionID == criterionID }) {
            previewOption.evaluations[index] = preview
        } else {
            previewOption.evaluations.append(preview)
        }
        return ScoringEngine.status(
            evaluation: preview,
            option: previewOption,
            criterion: criterion,
            evidence: store.state.evidence(forDecision: decisionID)
        )
    }

    private var canSave: Bool {
        guard hasJudgement || !measuredValue.popIsBlank else { return false }
        if let criterion, criterion.kind.expectsNumericValue, !measuredValue.popIsBlank, measuredNumeric == nil { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Group {
                if let decision, let option, let criterion {
                    content(decision: decision, option: option, criterion: criterion)
                } else {
                    POPEmptyState(icon: "questionmark.folder", title: "Not available",
                                  message: "This criterion or option was removed.",
                                  actionTitle: "Close", action: { dismiss() })
                        .background(POPColor.canvas.ignoresSafeArea())
                }
            }
        }
        .onAppear(perform: hydrate)
    }

    private func content(decision: Decision, option: DecisionOption, criterion: Criterion) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {

                header(option: option, criterion: criterion)

                // Measured value
                VStack(alignment: .leading, spacing: 10) {
                    POPSectionHeader(title: "Measured Value", subtitle: criterion.measurementMethod.popIsBlank
                                     ? "What did you actually observe?"
                                     : criterion.measurementMethod,
                                     icon: "ruler")
                    if criterion.kind == .yesNo {
                        POPFieldShell(label: "Does this option have it?") {
                            POPYesNoPicker(value: $boolValue)
                        }
                    } else if criterion.kind.expectsNumericValue {
                        POPNumberField(
                            label: "Measured Value",
                            text: $measuredValue,
                            placeholder: "e.g. 24",
                            hint: thresholdHint(criterion),
                            errorText: measuredError
                        )
                    } else {
                        POPTextField(
                            label: "Measured Value",
                            text: $measuredValue,
                            placeholder: "What you observed, in your own words",
                            hint: thresholdHint(criterion),
                            characterLimit: 120
                        )
                    }
                }

                // Rating
                if criterion.kind != .yesNo {
                    VStack(alignment: .leading, spacing: 10) {
                        POPSectionHeader(title: "Rating", subtitle: "Your judgement on the 1–\(scaleMax) scale.", icon: "star.leadinghalf.filled")
                        POPRatingPicker(rating: $rating, scaleMax: scaleMax)
                        if criterion.importance == .mustHave,
                           let threshold = POPFormat.parseNumber(criterion.minimumAcceptableValue),
                           let rating, Double(rating) < threshold {
                            POPBanner(
                                kind: .danger,
                                message: "Below the must-have threshold.",
                                detail: "This criterion requires at least \(POPFormat.decimal(threshold)). Saving this rating disqualifies the option."
                            )
                        }
                    }
                } else if boolValue == false, criterion.importance == .mustHave {
                    POPBanner(
                        kind: .danger,
                        message: "This is a Must Have.",
                        detail: "Answering No disqualifies this option from being the leader."
                    )
                }

                // Reason
                VStack(alignment: .leading, spacing: 8) {
                    POPTextEditor(
                        label: "Reason for Rating",
                        text: $reason,
                        placeholder: "Why this value? What convinced you?",
                        hint: "Without a reason or supporting evidence a rating stays Preliminary.",
                        characterLimit: 600,
                        minHeight: 92
                    )
                }

                // Confidence
                VStack(alignment: .leading, spacing: 10) {
                    POPSectionHeader(title: "Confidence", subtitle: "How sure are you about this specific value?", icon: "gauge.medium")
                    POPInlineSegments(
                        options: ConfidenceLevel.allCases,
                        selection: $confidence,
                        titleFor: { $0.title },
                        tintFor: { $0.color }
                    )
                }

                // Linked evidence
                linkedEvidenceCard(decision: decision)

                // Status preview
                statusCard

                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 8)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationTitle("Evaluate Option")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(POPColor.inkSecondary)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                POPToolbarSaveButton(title: "Save Evaluation", isSaving: submission.isRunning, isHighlighted: canSave) { save() }
            }
            ToolbarItem(placement: .bottomBar) {
                if hasExistingEvaluation {
                    Button(role: .destructive) { showClearConfirm = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Clear Evaluation")
                                .font(POPFont.calloutMedium)
                        }
                        .foregroundStyle(POPColor.danger)
                    }
                }
            }
        }
        .sheet(isPresented: $showEvidencePicker) {
            EvidenceLinkPicker(decisionID: decisionID, optionID: optionID, criterionID: criterionID)
        }
        .alert("Clear this evaluation?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                submission.run(store, .clearEvaluation(decisionID: decisionID, optionID: optionID, criterionID: criterionID)) { dismiss() }
            }
        } message: {
            Text("The rating, measured value and reason are removed. Linked evidence stays attached.")
        }
    }

    private var hasExistingEvaluation: Bool {
        guard let evaluation = option?.evaluation(for: criterionID) else { return false }
        return !evaluation.isEmpty
    }

    private func thresholdHint(_ criterion: Criterion) -> String? {
        var parts: [String] = []
        if !criterion.targetValue.popIsBlank { parts.append("Target: \(criterion.targetValue)") }
        if !criterion.minimumAcceptableValue.popIsBlank {
            let label = criterion.kind == .lowerIsBetter ? "Maximum acceptable" : "Minimum acceptable"
            parts.append("\(label): \(criterion.minimumAcceptableValue)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Header

    private func header(option: DecisionOption, criterion: Criterion) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                POPBadge(text: criterion.importance.title, icon: criterion.importance.icon,
                         color: criterion.importance.color, soft: criterion.importance.softColor, compact: true)
                POPBadge(text: criterion.kind.shortTitle, icon: criterion.kind.icon, compact: true)
                POPBadge(text: POPFormat.percent(criterion.weight),
                         color: POPColor.brandOrange, soft: POPColor.warningSoft, compact: true)
            }
            Text(criterion.displayName)
                .font(POPFont.title)
                .foregroundStyle(POPColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("for \(option.displayName)")
                .font(POPFont.callout)
                .foregroundStyle(POPColor.inkSecondary)
            if !criterion.details.popIsBlank {
                Text(criterion.details)
                    .font(POPFont.caption)
                    .foregroundStyle(POPColor.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .popCard()
    }

    // MARK: Linked evidence

    private func linkedEvidenceCard(decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(
                title: "Linked Evidence",
                subtitle: "Material that supports or contradicts this specific rating.",
                icon: "paperclip"
            )

            if linkedEvidence.isEmpty {
                POPInlineNote(text: "Nothing linked yet. A rating without evidence or a written reason stays Preliminary.")
            } else {
                ForEach(linkedEvidence) { item in
                    let relation = item.links.first { $0.optionID == optionID && $0.criterionID == criterionID }?.relation ?? .context
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: relation.icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(relation.color)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayTitle)
                                .font(POPFont.calloutMedium)
                                .foregroundStyle(POPColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 6) {
                                POPBadge(text: relation.shortTitle, color: relation.color, soft: relation.softColor, compact: true)
                                POPBadge(text: item.verification.title, icon: item.verification.icon,
                                         color: item.verification.color, soft: item.verification.softColor, compact: true)
                            }
                        }
                        Spacer(minLength: 0)
                        ConfidenceMarker(level: item.confidence, showLabel: false)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.surfaceMuted))
                }
            }

            POPSecondaryButton(title: "Link Evidence", icon: "link") {
                showEvidencePicker = true
            }
            .popRequiresConnection()
        }
        .popCard()
    }

    // MARK: Status

    private var statusCard: some View {
        let status = derivedStatus
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: status.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(status.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Status after saving")
                        .font(POPFont.micro)
                        .foregroundStyle(POPColor.inkTertiary)
                    Text(status.title)
                        .font(POPFont.cardTitle)
                        .foregroundStyle(POPColor.ink)
                }
                Spacer(minLength: 0)
            }
            Text(statusExplanation(status))
                .font(POPFont.caption)
                .foregroundStyle(POPColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(POPMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: POPMetrics.cardRadius, style: .continuous).fill(status.softColor))
    }

    private func statusExplanation(_ status: EvaluationStatus) -> String {
        switch status {
        case .notEvaluated:
            return "Nothing recorded yet, so this criterion is excluded from the score."
        case .preliminary:
            return supportingCount == 0
                ? "Recorded from your own judgement. Link at least one supporting evidence item to move it to Evidence Supported."
                : "Recorded, but the linked evidence does not support this rating yet."
        case .evidenceSupported:
            return "\(supportingCount) supporting \(supportingCount == 1 ? "item" : "items") back this rating."
        case .conflictingEvidence:
            return "\(contradictingCount) linked \(contradictingCount == 1 ? "item contradicts" : "items contradict") this rating. Resolve the conflict before you rely on it."
        }
    }

    // MARK: Persistence

    private func hydrate() {
        guard !loaded, let evaluation = option?.evaluation(for: criterionID) else {
            loaded = true
            return
        }
        loaded = true
        measuredValue = evaluation.measuredValue
        boolValue = evaluation.boolValue
        rating = evaluation.rating
        reason = evaluation.reason
        confidence = evaluation.confidence
    }

    private func save() {
        guard canSave else {
            showValidation = true
            Haptics.error()
            return
        }
        var evaluation = option?.evaluation(for: criterionID) ?? Evaluation(criterionID: criterionID)
        evaluation.measuredValue = measuredValue.popTrimmed
        evaluation.numericValue = measuredNumeric
        evaluation.boolValue = criterion?.kind == .yesNo ? boolValue : nil
        evaluation.rating = criterion?.kind == .yesNo ? nil : rating
        evaluation.reason = reason.popTrimmed
        evaluation.confidence = confidence
        submission.run(store, .saveEvaluation(decisionID: decisionID, optionID: optionID, evaluation: evaluation)) { dismiss() }
    }
}

// MARK: - Evidence link picker

struct EvidenceLinkPicker: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID
    let optionID: UUID?
    let criterionID: UUID?

    @State private var search = ""
    @State private var showNewEvidence = false

    private var candidates: [Evidence] {
        let all = store.state.evidence(forDecision: decisionID)
        guard !search.popIsBlank else { return all }
        let needle = search.popNormalizedForCompare
        return all.filter {
            $0.title.popNormalizedForCompare.contains(needle)
                || $0.summary.popNormalizedForCompare.contains(needle)
                || $0.source.popNormalizedForCompare.contains(needle)
        }
    }

    private func currentRelation(_ item: Evidence) -> EvidenceRelation? {
        item.links.first { $0.optionID == optionID && $0.criterionID == criterionID }?.relation
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    POPBanner(
                        kind: .neutral,
                        message: "Say how each item relates to this rating.",
                        detail: "One item can support one option and contradict another — the relation is per link, not per item."
                    )

                    if !store.state.evidence(forDecision: decisionID).isEmpty {
                        POPSearchField(text: $search, placeholder: "Search this decision's evidence")
                    }

                    if candidates.isEmpty {
                        POPEmptyState(
                            icon: "paperclip",
                            title: store.state.evidence(forDecision: decisionID).isEmpty ? "No evidence yet" : "No matches",
                            message: store.state.evidence(forDecision: decisionID).isEmpty
                                ? "Add a link, photo, document or note to start building the record."
                                : "Try a different search term.",
                            actionTitle: "Add Evidence",
                            action: { showNewEvidence = true },
                            compact: true
                        )
                        .popCard(padding: 4)
                    } else {
                        ForEach(candidates) { item in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: item.type.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(POPColor.brandOrange)
                                        .frame(width: 30, height: 30)
                                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(POPColor.warningSoft))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.displayTitle)
                                            .font(POPFont.calloutMedium)
                                            .foregroundStyle(POPColor.ink)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text("\(item.type.title) · \(POPFormat.date(item.dateCollected))")
                                            .font(POPFont.caption)
                                            .foregroundStyle(POPColor.inkSecondary)
                                    }
                                    Spacer(minLength: 0)
                                    ConfidenceMarker(level: item.confidence, showLabel: false)
                                }

                                HStack(spacing: 7) {
                                    ForEach(EvidenceRelation.allCases) { relation in
                                        POPPillButton(
                                            title: relation.shortTitle,
                                            icon: relation.icon,
                                            tint: relation.color,
                                            filled: currentRelation(item) == relation
                                        ) {
                                            setRelation(item: item, relation: relation)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    if currentRelation(item) != nil {
                                        Button(action: { removeLink(item) }) {
                                            Image(systemName: "link.badge.plus")
                                                .rotationEffect(.degrees(45))
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(POPColor.danger)
                                                .frame(width: 30, height: 30)
                                                .contentShape(Rectangle())
                                        }
                                        .accessibilityLabel(Text("Remove link"))
                                    }
                                }
                            }
                            .padding(11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surface))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(currentRelation(item) != nil ? POPColor.brandOrange.opacity(0.4) : POPColor.hairline,
                                              lineWidth: currentRelation(item) != nil ? 1.4 : 1))
                        }

                        POPSecondaryButton(title: "Add New Evidence", icon: "plus") {
                            showNewEvidence = true
                        }
                        .popRequiresConnection()
                    }

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 8)
            }
            .background(POPColor.canvas.ignoresSafeArea())
            .navigationTitle("Link Evidence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(POPFont.bodyMedium)
                        .foregroundStyle(POPColor.brandOrange)
                }
            }
            .sheet(isPresented: $showNewEvidence) {
                EvidenceEditorSheet(
                    existing: nil,
                    presetDecisionID: decisionID,
                    presetOptionID: optionID,
                    presetCriterionID: criterionID
                )
            }
        }
    }

    private func setRelation(item: Evidence, relation: EvidenceRelation) {
        if let existing = item.links.first(where: { $0.optionID == optionID && $0.criterionID == criterionID }) {
            if existing.relation == relation {
                store.send(.removeEvidenceLink(evidenceID: item.id, linkID: existing.id))
            } else {
                var updated = existing
                updated.relation = relation
                store.send(.updateEvidenceLink(evidenceID: item.id, link: updated))
            }
        } else {
            var link = EvidenceLink()
            link.optionID = optionID
            link.criterionID = criterionID
            link.relation = relation
            store.send(.addEvidenceLink(evidenceID: item.id, link: link))
        }
    }

    private func removeLink(_ item: Evidence) {
        guard let existing = item.links.first(where: { $0.optionID == optionID && $0.criterionID == criterionID }) else { return }
        store.send(.removeEvidenceLink(evidenceID: item.id, linkID: existing.id))
    }
}
