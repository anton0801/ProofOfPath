//
//  RisksSection.swift
//  ProofOfPath
//
//  Risk Board. A High/High risk needs a plan or a written acceptance.
//

import SwiftUI

struct RisksSection: View {
    @EnvironmentObject private var store: AppStore
    let decisionID: UUID

    @State private var showEditor = false
    @State private var editingRisk: Risk?
    @State private var categoryFilter: RiskCategory?

    private var decision: Decision? { store.state.decision(id: decisionID) }

    private func filtered(_ decision: Decision) -> [Risk] {
        let sorted = decision.risks.sorted { lhs, rhs in
            if lhs.severityScore != rhs.severityScore { return lhs.severityScore > rhs.severityScore }
            return lhs.createdAt > rhs.createdAt
        }
        guard let categoryFilter else { return sorted }
        return sorted.filter { $0.category == categoryFilter }
    }

    var body: some View {
        if let decision {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                WorkspaceSectionIntro(
                    title: "Risk Board",
                    subtitle: "What could go wrong, how likely it is, and what you would do about it.",
                    icon: "exclamationmark.triangle"
                )

                if decision.risks.isEmpty {
                    POPEmptyState(
                        icon: "shield",
                        title: "No risks recorded",
                        message: "Naming a risk now costs nothing. Discovering it after you have committed costs a lot.",
                        actionTitle: "Add Risk",
                        action: {
                            editingRisk = nil
                            showEditor = true
                        }
                    )
                    .popCard(padding: 6)
                } else {
                    summary(decision)

                    let needsAttention = decision.risks.filter { $0.needsAttentionBeforeFinalizing }
                    if !needsAttention.isEmpty {
                        POPBanner(
                            kind: .danger,
                            message: "\(needsAttention.count) high-likelihood, high-impact \(needsAttention.count == 1 ? "risk needs" : "risks need") attention.",
                            detail: "Add a mitigation plan, or accept it explicitly with a written reason."
                        )
                    }

                    filterStrip(decision)

                    ForEach(filtered(decision)) { risk in
                        RiskRow(risk: risk, decision: decision) {
                            editingRisk = risk
                            showEditor = true
                        }
                    }

                    POPPrimaryButton(title: "Add Risk", icon: "plus") {
                        editingRisk = nil
                        showEditor = true
                    }
                    .popRequiresConnection()
                }
            }
            .sheet(isPresented: $showEditor, onDismiss: { editingRisk = nil }) {
                RiskEditorSheet(decisionID: decisionID, existing: editingRisk)
            }
        }
    }

    private func summary(_ decision: Decision) -> some View {
        HStack(spacing: 10) {
            POPStatTile(value: "\(decision.risks.filter { $0.category == .critical }.count)",
                        label: "Critical", icon: "flame", tint: POPColor.danger)
            POPStatTile(value: "\(decision.risks.filter { $0.category == .needsAction }.count)",
                        label: "Needs action", icon: "exclamationmark.circle", tint: POPColor.brandOrange)
            POPStatTile(value: "\(decision.risks.filter { $0.state == .reduced }.count)",
                        label: "Reduced", icon: "shield.lefthalf.filled", tint: POPColor.success)
        }
    }

    private func filterStrip(_ decision: Decision) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                POPChip(title: "All", count: decision.risks.count, isSelected: categoryFilter == nil) {
                    categoryFilter = nil
                }
                ForEach([RiskCategory.critical, .needsAction, .monitor], id: \.self) { category in
                    let count = decision.risks.filter { $0.category == category }.count
                    if count > 0 {
                        POPChip(title: category.title, count: count, icon: category.icon,
                                isSelected: categoryFilter == category) {
                            categoryFilter = categoryFilter == category ? nil : category
                        }
                    }
                }
            }
            .padding(.horizontal, 1)
        }
        .popScrollClipDisabled()
    }
}

// MARK: - Risk row

struct RiskRow: View {
    @EnvironmentObject private var store: AppStore
    let risk: Risk
    let decision: Decision
    let onTap: () -> Void

