//
//  OptionsSection.swift
//  ProofOfPath
//
//  Options Workspace — every option is a full record, not a row in a list.
//

import SwiftUI

struct OptionsSection: View {
    @Environment(AppStore.self) private var store
    let decisionID: UUID

    @State private var showEditor = false
    @State private var editingOption: DecisionOption?
    @State private var pendingDelete: DecisionOption?
    @State private var statusFilter: OptionStatus?
    @State private var route: AppRoute?

    private var decision: Decision? { store.state.decision(id: decisionID) }

    private func filtered(_ decision: Decision) -> [DecisionOption] {
        guard let statusFilter else { return decision.sortedOptions }
        return decision.sortedOptions.filter { $0.status == statusFilter }
    }

    var body: some View {
        if let decision {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                WorkspaceSectionIntro(
                    title: "Options",
                    subtitle: "Everything you are actually choosing between, with its own evidence, claims and risks.",
                    icon: "square.stack.3d.up"
                )

                if decision.options.isEmpty {
                    POPEmptyState(
                        icon: "square.stack.3d.up",
                        title: "No options yet",
                        message: decision.criteria.isEmpty
                            ? "Add criteria first, then add the options you want to compare — each new option starts with an empty row per criterion."
                            : "Add the options you want to compare. Each one starts Not Evaluated on all \(decision.criteria.count) criteria.",
                        actionTitle: "Add Option",
                        action: {
                            editingOption = nil
                            showEditor = true
                        }
                    )
                    .popCard(padding: 6)
                } else {
                    summary(decision)
                    filterStrip(decision)
                    list(decision)
                    POPPrimaryButton(title: "Add Option", icon: "plus") {
                        editingOption = nil
                        showEditor = true
                    }
                }
            }
            .sheet(isPresented: $showEditor, onDismiss: { editingOption = nil }) {
                OptionEditorSheet(decisionID: decisionID, existing: editingOption)
            }
            .navigationDestination(item: $route) { destination in
                if case .optionDetail(let decisionID, let optionID) = destination {
                    OptionDetailView(decisionID: decisionID, optionID: optionID)
                }
            }
            .alert(
                "Delete this option?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete
            ) { option in
                Button("Cancel", role: .cancel) { pendingDelete = nil }
                Button("Delete", role: .destructive) {
                    store.send(.deleteOption(decisionID: decisionID, optionID: option.id))
                    pendingDelete = nil
                }
            } message: { option in
                Text(deleteMessage(for: option, in: decision))
            }
        }
    }

    private func deleteMessage(for option: DecisionOption, in decision: Decision) -> String {
        let evaluations = option.evaluations.filter { !$0.isEmpty }.count
        let evidence = store.state.evidence(forDecision: decision.id)
            .filter { item in item.links.contains { $0.optionID == option.id } }.count
        let risks = decision.risks.filter { $0.optionID == option.id }.count
        let claims = decision.claims.filter { $0.optionID == option.id }.count

        var parts: [String] = []
        if evaluations > 0 { parts.append("\(evaluations) \(evaluations == 1 ? "evaluation" : "evaluations")") }
        if evidence > 0 { parts.append("\(evidence) evidence \(evidence == 1 ? "link" : "links")") }
        if risks > 0 { parts.append("\(risks) \(risks == 1 ? "risk" : "risks") (deleted too)") }
        if claims > 0 { parts.append("\(claims) \(claims == 1 ? "claim" : "claims") (unlinked)") }

        if parts.isEmpty { return "“\(option.displayName)” has no attached data yet." }
        return "“\(option.displayName)” carries \(parts.joined(separator: ", ")). Rejecting it instead keeps the record."
    }

    // MARK: Summary

    private func summary(_ decision: Decision) -> some View {
        let scoreboard = store.scoreboard(for: decision)
        let disqualified = scoreboard.scores.filter(\.isDisqualified).count
        let evaluatedFully = scoreboard.scores.filter(\.isComplete).count

        return HStack(spacing: 10) {
            POPStatTile(value: "\(decision.comparableOptions.count)", label: "In comparison", icon: "square.stack")
            POPStatTile(value: "\(evaluatedFully)", label: "Fully evaluated", icon: "checkmark.square",
                        tint: evaluatedFully == scoreboard.scores.count && !scoreboard.scores.isEmpty ? POPColor.success : POPColor.graphite)
            POPStatTile(value: "\(disqualified)", label: "Disqualified", icon: "lock.slash",
                        tint: disqualified > 0 ? POPColor.danger : POPColor.graphite)
        }
    }

    // MARK: Filters

    private func filterStrip(_ decision: Decision) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                POPChip(title: "All", count: decision.options.count, isSelected: statusFilter == nil) {
                    statusFilter = nil
                }
                ForEach(OptionStatus.allCases) { status in
                    let count = decision.options.filter { $0.status == status }.count
                    if count > 0 {
                        POPChip(title: status.title, count: count, icon: status.icon, isSelected: statusFilter == status) {
                            statusFilter = statusFilter == status ? nil : status
                        }
                    }
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollClipDisabled()
    }

    // MARK: List

    private func list(_ decision: Decision) -> some View {
        let scoreboard = store.scoreboard(for: decision)
        let options = filtered(decision)

        return VStack(spacing: 12) {
            if options.isEmpty {
                POPEmptyState(icon: "line.3.horizontal.decrease.circle", title: "No options with this status",
                              message: "Clear the filter to see the rest.", compact: true)
                    .popCard(padding: 4)
            } else {
                ForEach(options) { option in
                    OptionCard(
                        option: option,
                        decision: decision,
                        score: scoreboard.score(for: option.id),
                        isLeader: scoreboard.leaderID == option.id,
                        evidenceCount: evidenceCount(for: option, in: decision),
                        onOpen: { route = .optionDetail(decisionID: decisionID, optionID: option.id) },
                        onEdit: {
                            editingOption = option
                            showEditor = true
                        },
                        onDuplicate: { store.send(.duplicateOption(decisionID: decisionID, optionID: option.id)) },
                        onStatusChange: { status in
                            store.send(.setOptionStatus(decisionID: decisionID, optionID: option.id, status: status))
                        },
                        onDelete: { pendingDelete = option }
                    )
                }
            }
        }
    }

    private func evidenceCount(for option: DecisionOption, in decision: Decision) -> Int {
        store.state.evidence(forDecision: decision.id)
            .filter { item in item.links.contains { $0.optionID == option.id } }
            .count
    }
}

