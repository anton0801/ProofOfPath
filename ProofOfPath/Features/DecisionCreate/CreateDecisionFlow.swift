//
//  CreateDecisionFlow.swift
//  ProofOfPath
//
//  Four-step wizard. Title and Desired Outcome are required, the budget range
//  must be coherent, and a past deadline needs an explicit confirmation.
//

import SwiftUI

// MARK: - Wizard state

final class CreateDecisionModel: ObservableObject {
    /// Chosen once, so submitting again after a lost response cannot create a twin.
    let decisionID = UUID()
    @Published var step: Int = 0

    // Step 1
    @Published var templateID: String?
    @Published var category: DecisionCategory = .purchase
    @Published var customCategoryName: String = ""
    @Published var title: String = ""

    // Step 2
    @Published var desiredOutcome: String = ""
    @Published var whyItMatters: String = ""
    @Published var peopleAffected: String = ""

    // Step 3
    @Published var budgetMinText: String = ""
    @Published var budgetMaxText: String = ""
    @Published var currencyCode: String = "USD"
    @Published var deadline: Date?
    @Published var preferredCompletionDate: Date?
    @Published var hardConstraints: [HardConstraint] = []
    @Published var acknowledgedOverdue: Bool = false

    // Step 4
    @Published var reviewedTemplateCriteria: [TemplateCriterion] = []
    @Published var showValidation: Bool = false

    let totalSteps = 4

    var budgetMin: Double? { POPFormat.parseNumber(budgetMinText) }
    var budgetMax: Double? { POPFormat.parseNumber(budgetMaxText) }

    var template: DecisionTemplate? { DecisionTemplateLibrary.template(id: templateID) }

    // MARK: Validation

    var titleError: String? {
        guard showValidation else { return nil }
        if title.popIsBlank { return "A decision title is required." }
        if title.popTrimmed.count < 3 { return "Give the decision a recognisable name." }
        return nil
    }

    var customCategoryError: String? {
        guard showValidation, category == .custom else { return nil }
        return customCategoryName.popIsBlank ? "Name your custom category." : nil
    }

    var desiredOutcomeError: String? {
        guard showValidation else { return nil }
        return desiredOutcome.popIsBlank ? "Describe what a good result looks like." : nil
    }

    var budgetError: String? {
        if !budgetMinText.popIsBlank && budgetMin == nil { return "Minimum budget is not a number." }
        if !budgetMaxText.popIsBlank && budgetMax == nil { return "Maximum budget is not a number." }
        if let minValue = budgetMin, minValue < 0 { return "Budget cannot be negative." }
        if let maxValue = budgetMax, maxValue < 0 { return "Budget cannot be negative." }
        if let minValue = budgetMin, let maxValue = budgetMax, minValue > maxValue {
            return "The minimum budget cannot be higher than the maximum."
        }
        return nil
    }

    var isDeadlineInPast: Bool {
        guard let deadline else { return false }
        return POPFormat.daysUntil(deadline) < 0
    }

    var deadlineError: String? {
        guard isDeadlineInPast, !acknowledgedOverdue else { return nil }
        return "This deadline has already passed. Confirm below to create it as overdue."
    }

    var preferredDateError: String? {
        guard let preferred = preferredCompletionDate, let deadline else { return nil }
        return preferred > deadline ? "The preferred completion date is after the deadline." : nil
    }

    func canLeaveStep(_ index: Int) -> Bool {
        switch index {
        case 0: return !title.popIsBlank && title.popTrimmed.count >= 3 && (category != .custom || !customCategoryName.popIsBlank)
        case 1: return !desiredOutcome.popIsBlank
        case 2: return budgetError == nil && deadlineError == nil && preferredDateError == nil
        default: return true
        }
    }

    var canSubmit: Bool {
        (0..<3).allSatisfy { canLeaveStep($0) }
    }

