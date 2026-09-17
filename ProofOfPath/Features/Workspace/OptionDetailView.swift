//
//  OptionDetailView.swift
//  ProofOfPath
//
//  Overview · Criteria · Evidence · Claims · Risks · Activity
//

import SwiftUI

enum OptionTab: String, CaseIterable, Identifiable, Hashable {
    case overview
    case criteria
    case evidence
    case claims
    case risks
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .criteria: return "Criteria"
        case .evidence: return "Evidence"
        case .claims: return "Claims"
        case .risks: return "Risks"
        case .activity: return "Activity"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "info.circle"
        case .criteria: return "list.bullet.indent"
        case .evidence: return "paperclip"
        case .claims: return "quote.bubble"
        case .risks: return "exclamationmark.triangle"
        case .activity: return "clock.arrow.circlepath"
        }
    }
}

struct OptionDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var submission = POPSubmission()

    let decisionID: UUID
    let optionID: UUID

    @State private var tab: OptionTab = .overview
    @State private var showEditor = false
    @State private var evaluatingCriterion: Criterion?
    @State private var showEvidenceEditor = false
    @State private var showClaimEditor = false
    @State private var showRiskEditor = false
    @State private var pendingDelete = false

    private var decision: Decision? { store.state.decision(id: decisionID) }
    private var option: DecisionOption? { decision?.option(id: optionID) }

    var body: some View {
        Group {
            if let decision, let option {
                content(decision: decision, option: option)
            } else {
                POPEmptyState(
                    icon: "questionmark.folder",
                    title: "Option not found",
                    message: "This option was deleted.",
                    actionTitle: "Back",
                    action: { dismiss() }
                )
                .background(POPColor.canvas.ignoresSafeArea())
            }
        }
    }

    private func content(decision: Decision, option: DecisionOption) -> some View {
        let score = store.scoreboard(for: decision).score(for: option.id)

        return VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(OptionTab.allCases) { item in
                        POPChip(title: item.title, icon: item.icon, isSelected: tab == item) {
                            withAnimation(.easeInOut(duration: 0.2)) { tab = item }
                        }
                    }
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.vertical, 9)
            }
            .background(
                POPColor.surface
                    .overlay(alignment: .bottom) { Rectangle().fill(POPColor.hairline).frame(height: 1) }
            )

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                    OptionHeaderCard(option: option, decision: decision, score: score)

                    switch tab {
                    case .overview:
                        OptionOverviewTab(decision: decision, option: option, score: score)
                    case .criteria:
                        OptionCriteriaTab(decision: decision, option: option, score: score) { criterion in
                            evaluatingCriterion = criterion
                        }
                    case .evidence:
                        OptionEvidenceTab(decision: decision, option: option, onAdd: { showEvidenceEditor = true })
                    case .claims:
                        OptionClaimsTab(decision: decision, option: option, onAdd: { showClaimEditor = true })
                    case .risks:
                        OptionRisksTab(decision: decision, option: option, onAdd: { showRiskEditor = true })
                    case .activity:
                        OptionActivityTab(decision: decision, option: option)
                    }

                    Color.clear.frame(height: 16)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 12)
            }
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationTitle(option.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showEditor = true } label: { Label("Edit Option", systemImage: "pencil") }
                    Button {
                        store.send(.duplicateOption(decisionID: decisionID, optionID: optionID))
                    } label: { Label("Duplicate as New Option", systemImage: "plus.square.on.square") }
                    Divider()
                    Menu("Change Status") {
                        ForEach(OptionStatus.allCases.filter { $0 != .selected }) { status in
                            Button {
                                store.send(.setOptionStatus(decisionID: decisionID, optionID: optionID, status: status))
                            } label: { Label(status.title, systemImage: status.icon) }
                        }
                    }
                    if option.status == .rejected {
                        Button {
                            store.send(.setOptionStatus(decisionID: decisionID, optionID: optionID, status: .researching))
                        } label: { Label("Restore Option", systemImage: "arrow.uturn.backward") }
                    } else {
                        Button {
                            store.send(.setOptionStatus(decisionID: decisionID, optionID: optionID, status: .rejected))
                        } label: { Label("Reject Option", systemImage: "xmark.circle") }
                    }
                    Divider()
                    Button(role: .destructive) { pendingDelete = true } label: {
                        Label("Delete Option", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(POPColor.graphite)
                }
                .accessibilityLabel(Text("Option actions"))
            }
        }
        .sheet(isPresented: $showEditor) {
            OptionEditorSheet(decisionID: decisionID, existing: option)
        }
        .sheet(item: $evaluatingCriterion) { criterion in
            CriterionEvaluationSheet(decisionID: decisionID, optionID: optionID, criterionID: criterion.id)
        }
        .sheet(isPresented: $showEvidenceEditor) {
            EvidenceEditorSheet(existing: nil, presetDecisionID: decisionID, presetOptionID: optionID)
        }
        .sheet(isPresented: $showClaimEditor) {
            ClaimEditorSheet(decisionID: decisionID, existing: nil, presetOptionID: optionID)
        }
        .sheet(isPresented: $showRiskEditor) {
            RiskEditorSheet(decisionID: decisionID, existing: nil, presetOptionID: optionID)
        }
        .alert("Delete this option?", isPresented: $pendingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                submission.run(store, .deleteOption(decisionID: decisionID, optionID: optionID)) { dismiss() }
            }
        } message: {
            Text("Its evaluations, evidence links and risks will be removed. Rejecting it instead keeps the record.")
        }
    }
}