// MARK: - Option card

struct OptionCard: View {
    @Environment(AppStore.self) private var store

    let option: DecisionOption
    let decision: Decision
    let score: OptionScore?
    let isLeader: Bool
    let evidenceCount: Int
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onStatusChange: (OptionStatus) -> Void
    let onDelete: () -> Void

    private var isDisqualified: Bool { score?.isDisqualified ?? false }
    private var failsMustHave: Bool { score?.failsMustHave ?? false }

    var body: some View {
        Button(action: {
            Haptics.tap()
            onOpen()
        }) {
            VStack(alignment: .leading, spacing: 11) {
                header
                if isDisqualified || failsMustHave { blockingNotice }
                metrics
                if let score, !score.isComplete { incompleteNotice(score) }
            }
            .padding(POPMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: POPMetrics.cardRadius, style: .continuous).fill(POPColor.surface))
            .overlay(
                RoundedRectangle(cornerRadius: POPMetrics.cardRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .opacity(option.status == .rejected ? 0.68 : 1)
        }
        .buttonStyle(POPPressStyle())
    }

    private var borderColor: Color {
        if isDisqualified || failsMustHave { return POPColor.danger.opacity(0.45) }
        if isLeader { return POPColor.brandYellow }
        return POPColor.hairline
    }

    private var borderWidth: CGFloat {
        (isDisqualified || failsMustHave || isLeader) ? 1.8 : 1
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            if let image = store.image(named: option.imageFileName) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(POPColor.hairline, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if isLeader {
                        POPBadge(text: "Current Leader", icon: "crown.fill",
                                 color: POPColor.graphite, soft: POPColor.brandYellow, compact: true)
                    }
                    POPBadge(text: option.status.title, icon: option.status.icon,
                             color: option.status.color, soft: option.status.softColor, compact: true)
                }
                Text(option.displayName)
                    .font(POPFont.cardTitle)
                    .foregroundStyle(POPColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !option.providerOrBrand.popIsBlank {
                    Text(option.providerOrBrand)
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Menu {
                    Button { onEdit() } label: { Label("Edit Option", systemImage: "pencil") }
                    Button { onDuplicate() } label: { Label("Duplicate as New Option", systemImage: "plus.square.on.square") }
                    Divider()
                    Menu("Change Status") {
                        ForEach(OptionStatus.allCases.filter { $0 != .selected }) { status in
                            Button { onStatusChange(status) } label: {
                                Label(status.title, systemImage: status.icon)
                            }
                        }
                    }
                    if option.status == .rejected {
                        Button { onStatusChange(.researching) } label: {
                            Label("Restore Option", systemImage: "arrow.uturn.backward")
                        }
                    } else {
                        Button { onStatusChange(.rejected) } label: {
                            Label("Reject Option", systemImage: "xmark.circle")
                        }
                    }
                    Divider()
                    Button(role: .destructive) { onDelete() } label: { Label("Delete Option", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(POPColor.inkTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Option actions"))

                if let score, score.evaluatedWeight > 0 {
                    Text(POPFormat.score(score.weightedScore))
                        .font(POPFont.numeric)
                        .foregroundStyle(isDisqualified || failsMustHave ? POPColor.inkTertiary : POPColor.ink)
                        .monospacedDigit()
                    Text("score")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(POPColor.inkTertiary)
                }
            }
        }
    }

    private var blockingNotice: some View {
        VStack(alignment: .leading, spacing: 5) {
            if isDisqualified, let score {
                ForEach(score.constraintResults.filter { $0.outcome == .violates }) { result in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "lock.slash.fill")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.top, 1.5)
                        Text(result.explanation)
                            .font(POPFont.caption)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(POPColor.danger)
                }
            }
            if failsMustHave, let score {
                ForEach(score.mustHaveResults.filter { $0.outcome == .failed }) { result in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.top, 1.5)
                        Text("Does Not Meet Must-Have Requirements — \(result.criterion.displayName): \(result.explanation)")
                            .font(POPFont.caption)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(POPColor.danger)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(POPColor.dangerSoft))
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let cost = option.estimatedCost {
                    metric(icon: "tag", text: POPFormat.money(cost, currencyCode: decision.currencyCode),
                           tint: budgetTint)
                } else {
                    metric(icon: "tag", text: "No price", tint: POPColor.brandOrange)
                }
                if let recurring = option.cost.recurringCost, recurring > 0 {
                    metric(icon: "arrow.clockwise",
                           text: "\(POPFormat.money(recurring, currencyCode: decision.currencyCode))\(option.cost.recurringPeriod.shortTitle)")
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                if let score {
                    metric(icon: "checkmark.square",
                           text: "\(decision.criteria.count - score.unevaluatedCriteriaIDs.count)/\(decision.criteria.count) evaluated")
                }
                metric(icon: "paperclip", text: "\(evidenceCount) evidence",
                       tint: evidenceCount == 0 ? POPColor.brandOrange : POPColor.inkSecondary)
                Spacer(minLength: 0)
            }

            if let score, score.evaluatedWeight > 0 {
                HStack(spacing: 10) {
                    POPMeter(value: score.weightedScore / 100,
                             tint: isDisqualified || failsMustHave ? POPColor.inkTertiary : POPColor.brandYellow)
                    ConfidenceMarker(level: confidenceLevel(score.confidenceIndex), showLabel: false)
                }
            }
        }
    }

    private var budgetTint: Color {
        switch CostEngine.budgetFit(for: option, decision: decision) {
        case .above: return POPColor.danger
        case .inside: return POPColor.success
        default: return POPColor.inkSecondary
        }
    }

    private func confidenceLevel(_ index: Double) -> ConfidenceLevel {
        if index >= 0.8 { return .high }
        if index >= 0.5 { return .medium }
        return .low
    }

    private func incompleteNotice(_ score: OptionScore) -> some View {
        POPInlineNote(
            text: score.incompleteMessage ?? "",
            icon: "exclamationmark.circle",
            tint: POPColor.brandOrange
        )
    }

    private func metric(icon: String, text: String, tint: Color = POPColor.inkSecondary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10.5, weight: .semibold))
            Text(text).font(POPFont.caption)
        }
        .foregroundStyle(tint)
    }
}
