//
//  BriefSection.swift
//  ProofOfPath
//
//  Decision Brief — the passport of the decision.
//

import SwiftUI

struct BriefSection: View {
    @EnvironmentObject private var store: AppStore
    let decisionID: UUID

    @State private var showEdit = false
    @State private var editingConstraint: HardConstraint?
    @State private var showConstraintSheet = false
    @State private var pendingConstraintDelete: HardConstraint?

    private var decision: Decision? { store.state.decision(id: decisionID) }

    var body: some View {
        if let decision {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                WorkspaceSectionIntro(
                    title: "Decision Brief",
                    subtitle: "What you are deciding, what a good result looks like, and the limits you set.",
                    icon: "doc.text"
                )

                goalCard(decision)
                limitsCard(decision)
                constraintsCard(decision)
                statusCard(decision)
            }
            .sheet(isPresented: $showEdit) {
                EditBriefSheet(decisionID: decisionID)
            }
            .sheet(isPresented: $showConstraintSheet, onDismiss: { editingConstraint = nil }) {
                ConstraintEditorSheet(
                    currencyCode: decision.currencyCode,
                    criteria: decision.sortedCriteria,
                    existing: editingConstraint
                ) { constraint in
                    await store.perform(editingConstraint == nil
                        ? .addConstraint(decisionID: decisionID, constraint: constraint)
                        : .updateConstraint(decisionID: decisionID, constraint: constraint))
                }
            }
            .alert(
                "Remove this constraint?",
                isPresented: Binding(get: { pendingConstraintDelete != nil }, set: { if !$0 { pendingConstraintDelete = nil } }),
                presenting: pendingConstraintDelete
            ) { constraint in
                Button("Cancel", role: .cancel) { pendingConstraintDelete = nil }
                Button("Remove", role: .destructive) {
                    store.send(.deleteConstraint(decisionID: decisionID, constraintID: constraint.id))
                    pendingConstraintDelete = nil
                }
            } message: { _ in
                Text("Options currently disqualified by it will be re-checked immediately.")
            }
        }
    }

    // MARK: Goal

    private func goalCard(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    POPBadge(
                        text: decision.categoryTitle,
                        icon: decision.category.icon,
                        color: POPColor.inkSecondary,
                        soft: POPColor.neutralSoft
                    )
                    Text(decision.displayTitle)
                        .font(POPFont.title)
                        .foregroundStyle(POPColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                POPIconButton(systemName: "square.and.pencil", accessibilityTitle: "Edit brief") {
                    showEdit = true
                }
            }

            POPDivider()

            POPKeyValueRow(label: "Desired Outcome", value: decision.desiredOutcome, icon: "flag", isMultiline: true)

            if !decision.whyItMatters.popIsBlank {
                POPDivider()
                POPKeyValueRow(label: "Why It Matters", value: decision.whyItMatters, icon: "questionmark.circle", isMultiline: true)
            }
            if !decision.peopleAffected.popIsBlank {
                POPDivider()
                POPKeyValueRow(label: "People Affected", value: decision.peopleAffected, icon: "person.2")
            }
            POPDivider()
            POPKeyValueRow(
                label: "Decision Owner",
                value: decision.owner.popIsBlank ? "Not set" : decision.owner,
                icon: "person.crop.circle"
            )
        }
        .popCard()
    }

    // MARK: Limits

    private func limitsCard(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Limits", icon: POPSymbol.limits)

            POPKeyValueRow(label: "Budget", value: budgetSummary(decision), icon: "banknote")
            POPDivider()
            POPKeyValueRow(
                label: "Deadline",
                value: decision.deadline.map { "\(POPFormat.date($0)) · \(POPFormat.relativeDeadline($0))" } ?? "Not set",
                valueColor: deadlineColor(decision),
                icon: "calendar"
            )
            if let preferred = decision.preferredCompletionDate {
                POPDivider()
                POPKeyValueRow(label: "Preferred Completion", value: POPFormat.date(preferred), icon: "calendar.badge.clock")
            }
            POPDivider()
            POPKeyValueRow(label: "Currency", value: decision.currencyCode, icon: "coloncurrencysign.circle")
        }
        .popCard()
    }

    private func budgetSummary(_ decision: Decision) -> String {
        switch (decision.budgetMin, decision.budgetMax) {
        case (nil, nil): return "Not set"
        case (let minValue?, nil): return "From \(POPFormat.money(minValue, currencyCode: decision.currencyCode))"
        case (nil, let maxValue?): return "Up to \(POPFormat.money(maxValue, currencyCode: decision.currencyCode))"
        case (let minValue?, let maxValue?):
            return "\(POPFormat.money(minValue, currencyCode: decision.currencyCode)) – \(POPFormat.money(maxValue, currencyCode: decision.currencyCode))"
        }
    }

    private func deadlineColor(_ decision: Decision) -> Color {
        guard let deadline = decision.deadline else { return POPColor.ink }
        if POPFormat.daysUntil(deadline) < 0 && decision.status != .finalized { return POPColor.danger }
        return POPColor.ink
    }

    // MARK: Hard constraints

    private func constraintsCard(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            POPSectionHeader(
                title: "Hard Constraints",
                subtitle: "Conditions an option must meet. Breaking one marks the option Disqualified.",
                icon: "lock"
            )

            if decision.hardConstraints.isEmpty {
                POPEmptyState(
                    icon: "lock.open",
                    title: "No hard constraints",
                    message: "Without them every option stays eligible, however far it drifts from your limits.",
                    compact: true
                )
            } else {
                VStack(spacing: 9) {
                    ForEach(decision.hardConstraints) { constraint in
                        ConstraintRow(
                            constraint: constraint,
                            decision: decision,
                            onEdit: {
                                editingConstraint = constraint
                                showConstraintSheet = true
                            },
                            onDelete: { pendingConstraintDelete = constraint }
                        )
                    }
                }

                let disqualified = ConstraintEngine.disqualifiedOptions(in: decision)
                if !disqualified.isEmpty {
                    POPBanner(
                        kind: .danger,
                        message: "\(disqualified.count) \(disqualified.count == 1 ? "option does" : "options do") not meet your hard constraints.",
                        detail: disqualified.map(\.displayName).joined(separator: ", ")
                    )
                }
            }

            POPSecondaryButton(title: "Add Constraint", icon: "plus") {
                editingConstraint = nil
                showConstraintSheet = true
            }
            .popRequiresConnection()
        }
        .popCard()
    }

    // MARK: Status

    private func statusCard(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            POPSectionHeader(title: "Current Status", icon: "flag.checkered")

            HStack(spacing: 10) {
                POPBadge(
                    text: decision.status.title,
                    icon: decision.status.icon,
                    color: decision.status.color,
                    soft: decision.status.softColor
                )
                Spacer()
                Text("Updated \(POPFormat.relativeTimestamp(decision.updatedAt))")
                    .font(POPFont.caption)
                    .foregroundStyle(POPColor.inkTertiary)
            }

            let progress = store.progress(for: decision)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Completion")
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                    Spacer()
                    Text("\(progress.completedCount) of \(progress.steps.count) steps")
                        .font(POPFont.captionMedium)
                        .foregroundStyle(POPColor.ink)
                }
                POPMeter(value: progress.fraction, tint: progress.fraction >= 1 ? POPColor.success : POPColor.brandOrange)
            }

            POPDivider()

            HStack(spacing: 10) {
                POPKeyValueRow(label: "Created", value: POPFormat.date(decision.createdAt), icon: "calendar.badge.plus")
            }

            if decision.status == .finalized, let final = decision.finalDecision, final.isDraft == false {
                POPDivider()
                POPKeyValueRow(
                    label: "Finalized",
                    value: final.finalizedAt.map { POPFormat.date($0) } ?? "—",
                    valueColor: POPColor.success,
                    icon: "checkmark.seal.fill"
                )
                POPKeyValueRow(label: "Version", value: "v\(final.version)", icon: "number")
            }
        }
        .popCard()
    }
}