    func makeDraft(saveAsDraft: Bool, defaultCurrency: String, ownerName: String) -> DecisionDraft {
        var draft = DecisionDraft()
        draft.id = decisionID
        draft.title = title
        draft.category = category
        draft.customCategoryName = customCategoryName
        draft.desiredOutcome = desiredOutcome
        draft.whyItMatters = whyItMatters
        draft.peopleAffected = peopleAffected
        draft.budgetMin = budgetMin
        draft.budgetMax = budgetMax
        draft.currencyCode = currencyCode.isEmpty ? defaultCurrency : currencyCode
        draft.deadline = deadline
        draft.preferredCompletionDate = preferredCompletionDate
        draft.hardConstraints = hardConstraints
        draft.owner = ownerName
        draft.templateID = templateID
        draft.templateCriteria = reviewedTemplateCriteria
        draft.saveAsDraft = saveAsDraft
        return draft
    }
}

// MARK: - Flow

struct CreateDecisionFlow: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var preselectedTemplateID: String?
    var onFinished: (() -> Void)?
    var onCreated: ((UUID) -> Void)?

    @StateObject private var model = CreateDecisionModel()
    @State private var showDiscardAlert = false
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CreateStepBar(step: model.step, total: model.totalSteps)
                    .padding(.horizontal, POPMetrics.gutter)
                    .padding(.top, 6)
                    .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                        switch model.step {
                        case 0: StepDecisionType(model: model)
                        case 1: StepDesiredOutcome(model: model)
                        case 2: StepLimits(model: model)
                        default: StepReview(model: model)
                        }
                        Color.clear.frame(height: 12)
                    }
                    .padding(.horizontal, POPMetrics.gutter)
                    .padding(.bottom, 8)
                }

                footer
            }
            .background(POPColor.canvas.ignoresSafeArea())
            .navigationTitle("Create Decision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if hasAnyInput { showDiscardAlert = true } else { dismiss() }
                    }
                    .foregroundStyle(POPColor.inkSecondary)
                    .accessibilityIdentifier("wizard.cancel")
                }
            }
            .alert("Discard this decision?", isPresented: $showDiscardAlert) {
                Button("Keep editing", role: .cancel) {}
                Button("Discard", role: .destructive) { dismiss() }
            } message: {
                Text("Everything you typed will be lost.")
            }
        }
        .onAppear {
            if model.currencyCode == "USD" { model.currencyCode = store.state.settings.defaultCurrency }
            if let preselectedTemplateID, model.templateID == nil {
                applyTemplate(id: preselectedTemplateID)
            }
        }
    }

    private var hasAnyInput: Bool {
        !model.title.popIsBlank || !model.desiredOutcome.popIsBlank || !model.whyItMatters.popIsBlank
            || !model.peopleAffected.popIsBlank || !model.budgetMinText.popIsBlank
            || !model.budgetMaxText.popIsBlank || model.deadline != nil || !model.hardConstraints.isEmpty
    }

    private func applyTemplate(id: String) {
        guard let template = DecisionTemplateLibrary.template(id: id) else { return }
        model.templateID = template.id
        model.reviewedTemplateCriteria = template.criteria
        if template.category != .custom { model.category = template.category }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 8) {
            if model.step == model.totalSteps - 1 {
                POPPrimaryButton(title: "Create Workspace", icon: "checkmark", isEnabled: model.canSubmit && store.canEdit, isLoading: isSubmitting) {
                    submit(asDraft: false)
                }
                .accessibilityIdentifier("wizard.createWorkspace")
                HStack(spacing: 10) {
                    POPSecondaryButton(title: "Back", icon: "chevron.left") {
                        withAnimation(.easeInOut(duration: 0.2)) { model.step -= 1 }
                    }
                    POPSecondaryButton(title: "Save as Draft", icon: "tray.and.arrow.down", isEnabled: model.canSubmit && store.canEdit && !isSubmitting) {
                        submit(asDraft: true)
                    }
                    .accessibilityIdentifier("wizard.saveDraft")
                }
            } else {
                HStack(spacing: 10) {
                    if model.step > 0 {
                        POPSecondaryButton(title: "Back", icon: "chevron.left") {
                            model.showValidation = false
                            withAnimation(.easeInOut(duration: 0.2)) { model.step -= 1 }
                        }
                    }
                    POPPrimaryButton(title: "Continue") {
                        if model.canLeaveStep(model.step) {
                            model.showValidation = false
                            withAnimation(.easeInOut(duration: 0.2)) { model.step += 1 }
                        } else {
                            model.showValidation = true
                            Haptics.error()
                        }
                    }
                    .accessibilityIdentifier("wizard.continue")
                }
            }
        }
        .padding(.horizontal, POPMetrics.gutter)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            POPColor.surface
                .overlay(alignment: .top) { Rectangle().fill(POPColor.hairline).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func submit(asDraft: Bool) {
        guard model.canSubmit, !isSubmitting else {
            model.showValidation = true
            Haptics.error()
            return
        }
        isSubmitting = true
        let draft = model.makeDraft(
            saveAsDraft: asDraft,
            defaultCurrency: store.state.settings.defaultCurrency,
            ownerName: store.state.settings.ownerName
        )
        Task {
            let created = await store.perform(.createDecision(draft))
            isSubmitting = false
            // Nothing was stored: keep the wizard open with everything entered.
            guard created else { return }
            let createdID = store.state.decisions.last?.id
            Haptics.success()
            onFinished?()
            if let createdID { onCreated?(createdID) }
            dismiss()
        }
    }
}