// MARK: - Header

struct OptionHeaderCard: View {
    @EnvironmentObject private var store: AppStore
    let option: DecisionOption
    let decision: Decision
    let score: OptionScore?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let image = store.image(named: option.imageFileName) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 70, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(POPColor.hairline, lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 6) {
                    POPBadge(text: option.status.title, icon: option.status.icon,
                             color: option.status.color, soft: option.status.softColor)
                    if !option.providerOrBrand.popIsBlank {
                        Text(option.providerOrBrand)
                            .font(POPFont.callout)
                            .foregroundStyle(POPColor.inkSecondary)
                    }
                    if let cost = option.estimatedCost {
                        Text(POPFormat.money(cost, currencyCode: decision.currencyCode))
                            .font(POPFont.numeric)
                            .foregroundStyle(POPColor.ink)
                    }
                }
                Spacer(minLength: 0)

                if let score, score.evaluatedWeight > 0 {
                    VStack(spacing: 1) {
                        Text(POPFormat.score(score.weightedScore))
                            .font(POPFont.numericLarge)
                            .foregroundStyle(score.isEligibleLeader ? POPColor.ink : POPColor.inkTertiary)
                            .monospacedDigit()
                        Text("weighted score")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(POPColor.inkTertiary)
                    }
                }
            }

            if let score {
                if score.isDisqualified {
                    POPBanner(
                        kind: .danger,
                        message: "Disqualified by a hard constraint.",
                        detail: score.constraintResults.filter { $0.outcome == .violates }
                            .map(\.explanation).joined(separator: "\n")
                    )
                } else if score.failsMustHave {
                    POPBanner(
                        kind: .danger,
                        message: "Does Not Meet Must-Have Requirements",
                        detail: score.mustHaveResults.filter { $0.outcome == .failed }
                            .map { "\($0.criterion.displayName): \($0.explanation)" }
                            .joined(separator: "\n")
                    )
                }
                if let incomplete = score.incompleteMessage {
                    POPInlineNote(text: incomplete, icon: "exclamationmark.circle", tint: POPColor.brandOrange)
                }
            }
        }
        .popCard()
    }
}

// MARK: - Overview tab

struct OptionOverviewTab: View {
    @EnvironmentObject private var store: AppStore
    let decision: Decision
    let option: DecisionOption
    let score: OptionScore?

    var body: some View {
        VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 11) {
                POPSectionHeader(title: "Details", icon: "info.circle")
                POPKeyValueRow(label: "Estimated Cost",
                               value: POPFormat.moneyOptional(option.estimatedCost, currencyCode: decision.currencyCode, placeholder: "Not recorded"),
                               valueColor: option.estimatedCost == nil ? POPColor.brandOrange : POPColor.ink,
                               icon: "tag")
                if let recurring = option.cost.recurringCost {
                    POPDivider()
                    POPKeyValueRow(label: "Recurring Cost",
                                   value: "\(POPFormat.money(recurring, currencyCode: decision.currencyCode)) \(option.cost.recurringPeriod.title.lowercased())",
                                   icon: "arrow.clockwise")
                }
                POPDivider()
                POPKeyValueRow(label: "Budget Fit", value: budgetFitText,
                               valueColor: budgetFitColor, icon: "target")
                if !option.availability.popIsBlank {
                    POPDivider()
                    POPKeyValueRow(label: "Availability", value: option.availability, icon: "shippingbox")
                }
                if !option.website.popIsBlank {
                    POPDivider()
                    POPKeyValueRow(label: "Website", value: option.website, icon: "link", isMultiline: true)
                }
                if !option.contactDetails.popIsBlank {
                    POPDivider()
                    POPKeyValueRow(label: "Contact", value: option.contactDetails, icon: "phone", isMultiline: true)
                }
            }
            .popCard()