// MARK: - Constraint row

struct ConstraintRow: View {
    let constraint: HardConstraint
    let decision: Decision
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    private var affectedOptions: [(DecisionOption, ConstraintResult)] {
        decision.comparableOptions.map { ($0, ConstraintEngine.evaluate(constraint, option: $0, decision: decision)) }
    }

    private var violationCount: Int {
        affectedOptions.filter { $0.1.outcome == .violates }.count
    }

    private var uncheckedCount: Int {
        affectedOptions.filter { $0.1.outcome == .unknown }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: constraint.check.isAutomatic ? "lock.fill" : "hand.point.up.left.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(POPColor.brandOrange)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(POPColor.warningSoft))

                VStack(alignment: .leading, spacing: 3) {
                    Text(constraint.title.popIsBlank ? "Untitled constraint" : constraint.title)
                        .font(POPFont.calloutMedium)
                        .foregroundStyle(POPColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ConstraintEngine.describe(constraint, in: decision))
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !constraint.details.popIsBlank {
                        Text(constraint.details)
                            .font(POPFont.caption)
                            .foregroundStyle(POPColor.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)

                if onEdit != nil || onDelete != nil {
                    Menu {
                        if let onEdit {
                            Button { onEdit() } label: { Label("Edit Constraint", systemImage: "pencil") }
                        }
                        if let onDelete {
                            Button(role: .destructive) { onDelete() } label: { Label("Remove Constraint", systemImage: "trash") }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(POPColor.inkTertiary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("Constraint actions"))
                }
            }

            if ConstraintEngine.isOrphaned(constraint, in: decision) {
                POPInlineNote(
                    text: "The linked criterion was removed. Edit this constraint so it can be checked again.",
                    icon: "exclamationmark.triangle.fill",
                    tint: POPColor.danger
                )
            } else if !decision.comparableOptions.isEmpty {
                HStack(spacing: 7) {
                    if violationCount > 0 {
                        POPBadge(text: "\(violationCount) violating", icon: "xmark.circle.fill",
                                 color: POPColor.danger, soft: POPColor.dangerSoft, compact: true)
                    }
                    if uncheckedCount > 0 {
                        POPBadge(text: "\(uncheckedCount) not checked", icon: "questionmark.circle",
                                 color: POPColor.inkSecondary, soft: POPColor.neutralSoft, compact: true)
                    }
                    if violationCount == 0 && uncheckedCount == 0 {
                        POPBadge(text: "All options meet it", icon: "checkmark.circle.fill",
                                 color: POPColor.success, soft: POPColor.successSoft, compact: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(POPColor.hairline, lineWidth: 1))
    }
}

// MARK: - Edit brief

struct EditBriefSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var submission = POPSubmission()

    let decisionID: UUID

    @State private var title = ""
    @State private var category: DecisionCategory = .purchase
    @State private var customCategory = ""
    @State private var desiredOutcome = ""
    @State private var whyItMatters = ""
    @State private var peopleAffected = ""
    @State private var owner = ""
    @State private var budgetMinText = ""
    @State private var budgetMaxText = ""
    @State private var currencyCode = "USD"
    @State private var deadline: Date?
    @State private var preferredDate: Date?
    @State private var showValidation = false
    @State private var loaded = false

    private var budgetMin: Double? { POPFormat.parseNumber(budgetMinText) }
    private var budgetMax: Double? { POPFormat.parseNumber(budgetMaxText) }

    private var titleError: String? {
        guard showValidation, title.popIsBlank else { return nil }
        return "A decision title is required."
    }

    private var outcomeError: String? {
        guard showValidation, desiredOutcome.popIsBlank else { return nil }
        return "Describe what a good result looks like."
    }

    private var customCategoryError: String? {
        guard showValidation, category == .custom, customCategory.popIsBlank else { return nil }
        return "Name your custom category."
    }

    private var budgetError: String? {
        if !budgetMinText.popIsBlank && budgetMin == nil { return "Minimum budget is not a number." }
        if !budgetMaxText.popIsBlank && budgetMax == nil { return "Maximum budget is not a number." }
        if let value = budgetMin, value < 0 { return "Budget cannot be negative." }
        if let value = budgetMax, value < 0 { return "Budget cannot be negative." }
        if let minValue = budgetMin, let maxValue = budgetMax, minValue > maxValue {
            return "The minimum budget cannot be higher than the maximum."
        }
        return nil
    }

    private var preferredDateError: String? {
        guard let preferred = preferredDate, let deadline else { return nil }
        return preferred > deadline ? "The preferred completion date is after the deadline." : nil
    }

    private var isValid: Bool {
        !title.popIsBlank && !desiredOutcome.popIsBlank && budgetError == nil
            && preferredDateError == nil && (category != .custom || !customCategory.popIsBlank)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                    POPTextField(label: "Decision Title", text: $title, isRequired: true,
                                 errorText: titleError, characterLimit: 90)

                    POPSegmentedPicker(
                        label: "Decision Category",
                        options: DecisionCategory.allCases,
                        selection: $category,
                        titleFor: { $0.title },
                        iconFor: { $0.icon },
                        columns: 2
                    )
                    if category == .custom {
                        POPTextField(label: "Custom Category Name", text: $customCategory,
                                     isRequired: true, errorText: customCategoryError, characterLimit: 40)
                    }

                    POPTextEditor(label: "Desired Outcome", text: $desiredOutcome, isRequired: true,
                                  errorText: outcomeError, characterLimit: 600, minHeight: 100)
                    POPTextEditor(label: "Why It Matters", text: $whyItMatters, characterLimit: 600, minHeight: 84)
                    POPTextField(label: "Who Is Affected?", text: $peopleAffected, characterLimit: 140)
                    POPTextField(label: "Decision Owner", text: $owner,
                                 placeholder: "Who makes the final call?", characterLimit: 60)

                    VStack(alignment: .leading, spacing: 10) {
                        POPSectionHeader(title: "Budget Range", icon: "banknote")
                        HStack(alignment: .top, spacing: 10) {
                            POPNumberField(label: "Minimum", text: $budgetMinText,
                                           prefix: POPFormat.currencySymbol(for: currencyCode))
                            POPNumberField(label: "Maximum", text: $budgetMaxText,
                                           prefix: POPFormat.currencySymbol(for: currencyCode))
                        }
                        if let budgetError {
                            POPInlineNote(text: budgetError, icon: "exclamationmark.circle.fill", tint: POPColor.danger)
                        }
                        POPMenuPicker(
                            label: "Currency",
                            options: AppSettings.supportedCurrencies.map { CurrencyOption(code: $0) },
                            selection: Binding(
                                get: { CurrencyOption(code: currencyCode) },
                                set: { currencyCode = $0.code }
                            ),
                            titleFor: { "\($0.code) · \(POPFormat.currencySymbol(for: $0.code))" }
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        POPSectionHeader(title: "Timing", icon: "calendar")
                        POPDateField(label: "Decision Deadline", date: $deadline)
                        POPDateField(label: "Preferred Completion Date", date: $preferredDate,
                                     errorText: preferredDateError)
                    }

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 8)
            }
            .background(POPColor.canvas.ignoresSafeArea())
            .navigationTitle("Edit Brief")
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
        }
        .onAppear(perform: hydrate)
    }

    private func hydrate() {
        guard !loaded, let decision = store.state.decision(id: decisionID) else { return }
        loaded = true
        title = decision.title
        category = decision.category
        customCategory = decision.customCategoryName
        desiredOutcome = decision.desiredOutcome
        whyItMatters = decision.whyItMatters
        peopleAffected = decision.peopleAffected
        owner = decision.owner
        budgetMinText = POPFormat.editableNumber(decision.budgetMin)
        budgetMaxText = POPFormat.editableNumber(decision.budgetMax)
        currencyCode = decision.currencyCode
        deadline = decision.deadline
        preferredDate = decision.preferredCompletionDate
    }

    private func save() {
        guard isValid else {
            showValidation = true
            Haptics.error()
            return
        }
        guard let decision = store.state.decision(id: decisionID) else { return }
        var brief = DecisionBriefEdit(decision: decision)
        brief.title = title
        brief.category = category
        brief.customCategoryName = customCategory
        brief.desiredOutcome = desiredOutcome
        brief.whyItMatters = whyItMatters
        brief.peopleAffected = peopleAffected
        brief.owner = owner
        brief.budgetMin = budgetMin
        brief.budgetMax = budgetMax
        brief.currencyCode = currencyCode
        brief.deadline = deadline
        brief.preferredCompletionDate = preferredDate
        submission.run(store, .updateDecisionBrief(decisionID: decisionID, brief: brief)) { dismiss() }
    }
}