// MARK: - Step bar

struct CreateStepBar: View {
    let step: Int
    let total: Int

    private let titles = ["Decision Type", "Desired Outcome", "Limits", "Review"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? POPColor.brandOrange : POPColor.hairline)
                        .frame(height: 4)
                }
            }
            HStack {
                Text("Step \(step + 1) of \(total)")
                    .font(POPFont.micro)
                    .foregroundStyle(POPColor.inkTertiary)
                Spacer()
                Text(titles[popSafe: step] ?? "")
                    .font(POPFont.captionMedium)
                    .foregroundStyle(POPColor.ink)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: step)
    }
}

private extension Array where Element == String {
    subscript(popSafe index: Int) -> String? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Step 1

struct StepDecisionType: View {
    @ObservedObject var model: CreateDecisionModel

    var body: some View {
        VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What Are You Deciding?")
                    .font(POPFont.display(25))
                    .foregroundStyle(POPColor.ink)
                Text("Name the choice in front of you and pick the closest category.")
                    .font(POPFont.callout)
                    .foregroundStyle(POPColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            POPTextField(
                label: "Decision Title",
                text: $model.title,
                placeholder: "e.g. Replace the kitchen fridge",
                isRequired: true,
                hint: "You will see this name everywhere in the app.",
                errorText: model.titleError,
                characterLimit: 90
            )
            .accessibilityIdentifier("wizard.titleField")

            VStack(alignment: .leading, spacing: 10) {
                POPSegmentedPicker(
                    label: "Decision Category",
                    options: DecisionCategory.allCases,
                    selection: $model.category,
                    titleFor: { $0.title },
                    iconFor: { $0.icon },
                    columns: 2
                )
                if model.category == .custom {
                    POPTextField(
                        label: "Custom Category Name",
                        text: $model.customCategoryName,
                        placeholder: "e.g. Studio equipment",
                        isRequired: true,
                        errorText: model.customCategoryError,
                        characterLimit: 40
                    )
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                POPSectionHeader(
                    title: "Starting Structure",
                    subtitle: "Optional. Adds suggested criteria you must review — never options or ratings.",
                    icon: "square.grid.2x2"
                )
                VStack(spacing: 8) {
                    ForEach(DecisionTemplateLibrary.all) { template in
                        TemplateChoiceRow(
                            template: template,
                            isSelected: model.templateID == template.id || (template.id == "blank" && model.templateID == nil)
                        ) {
                            if template.id == "blank" {
                                model.templateID = nil
                                model.reviewedTemplateCriteria = []
                            } else {
                                model.templateID = template.id
                                model.reviewedTemplateCriteria = template.criteria
                                if template.category != .custom { model.category = template.category }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct TemplateChoiceRow: View {
    let template: DecisionTemplate
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.selection()
            action()
        }) {
            HStack(spacing: 11) {
                Image(systemName: template.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? POPColor.graphite : POPColor.brandOrange)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSelected ? POPColor.brandYellow : POPColor.warningSoft))

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title)
                        .font(POPFont.cardTitle)
                        .foregroundStyle(POPColor.ink)
                    Text(template.criteria.isEmpty ? template.subtitle : "\(template.criteria.count) suggested criteria · \(template.subtitle)")
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? POPColor.brandOrange : POPColor.hairline)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(POPColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(isSelected ? POPColor.brandOrange.opacity(0.5) : POPColor.hairline,
                              lineWidth: isSelected ? 1.6 : 1))
        }
        .buttonStyle(POPPressStyle())
    }
}

// MARK: - Step 2

struct StepDesiredOutcome: View {
    @ObservedObject var model: CreateDecisionModel

    var body: some View {
        VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Desired Outcome")
                    .font(POPFont.display(25))
                    .foregroundStyle(POPColor.ink)
                Text("Write this before you look at any option. It is what you will measure against later.")
                    .font(POPFont.callout)
                    .foregroundStyle(POPColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            POPTextEditor(
                label: "Desired Outcome",
                text: $model.desiredOutcome,
                placeholder: "What does a good result actually look like six months from now?",
                isRequired: true,
                errorText: model.desiredOutcomeError,
                characterLimit: 600,
                minHeight: 110
            )
            .accessibilityIdentifier("wizard.outcomeEditor")

            POPTextEditor(
                label: "Why It Matters",
                text: $model.whyItMatters,
                placeholder: "What happens if you get this wrong? What are you really solving?",
                hint: "Optional, but it makes the outcome review far more useful.",
                characterLimit: 600,
                minHeight: 92
            )

            POPTextField(
                label: "Who Is Affected?",
                text: $model.peopleAffected,
                placeholder: "e.g. Me and my partner, the whole team",
                hint: "People who live with the consequences of this choice.",
                characterLimit: 140
            )
        }
    }
}

// MARK: - Step 3

struct StepLimits: View {
    @ObservedObject var model: CreateDecisionModel
    @State private var showConstraintSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Limits")
                    .font(POPFont.display(25))
                    .foregroundStyle(POPColor.ink)
                Text("Boundaries you are not willing to cross. All of this stays editable later.")
                    .font(POPFont.callout)
                    .foregroundStyle(POPColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                POPSectionHeader(title: "Budget Range", icon: "banknote")
                HStack(alignment: .top, spacing: 10) {
                    POPNumberField(
                        label: "Minimum",
                        text: $model.budgetMinText,
                        placeholder: "0",
                        prefix: POPFormat.currencySymbol(for: model.currencyCode)
                    )
                    .accessibilityIdentifier("wizard.budgetMin")
                    POPNumberField(
                        label: "Maximum",
                        text: $model.budgetMaxText,
                        placeholder: "0",
                        prefix: POPFormat.currencySymbol(for: model.currencyCode)
                    )
                    .accessibilityIdentifier("wizard.budgetMax")
                }
                if let error = model.budgetError {
                    POPInlineNote(text: error, icon: "exclamationmark.circle.fill", tint: POPColor.danger)
                }
                POPMenuPicker(
                    label: "Currency",
                    options: AppSettings.supportedCurrencies.map { CurrencyOption(code: $0) },
                    selection: Binding(
                        get: { CurrencyOption(code: model.currencyCode) },
                        set: { model.currencyCode = $0.code }
                    ),
                    titleFor: { "\($0.code) · \(POPFormat.currencySymbol(for: $0.code))" }
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                POPSectionHeader(title: "Timing", icon: "calendar")
                POPDateField(
                    label: "Decision Deadline",
                    date: $model.deadline,
                    hint: "The date by which the choice must be made.",
                    errorText: model.deadlineError
                )
                if model.isDeadlineInPast {
                    Toggle(isOn: $model.acknowledgedOverdue) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create as Overdue")
                                .font(POPFont.bodyMedium)
                                .foregroundStyle(POPColor.ink)
                            Text("I know this deadline has already passed.")
                                .font(POPFont.caption)
                                .foregroundStyle(POPColor.inkSecondary)
                        }
                    }
                    .tint(POPColor.brandOrange)
                    .padding(11)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.warningSoft))
                }
                POPDateField(
                    label: "Preferred Completion Date",
                    date: $model.preferredCompletionDate,
                    hint: "When you would ideally have it done, not the hard limit.",
                    errorText: model.preferredDateError
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                POPSectionHeader(
                    title: "Hard Constraints",
                    subtitle: "Conditions an option must meet. Breaking one disqualifies the option.",
                    icon: "lock"
                )
                if model.hardConstraints.isEmpty {
                    POPInlineNote(text: "No hard constraints yet. You can also add them later from the Brief.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(model.hardConstraints) { constraint in
                            ConstraintSummaryRow(
                                constraint: constraint,
                                description: constraintDescription(constraint)
                            ) {
                                model.hardConstraints.removeAll { $0.id == constraint.id }
                            }
                        }
                    }
                }
                POPSecondaryButton(title: "Add Constraint", icon: "plus") {
                    showConstraintSheet = true
                }
            }
        }
        .sheet(isPresented: $showConstraintSheet) {
            ConstraintEditorSheet(
                currencyCode: model.currencyCode,
                criteria: [],
                existing: nil
            ) { constraint in
                model.hardConstraints.append(constraint)
                return true
            }
        }
    }

    private func constraintDescription(_ constraint: HardConstraint) -> String {
        switch constraint.check {
        case .maximumCost(let value):
            return "Cost must not exceed \(POPFormat.money(value, currencyCode: model.currencyCode))"
        case .minimumCost(let value):
            return "Cost must be at least \(POPFormat.money(value, currencyCode: model.currencyCode))"
        case .manual:
            return "Marked manually on each option"
        default:
            return constraint.check.kindTitle
        }
    }
}