            if !option.keyDetails.popIsBlank {
                VStack(alignment: .leading, spacing: 8) {
                    POPSectionHeader(title: "Key Details", icon: "text.alignleft")
                    Text(option.keyDetails)
                        .font(POPFont.body)
                        .foregroundStyle(POPColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .popCard()
            }

            if !decision.hardConstraints.isEmpty {
                constraintsCard
            }

            if let score, !score.mustHaveResults.isEmpty {
                mustHaveCard(score)
            }
        }
    }

    private var budgetFitText: String {
        CostEngine.budgetFit(for: option, decision: decision).title
    }

    private var budgetFitColor: Color {
        switch CostEngine.budgetFit(for: option, decision: decision) {
        case .above: return POPColor.danger
        case .inside: return POPColor.success
        case .below: return POPColor.inkSecondary
        default: return POPColor.inkTertiary
        }
    }

    private var constraintsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Hard Constraints", subtitle: "How this option measures against each one.", icon: "lock")
            ForEach(ConstraintEngine.results(for: option, decision: decision)) { result in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: outcomeIcon(result.outcome))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(outcomeColor(result.outcome))
                        Text(result.constraint.title.popIsBlank ? "Untitled constraint" : result.constraint.title)
                            .font(POPFont.calloutMedium)
                            .foregroundStyle(POPColor.ink)
                        Spacer(minLength: 0)
                        POPBadge(text: result.outcome.title, color: outcomeColor(result.outcome),
                                 soft: outcomeSoft(result.outcome), compact: true)
                    }
                    Text(result.explanation)
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if case .manual = result.constraint.check {
                        HStack(spacing: 7) {
                            ForEach(ManualConstraintStatus.allCases) { status in
                                POPPillButton(
                                    title: status.title,
                                    icon: status.icon,
                                    tint: status.color,
                                    filled: option.manualStatus(for: result.constraint.id) == status
                                ) {
                                    store.send(.setManualConstraintStatus(
                                        decisionID: decision.id,
                                        optionID: option.id,
                                        constraintID: result.constraint.id,
                                        status: status
                                    ))
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.surfaceMuted))
            }
        }
        .popCard()
    }

    private func mustHaveCard(_ score: OptionScore) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Must-Have Status", icon: "exclamationmark.circle")
            ForEach(score.mustHaveResults) { result in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: mustHaveIcon(result.outcome))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(mustHaveColor(result.outcome))
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.criterion.displayName)
                            .font(POPFont.calloutMedium)
                            .foregroundStyle(POPColor.ink)
                        Text(result.explanation)
                            .font(POPFont.caption)
                            .foregroundStyle(POPColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    POPBadge(text: result.outcome.title, color: mustHaveColor(result.outcome),
                             soft: mustHaveSoft(result.outcome), compact: true)
                }
            }
        }
        .popCard()
    }

    private func outcomeIcon(_ outcome: ConstraintOutcome) -> String {
        switch outcome {
        case .meets: return "checkmark.circle.fill"
        case .violates: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private func outcomeColor(_ outcome: ConstraintOutcome) -> Color {
        switch outcome {
        case .meets: return POPColor.success
        case .violates: return POPColor.danger
        case .unknown: return POPColor.inkSecondary
        }
    }

    private func outcomeSoft(_ outcome: ConstraintOutcome) -> Color {
        switch outcome {
        case .meets: return POPColor.successSoft
        case .violates: return POPColor.dangerSoft
        case .unknown: return POPColor.neutralSoft
        }
    }

    private func mustHaveIcon(_ outcome: MustHaveOutcome) -> String {
        switch outcome {
        case .met: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        case .noThreshold: return "exclamationmark.triangle"
        }
    }

    private func mustHaveColor(_ outcome: MustHaveOutcome) -> Color {
        switch outcome {
        case .met: return POPColor.success
        case .failed: return POPColor.danger
        case .unknown: return POPColor.inkSecondary
        case .noThreshold: return POPColor.brandOrange
        }
    }

    private func mustHaveSoft(_ outcome: MustHaveOutcome) -> Color {
        switch outcome {
        case .met: return POPColor.successSoft
        case .failed: return POPColor.dangerSoft
        case .unknown: return POPColor.neutralSoft
        case .noThreshold: return POPColor.warningSoft
        }
    }
}

// MARK: - Criteria tab

struct OptionCriteriaTab: View {
    @EnvironmentObject private var store: AppStore
    let decision: Decision
    let option: DecisionOption
    let score: OptionScore?
    let onEvaluate: (Criterion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            POPSectionHeader(
                title: "Evaluation",
                subtitle: "Tap a criterion to record the measured value, your rating and why.",
                icon: "list.bullet.indent"
            )

            if decision.criteria.isEmpty {
                POPEmptyState(icon: "list.bullet.indent", title: "No criteria",
                              message: "Add criteria in the Criteria Workshop first.", compact: true)
                    .popCard(padding: 4)
            } else {
                ForEach(decision.sortedCriteria) { criterion in
                    EvaluationRow(
                        criterion: criterion,
                        option: option,
                        decision: decision,
                        cell: score?.cells[criterion.id],
                        scaleMax: store.state.scaleMax,
                        onTap: { onEvaluate(criterion) }
                    )
                }
            }
        }
    }
}