    @State private var showAcceptSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: {
                Haptics.tap()
                onTap()
            }) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: risk.category.icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(risk.category.color)
                            .frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(risk.category.softColor))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(risk.displayTitle)
                                .font(POPFont.calloutMedium)
                                .foregroundStyle(POPColor.ink)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 6) {
                                POPBadge(text: risk.category.title, color: risk.category.color,
                                         soft: risk.category.softColor, compact: true)
                                POPBadge(text: risk.state.title, icon: risk.state.icon,
                                         color: risk.state.color, soft: risk.state.softColor, compact: true)
                                if let option = decision.option(id: risk.optionID) {
                                    POPBadge(text: option.displayName.popTruncated(18), icon: "square.stack", compact: true)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(POPColor.inkTertiary)
                    }

                    HStack(spacing: 14) {
                        scaleIndicator(label: "Likelihood", value: risk.likelihood)
                        scaleIndicator(label: "Impact", value: risk.impact)
                        Spacer(minLength: 0)
                    }

                    if risk.hasMitigation {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(POPColor.success)
                                .padding(.top, 1.5)
                            Text(risk.mitigationPlan)
                                .font(POPFont.caption)
                                .foregroundStyle(POPColor.inkSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    } else if risk.category != .monitor && risk.state == .open {
                        POPInlineNote(text: "No mitigation plan yet.", icon: "shield.slash", tint: POPColor.brandOrange)
                    }

                    if !risk.acceptWithoutMitigationReason.popIsBlank {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(POPColor.inkSecondary)
                                .padding(.top, 1.5)
                            Text("Accepted: \(risk.acceptWithoutMitigationReason)")
                                .font(POPFont.caption)
                                .foregroundStyle(POPColor.inkSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(POPPressStyle())

            HStack(spacing: 7) {
                POPPillButton(title: "Accepted", icon: "hand.raised",
                              filled: risk.state == .accepted) {
                    if risk.isHighHigh && !risk.hasMitigation {
                        showAcceptSheet = true
                    } else {
                        store.send(.setRiskState(decisionID: decision.id, riskID: risk.id, state: .accepted, reason: risk.acceptWithoutMitigationReason))
                    }
                }
                POPPillButton(title: "Reduced", icon: "shield.lefthalf.filled",
                              tint: POPColor.success, filled: risk.state == .reduced) {
                    store.send(.setRiskState(decisionID: decision.id, riskID: risk.id, state: .reduced, reason: ""))
                }
                POPPillButton(title: "Occurred", icon: POPSymbol.riskOccurred,
                              tint: POPColor.danger, filled: risk.state == .occurred) {
                    store.send(.setRiskState(decisionID: decision.id, riskID: risk.id, state: .occurred, reason: ""))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(risk.needsAttentionBeforeFinalizing ? POPColor.danger.opacity(0.45) : POPColor.hairline,
                          lineWidth: risk.needsAttentionBeforeFinalizing ? 1.5 : 1))
        .sheet(isPresented: $showAcceptSheet) {
            AcceptRiskSheet(decisionID: decision.id, riskID: risk.id, riskTitle: risk.displayTitle)
        }
    }

    private func scaleIndicator(label: String, value: RiskScale) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(POPColor.inkTertiary)
            HStack(spacing: 2) {
                ForEach(1...3, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(level <= value.weight ? value.color : POPColor.hairline)
                        .frame(width: 8, height: 5)
                }
            }
            Text(value.title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(value.color)
        }
    }
}

// MARK: - Accept risk sheet

struct AcceptRiskSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var submission = POPSubmission()

    let decisionID: UUID
    let riskID: UUID
    let riskTitle: String

    @State private var reason = ""
    @State private var showValidation = false

    private var reasonError: String? {
        guard showValidation, reason.popIsBlank else { return nil }
        return "A written reason is required for a high-likelihood, high-impact risk."
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                    POPBanner(
                        kind: .danger,
                        message: "High likelihood and high impact.",
                        detail: "You can accept this without a mitigation plan, but only with an explicit reason on the record."
                    )

                    Text(riskTitle)
                        .font(POPFont.title)
                        .foregroundStyle(POPColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    POPTextEditor(
                        label: "Why accept it without a plan?",
                        text: $reason,
                        placeholder: "e.g. The worst case costs less than the mitigation would, and I can absorb it.",
                        isRequired: true,
                        errorText: reasonError,
                        characterLimit: 500,
                        minHeight: 110
                    )

                    POPPrimaryButton(title: "Accept Without Mitigation", icon: "hand.raised",
                                     isEnabled: store.canEdit, isLoading: submission.isRunning) {
                        guard !reason.popIsBlank else {
                            showValidation = true
                            Haptics.error()
                            return
                        }
                        submission.run(store, .setRiskState(decisionID: decisionID, riskID: riskID, state: .accepted, reason: reason)) { dismiss() }
                    }

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 8)
            }
            .background(POPColor.canvas.ignoresSafeArea())
            .navigationTitle("Accept Risk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(POPColor.inkSecondary)
                }
            }
        }
    }
}