struct CurrencyOption: Identifiable, Hashable {
    let code: String
    var id: String { code }
}

struct ConstraintSummaryRow: View {
    let constraint: HardConstraint
    let description: String
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(POPColor.brandOrange)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(POPColor.warningSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text(constraint.title.popIsBlank ? "Untitled constraint" : constraint.title)
                    .font(POPFont.calloutMedium)
                    .foregroundStyle(POPColor.ink)
                Text(description)
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
            if let onDelete {
                Button(action: {
                    Haptics.warning()
                    onDelete()
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(POPColor.danger)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Delete constraint"))
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(POPColor.hairline, lineWidth: 1))
    }
}

// MARK: - Step 4

struct StepReview: View {
    @ObservedObject var model: CreateDecisionModel

    var body: some View {
        VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Review Decision Brief")
                    .font(POPFont.display(25))
                    .foregroundStyle(POPColor.ink)
                Text("Check it once. Everything here stays editable inside the workspace.")
                    .font(POPFont.callout)
                    .foregroundStyle(POPColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 11) {
                POPKeyValueRow(label: "Decision", value: model.title, icon: "target")
                POPDivider()
                POPKeyValueRow(
                    label: "Category",
                    value: model.category == .custom ? model.customCategoryName : model.category.title,
                    icon: model.category.icon
                )
                POPDivider()
                POPKeyValueRow(label: "Desired Outcome", value: model.desiredOutcome, icon: "flag", isMultiline: true)
                if !model.whyItMatters.popIsBlank {
                    POPDivider()
                    POPKeyValueRow(label: "Why It Matters", value: model.whyItMatters, icon: "questionmark.circle", isMultiline: true)
                }
                if !model.peopleAffected.popIsBlank {
                    POPDivider()
                    POPKeyValueRow(label: "People Affected", value: model.peopleAffected, icon: "person.2")
                }
            }
            .popCard()

            VStack(alignment: .leading, spacing: 11) {
                POPKeyValueRow(label: "Budget", value: budgetSummary, icon: "banknote")
                POPDivider()
                POPKeyValueRow(
                    label: "Deadline",
                    value: model.deadline.map { "\(POPFormat.date($0)) · \(POPFormat.relativeDeadline($0))" } ?? "Not set",
                    valueColor: model.isDeadlineInPast ? POPColor.danger : POPColor.ink,
                    icon: "calendar"
                )
                if let preferred = model.preferredCompletionDate {
                    POPDivider()
                    POPKeyValueRow(label: "Preferred Completion", value: POPFormat.date(preferred), icon: "calendar.badge.clock")
                }
                POPDivider()
                POPKeyValueRow(
                    label: "Hard Constraints",
                    value: model.hardConstraints.isEmpty ? "None" : "\(model.hardConstraints.count) set",
                    icon: "lock"
                )
            }
            .popCard()

            if let template = model.template, !model.reviewedTemplateCriteria.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    POPSectionHeader(
                        title: "Review Suggested Criteria",
                        subtitle: "From “\(template.title)”. Remove anything that does not apply to you.",
                        icon: "list.bullet.indent"
                    )

                    let total = model.reviewedTemplateCriteria.reduce(0) { $0 + $1.suggestedWeight }
                    POPBanner(
                        kind: abs(total - 100) < 0.01 ? .success : .warning,
                        message: abs(total - 100) < 0.01
                            ? "Suggested weights add up to 100%."
                            : "Suggested weights now add up to \(POPFormat.percent(total)).",
                        detail: abs(total - 100) < 0.01
                            ? nil
                            : "You will need to rebalance them in the Criteria Workshop before comparing."
                    )

                    VStack(spacing: 8) {
                        ForEach(Array(model.reviewedTemplateCriteria.enumerated()), id: \.offset) { index, criterion in
                            TemplateCriterionRow(criterion: criterion) {
                                model.reviewedTemplateCriteria.remove(at: index)
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        POPTextButton(title: "Remove all", icon: "trash", tint: POPColor.danger) {
                            model.reviewedTemplateCriteria = []
                        }
                        Spacer()
                        if model.reviewedTemplateCriteria.count < template.criteria.count {
                            POPTextButton(title: "Restore all", icon: "arrow.uturn.backward") {
                                model.reviewedTemplateCriteria = template.criteria
                            }
                        }
                    }
                }
            } else {
                POPBanner(
                    kind: .neutral,
                    message: "You will start with no criteria.",
                    detail: "Add them in the Criteria Workshop — the app never invents criteria for you."
                )
            }

            POPInlineNote(
                text: "Saving as a draft keeps the decision out of your active list until you are ready.",
                icon: "tray.and.arrow.down"
            )
        }
    }

    private var budgetSummary: String {
        let currency = model.currencyCode
        switch (model.budgetMin, model.budgetMax) {
        case (nil, nil): return "Not set"
        case (let minValue?, nil): return "From \(POPFormat.money(minValue, currencyCode: currency))"
        case (nil, let maxValue?): return "Up to \(POPFormat.money(maxValue, currencyCode: currency))"
        case (let minValue?, let maxValue?):
            return "\(POPFormat.money(minValue, currencyCode: currency)) – \(POPFormat.money(maxValue, currencyCode: currency))"
        }
    }
}

struct TemplateCriterionRow: View {
    let criterion: TemplateCriterion
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(criterion.name)
                        .font(POPFont.calloutMedium)
                        .foregroundStyle(POPColor.ink)
                    POPBadge(
                        text: criterion.importance.title,
                        color: criterion.importance.color,
                        soft: criterion.importance.softColor,
                        compact: true
                    )
                }
                Text(criterion.details)
                    .font(POPFont.caption)
                    .foregroundStyle(POPColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    POPBadge(text: criterion.kind.shortTitle, icon: criterion.kind.icon, compact: true)
                    POPBadge(text: POPFormat.percent(criterion.suggestedWeight),
                             color: POPColor.brandOrange, soft: POPColor.warningSoft, compact: true)
                }
            }
            Spacer(minLength: 0)
            Button(action: {
                Haptics.tap()
                onRemove()
            }) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(POPColor.danger.opacity(0.75))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Remove \(criterion.name)"))
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(POPColor.hairline, lineWidth: 1))
    }
}