struct EvaluationRow: View {
    let criterion: Criterion
    let option: DecisionOption
    let decision: Decision
    let cell: CellScore?
    let scaleMax: Int
    let onTap: () -> Void

    private var evaluation: Evaluation? { option.evaluation(for: criterion.id) }
    private var status: EvaluationStatus { cell?.status ?? .notEvaluated }

    var body: some View {
        Button(action: {
            Haptics.tap()
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(criterion.displayName)
                                .font(POPFont.calloutMedium)
                                .foregroundStyle(POPColor.ink)
                                .multilineTextAlignment(.leading)
                            if criterion.importance == .mustHave {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(POPColor.brandOrange)
                            }
                        }
                        HStack(spacing: 6) {
                            POPBadge(text: status.title, icon: status.icon,
                                     color: status.color, soft: status.softColor, compact: true)
                            POPBadge(text: POPFormat.percent(criterion.weight), compact: true)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        if criterion.kind == .yesNo {
                            if let value = evaluation?.boolValue {
                                Text(value ? "Yes" : "No")
                                    .font(POPFont.numeric)
                                    .foregroundStyle(value ? POPColor.success : POPColor.danger)
                            } else {
                                Text("—").font(POPFont.numeric).foregroundStyle(POPColor.inkTertiary)
                            }
                        } else {
                            RatingDots(rating: evaluation?.rating, scaleMax: scaleMax)
                        }
                        if let confidence = cell?.confidence {
                            ConfidenceMarker(level: confidence, showLabel: false)
                        }
                    }
                }

                HStack(spacing: 10) {
                    if let raw = cell?.rawDisplay, raw != "—" {
                        HStack(spacing: 4) {
                            Image(systemName: "ruler").font(.system(size: 10, weight: .semibold))
                            Text(raw).font(POPFont.caption).lineLimit(1)
                        }
                        .foregroundStyle(POPColor.inkSecondary)
                    }
                    if let cell {
                        EvidenceCoverageIndicator(supporting: cell.supportingEvidence, contradicting: cell.contradictingEvidence)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(POPColor.inkTertiary)
                }

                if let reason = evaluation?.reason, !reason.popIsBlank {
                    Text(reason)
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(status == .conflictingEvidence ? POPColor.danger.opacity(0.4) : POPColor.hairline,
                              lineWidth: status == .conflictingEvidence ? 1.4 : 1))
        }
        .buttonStyle(POPPressStyle())
    }
}

// MARK: - Evidence tab

struct OptionEvidenceTab: View {
    @EnvironmentObject private var store: AppStore
    let decision: Decision
    let option: DecisionOption
    let onAdd: () -> Void