// MARK: - Risk editor

struct RiskEditorSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    /// Fixed for the life of the sheet, so saving again after a lost response
    /// updates the same record instead of creating a second one.
    @State private var newRecordID = UUID()
    @StateObject private var submission = POPSubmission()

    let decisionID: UUID
    let existing: Risk?
    var presetOptionID: UUID?

    @State private var title = ""
    @State private var optionID: UUID?
    @State private var likelihood: RiskScale = .medium
    @State private var impact: RiskScale = .medium
    @State private var warningSigns = ""
    @State private var mitigationPlan = ""
    @State private var fallbackPlan = ""
    @State private var reviewDate: Date?
    @State private var acceptReason = ""
    @State private var showValidation = false
    @State private var pendingDelete = false
    @State private var loaded = false

    private var decision: Decision? { store.state.decision(id: decisionID) }

    private var titleError: String? {
        guard showValidation, title.popIsBlank else { return nil }
        return "Name the risk."
    }

    private var category: RiskCategory {
        let score = likelihood.weight * impact.weight
        switch score {
        case ...2: return .monitor
        case 3...4: return .needsAction
        default: return .critical
        }
    }

    private var isHighHigh: Bool { likelihood == .high && impact == .high }

    private var needsJustification: Bool {
        isHighHigh && mitigationPlan.popIsBlank && acceptReason.popIsBlank
    }

    private var isValid: Bool { !title.popIsBlank && !needsJustification }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                    POPTextField(
                        label: "Risk Title",
                        text: $title,
                        placeholder: "e.g. Delivery slips past the move-in date",
                        isRequired: true,
                        errorText: titleError,
                        characterLimit: 100
                    )

                    if let decision, !decision.options.isEmpty {
                        POPFieldShell(label: "Related Option", hint: "Leave empty if it applies to the whole decision.") {
                            Menu {
                                Button("Whole decision") { optionID = nil }
                                ForEach(decision.sortedOptions) { option in
                                    Button(action: { optionID = option.id }) {
                                        if optionID == option.id {
                                            Label(option.displayName, systemImage: "checkmark")
                                        } else {
                                            Text(option.displayName)
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(decision.option(id: optionID)?.displayName ?? "Whole decision")
                                        .font(POPFont.body)
                                        .foregroundStyle(POPColor.ink)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(POPColor.inkTertiary)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 46)
                                .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.surface))
                                .overlay(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                                    .strokeBorder(POPColor.hairline, lineWidth: 1))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        POPSectionHeader(title: "Likelihood and Impact", icon: POPSymbol.limits)
                        POPFieldShell(label: "Likelihood") {
                            POPInlineSegments(options: RiskScale.allCases, selection: $likelihood,
                                              titleFor: { $0.title }, tintFor: { $0.color })
                        }
                        POPFieldShell(label: "Impact") {
                            POPInlineSegments(options: RiskScale.allCases, selection: $impact,
                                              titleFor: { $0.title }, tintFor: { $0.color })
                        }
                        HStack(spacing: 9) {
                            Image(systemName: category.icon)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(category.color)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Calculated category")
                                    .font(POPFont.micro)
                                    .foregroundStyle(POPColor.inkTertiary)
                                Text(category.title)
                                    .font(POPFont.cardTitle)
                                    .foregroundStyle(POPColor.ink)
                            }
                            Spacer()
                            Text("\(likelihood.title) × \(impact.title)")
                                .font(POPFont.caption)
                                .foregroundStyle(POPColor.inkSecondary)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(category.softColor))
                    }

                    POPTextEditor(
                        label: "Warning Signs",
                        text: $warningSigns,
                        placeholder: "What would you notice first if this started happening?",
                        characterLimit: 400,
                        minHeight: 80
                    )

                    POPTextEditor(
                        label: "Mitigation Plan",
                        text: $mitigationPlan,
                        placeholder: "What reduces the chance or the damage?",
                        hint: isHighHigh ? "Required for a high/high risk unless you accept it explicitly below." : nil,
                        characterLimit: 500,
                        minHeight: 92
                    )

                    POPTextEditor(
                        label: "Fallback Plan",
                        text: $fallbackPlan,
                        placeholder: "What do you do if it happens anyway?",
                        characterLimit: 500,
                        minHeight: 84
                    )

                    POPDateField(
                        label: "Review Date",
                        date: $reviewDate,
                        hint: "Optional. A reminder is scheduled if reminders are on."
                    )

                    if isHighHigh && mitigationPlan.popIsBlank {
                        VStack(alignment: .leading, spacing: 10) {
                            POPBanner(
                                kind: .danger,
                                message: "High likelihood and high impact, with no mitigation plan.",
                                detail: "Either write a plan above, or accept it here with a reason. This cannot be left blank."
                            )
                            POPTextEditor(
                                label: "Accept Without Mitigation — reason",
                                text: $acceptReason,
                                placeholder: "Why is it acceptable to carry this risk unmitigated?",
                                isRequired: true,
                                errorText: showValidation && acceptReason.popIsBlank ? "A reason is required." : nil,
                                characterLimit: 500,
                                minHeight: 92
                            )
                        }
                    }

                    if existing != nil {
                        POPDestructiveButton(title: "Delete Risk") { pendingDelete = true }
                        .popRequiresConnection()
                    }

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 8)
            }
            .background(POPColor.canvas.ignoresSafeArea())
            .navigationTitle(existing == nil ? "Add Risk" : "Edit Risk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(POPColor.inkSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    POPToolbarSaveButton(title: "Save", isSaving: submission.isRunning, isHighlighted: isValid) { save() }
                }
            }
            .alert("Delete this risk?", isPresented: $pendingDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let existing {
                        submission.run(store, .deleteRisk(decisionID: decisionID, riskID: existing.id)) { dismiss() }
                    } else {
                        dismiss()
                    }
                }
            } message: {
                Text("This removes the risk and its plans from the record.")
            }
        }
        .onAppear(perform: hydrate)
    }

    private func hydrate() {
        guard !loaded else { return }
        loaded = true
        if let existing {
            title = existing.title
            optionID = existing.optionID
            likelihood = existing.likelihood
            impact = existing.impact
            warningSigns = existing.warningSigns
            mitigationPlan = existing.mitigationPlan
            fallbackPlan = existing.fallbackPlan
            reviewDate = existing.reviewDate
            acceptReason = existing.acceptWithoutMitigationReason
        } else {
            optionID = presetOptionID
        }
    }

    private func save() {
        guard isValid else {
            showValidation = true
            Haptics.error()
            return
        }
        var risk = existing ?? Risk(id: newRecordID)
        risk.title = title.popTrimmed
        risk.optionID = optionID
        risk.likelihood = likelihood
        risk.impact = impact
        risk.warningSigns = warningSigns.popTrimmed
        risk.mitigationPlan = mitigationPlan.popTrimmed
        risk.fallbackPlan = fallbackPlan.popTrimmed
        risk.reviewDate = reviewDate
        risk.acceptWithoutMitigationReason = acceptReason.popTrimmed
        if existing == nil, !acceptReason.popIsBlank { risk.state = .accepted }

        let intent: AppIntent = existing == nil
            ? .addRisk(decisionID: decisionID, risk: risk)
            : .updateRisk(decisionID: decisionID, risk: risk)
        submission.run(store, intent) { dismiss() }
    }
}