    private var items: [Evidence] {
        store.state.evidence(forDecision: decision.id)
            .filter { item in item.links.contains { $0.optionID == option.id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            POPSectionHeader(title: "Evidence", subtitle: "Everything linked to this option.", icon: "paperclip")

            if items.isEmpty {
                POPEmptyState(
                    icon: "paperclip",
                    title: "No evidence linked",
                    message: "Without evidence every rating here is only an opinion.",
                    actionTitle: "Add Evidence",
                    action: onAdd,
                    compact: true
                )
                .popCard(padding: 4)
            } else {
                ForEach(items) { item in
                    NavigationLink(value: AppRoute.evidenceDetail(item.id)) {
                        EvidenceRow(evidence: item, decision: decision, showsLinks: true)
                    }
                    .buttonStyle(POPPressStyle())
                }
                POPSecondaryButton(title: "Add Evidence", icon: "plus", action: onAdd)
                .popRequiresConnection()
            }
        }
    }
}

// MARK: - Claims tab

struct OptionClaimsTab: View {
    @EnvironmentObject private var store: AppStore
    let decision: Decision
    let option: DecisionOption
    let onAdd: () -> Void

    @State private var editingClaim: Claim?

    private var claims: [Claim] {
        decision.claims.filter { $0.optionID == option.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            POPSectionHeader(
                title: "Claims",
                subtitle: "Promises and assumptions attached to this option, and how well they hold up.",
                icon: "quote.bubble"
            )

            if claims.isEmpty {
                POPEmptyState(
                    icon: "quote.bubble",
                    title: "No claims recorded",
                    message: "Record what the seller promised so you can check it later.",
                    actionTitle: "Add Claim",
                    action: onAdd,
                    compact: true
                )
                .popCard(padding: 4)
            } else {
                ForEach(claims) { claim in
                    ClaimRow(claim: claim, decision: decision) { editingClaim = claim }
                }
                POPSecondaryButton(title: "Add Claim", icon: "plus", action: onAdd)
                .popRequiresConnection()
            }
        }
        .sheet(item: $editingClaim) { claim in
            ClaimDetailSheet(decisionID: decision.id, claimID: claim.id)
        }
    }
}

// MARK: - Risks tab

struct OptionRisksTab: View {
    @EnvironmentObject private var store: AppStore
    let decision: Decision
    let option: DecisionOption
    let onAdd: () -> Void

    @State private var editingRisk: Risk?

    private var risks: [Risk] {
        decision.risks.filter { $0.optionID == option.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            POPSectionHeader(title: "Risks", subtitle: "What could go wrong if you pick this option.", icon: "exclamationmark.triangle")

            if risks.isEmpty {
                POPEmptyState(
                    icon: "shield",
                    title: "No risks recorded",
                    message: "Name what could go wrong now, while you can still change your mind cheaply.",
                    actionTitle: "Add Risk",
                    action: onAdd,
                    compact: true
                )
                .popCard(padding: 4)
            } else {
                ForEach(risks) { risk in
                    RiskRow(risk: risk, decision: decision) { editingRisk = risk }
                }
                POPSecondaryButton(title: "Add Risk", icon: "plus", action: onAdd)
                .popRequiresConnection()
            }
        }
        .sheet(item: $editingRisk) { risk in
            RiskEditorSheet(decisionID: decision.id, existing: risk, presetOptionID: option.id)
        }
    }
}

// MARK: - Activity tab

struct OptionActivityTab: View {
    let decision: Decision
    let option: DecisionOption

    private var events: [ActivityEvent] {
        decision.activity(forOption: option.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            POPSectionHeader(title: "Activity", subtitle: "Everything that changed on this option, in order.", icon: "clock.arrow.circlepath")

            if events.isEmpty {
                POPEmptyState(icon: "clock", title: "Nothing recorded yet",
                              message: "Changes to this option will appear here.", compact: true)
                    .popCard(padding: 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        ActivityRow(event: event, isLast: index == events.count - 1)
                    }
                }
                .popCard()
            }
        }
    }
}

// MARK: - Activity row

struct ActivityRow: View {
    let event: ActivityEvent
    var isLast: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(event.kind.color.opacity(0.14)).frame(width: 26, height: 26)
                    Image(systemName: event.kind.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(event.kind.color)
                }
                if !isLast {
                    Rectangle()
                        .fill(POPColor.hairline)
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.summary)
                    .font(POPFont.calloutMedium)
                    .foregroundStyle(POPColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !event.detail.popIsBlank {
                    Text(event.detail)
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(POPFormat.dateTime(event.date))
                    .font(.system(size: 10.5))
                    .foregroundStyle(POPColor.inkTertiary)
            }
            .padding(.bottom, isLast ? 0 : 14)

            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
