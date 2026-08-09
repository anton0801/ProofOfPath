//
//  ConstraintEditorSheet.swift
//  ProofOfPath
//
//  Hard constraints must be machine-checkable or explicitly manual —
//  the app never claims to have checked something it cannot check.
//

import SwiftUI

enum ConstraintCheckKind: String, CaseIterable, Identifiable, Hashable {
    case maximumCost
    case minimumCost
    case criterionAtLeast
    case criterionAtMost
    case criterionMustBeYes
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .maximumCost: return "Maximum cost"
        case .minimumCost: return "Minimum cost"
        case .criterionAtLeast: return "Criterion at least"
        case .criterionAtMost: return "Criterion at most"
        case .criterionMustBeYes: return "Criterion must be Yes"
        case .manual: return "I check it myself"
        }
    }

    var explanation: String {
        switch self {
        case .maximumCost: return "Any option priced above the limit is disqualified automatically."
        case .minimumCost: return "Any option priced below the floor is disqualified automatically."
        case .criterionAtLeast: return "Uses the measured value you record for a numeric criterion."
        case .criterionAtMost: return "Uses the measured value you record for a numeric criterion."
        case .criterionMustBeYes: return "Uses the Yes/No answer you record for a criterion."
        case .manual: return "You mark each option as Meets or Fails yourself. Nothing is inferred."
        }
    }

    var icon: String {
        switch self {
        case .maximumCost: return "arrow.down.circle"
        case .minimumCost: return "arrow.up.circle"
        case .criterionAtLeast: return "greaterthan.circle"
        case .criterionAtMost: return "lessthan.circle"
        case .criterionMustBeYes: return "checkmark.circle"
        case .manual: return "hand.point.up.left"
        }
    }

    var needsCriterion: Bool {
        self == .criterionAtLeast || self == .criterionAtMost || self == .criterionMustBeYes
    }

    var needsNumber: Bool {
        self != .criterionMustBeYes && self != .manual
    }
}

struct CriterionOption: Identifiable, Hashable {
    let id: UUID
    let name: String
    let kind: CriterionKind
}

struct ConstraintEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let currencyCode: String
    let criteria: [Criterion]
    let existing: HardConstraint?
    let onSave: (HardConstraint) -> Void

    @State private var title = ""
    @State private var details = ""
    @State private var kind: ConstraintCheckKind = .maximumCost
    @State private var valueText = ""
    @State private var selectedCriterionID: UUID?
    @State private var showValidation = false

    private var numericCriteria: [Criterion] {
        criteria.filter { $0.kind == .higherIsBetter || $0.kind == .lowerIsBetter || $0.kind == .ratingScale || $0.kind == .descriptive }
    }

    private var yesNoCriteria: [Criterion] {
        criteria.filter { $0.kind == .yesNo }
    }

    private var availableCriteria: [Criterion] {
        kind == .criterionMustBeYes ? yesNoCriteria : numericCriteria
    }

    private var availableKinds: [ConstraintCheckKind] {
        ConstraintCheckKind.allCases.filter { candidate in
            switch candidate {
            case .criterionAtLeast, .criterionAtMost: return !numericCriteria.isEmpty
            case .criterionMustBeYes: return !yesNoCriteria.isEmpty
            default: return true
            }
        }
    }

    private var titleError: String? {
        guard showValidation, title.popIsBlank else { return nil }
        return "Give the constraint a short name."
    }

    private var valueError: String? {
        guard showValidation, kind.needsNumber else { return nil }
        guard let value = POPFormat.parseNumber(valueText) else { return "Enter a number." }
        if value < 0 { return "The value cannot be negative." }
        return nil
    }

    private var criterionError: String? {
        guard showValidation, kind.needsCriterion, selectedCriterionID == nil else { return nil }
        return "Choose which criterion this constraint checks."
    }

    private var isValid: Bool {
        guard !title.popIsBlank else { return false }
        if kind.needsNumber {
            guard let value = POPFormat.parseNumber(valueText), value >= 0 else { return false }
        }
        if kind.needsCriterion, selectedCriterionID == nil { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {

                    POPBanner(
                        kind: .neutral,
                        message: "A hard constraint is pass or fail.",
                        detail: "An option that breaks one is marked Disqualified and can never be the leader, no matter how high it scores."
                    )

                    POPTextField(
                        label: "Constraint Name",
                        text: $title,
                        placeholder: "e.g. Must stay under 900",
                        isRequired: true,
                        errorText: titleError,
                        characterLimit: 60
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        POPSectionHeader(title: "How Should It Be Checked?", icon: "checkmark.shield")
                        VStack(spacing: 8) {
                            ForEach(availableKinds) { candidate in
                                CheckKindRow(kind: candidate, isSelected: kind == candidate) {
                                    kind = candidate
                                    if !candidate.needsCriterion { selectedCriterionID = nil }
                                    if candidate.needsCriterion, selectedCriterionID == nil {
                                        selectedCriterionID = (candidate == .criterionMustBeYes ? yesNoCriteria : numericCriteria).first?.id
                                    }
                                }
                            }
                        }
                        if criteria.isEmpty {
                            POPInlineNote(text: "Criterion-based checks appear once you have added criteria.")
                        }
                    }

                    if kind.needsCriterion {
                        VStack(alignment: .leading, spacing: 8) {
                            POPFieldShell(label: "Linked Criterion", isRequired: true, errorText: criterionError) {
                                VStack(spacing: 7) {
                                    ForEach(availableCriteria) { criterion in
                                        Button(action: {
                                            Haptics.selection()
                                            selectedCriterionID = criterion.id
                                        }) {
                                            HStack(spacing: 8) {
                                                Image(systemName: selectedCriterionID == criterion.id ? "largecircle.fill.circle" : "circle")
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundStyle(selectedCriterionID == criterion.id ? POPColor.brandOrange : POPColor.hairline)
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(criterion.displayName)
                                                        .font(POPFont.calloutMedium)
                                                        .foregroundStyle(POPColor.ink)
                                                    Text(criterion.kind.title)
                                                        .font(POPFont.caption)
                                                        .foregroundStyle(POPColor.inkSecondary)
                                                }
                                                Spacer(minLength: 0)
                                            }
                                            .padding(10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.surface))
                                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(POPColor.hairline, lineWidth: 1))
                                        }
                                        .buttonStyle(POPPressStyle())
                                    }
                                }
                            }
                        }
                    }

                    if kind.needsNumber {
                        POPNumberField(
                            label: kind == .criterionAtLeast || kind == .criterionAtMost ? "Threshold Value" : "Amount",
                            text: $valueText,
                            placeholder: "0",
                            isRequired: true,
                            hint: numberHint,
                            errorText: valueError,
                            prefix: (kind == .maximumCost || kind == .minimumCost) ? POPFormat.currencySymbol(for: currencyCode) : nil
                        )
                    }

                    POPTextEditor(
                        label: "Notes",
                        text: $details,
                        placeholder: "Why is this non-negotiable?",
                        characterLimit: 300,
                        minHeight: 78
                    )

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 8)
            }
            .background(POPColor.canvas.ignoresSafeArea())
            .navigationTitle(existing == nil ? "Add Constraint" : "Edit Constraint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(POPColor.inkSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .font(POPFont.bodyMedium)
                        .foregroundStyle(isValid ? POPColor.brandOrange : POPColor.inkTertiary)
                }
            }
        }
        .onAppear(perform: hydrate)
    }

    private var numberHint: String? {
        switch kind {
        case .maximumCost: return "Compared against each option's estimated cost."
        case .minimumCost: return "Compared against each option's estimated cost."
        case .criterionAtLeast, .criterionAtMost:
            guard let id = selectedCriterionID, let criterion = criteria.first(where: { $0.id == id }) else { return nil }
            return criterion.kind.expectsNumericValue
                ? "Compared against the measured value you record."
                : "Compared against the rating you give."
        default: return nil
        }
    }

    private func hydrate() {
        guard let existing else {
            if !availableKinds.contains(kind) { kind = availableKinds.first ?? .manual }
            return
        }
        title = existing.title
        details = existing.details
        switch existing.check {
        case .maximumCost(let value):
            kind = .maximumCost
            valueText = POPFormat.editableNumber(value)
        case .minimumCost(let value):
            kind = .minimumCost
            valueText = POPFormat.editableNumber(value)
        case .criterionAtLeast(let criterionID, let value):
            kind = .criterionAtLeast
            selectedCriterionID = criterionID
            valueText = POPFormat.editableNumber(value)
        case .criterionAtMost(let criterionID, let value):
            kind = .criterionAtMost
            selectedCriterionID = criterionID
            valueText = POPFormat.editableNumber(value)
        case .criterionMustBeYes(let criterionID):
            kind = .criterionMustBeYes
            selectedCriterionID = criterionID
        case .manual:
            kind = .manual
        }
    }

    private func save() {
        guard isValid else {
            showValidation = true
            Haptics.error()
            return
        }
        let value = POPFormat.parseNumber(valueText) ?? 0
        let check: ConstraintCheck
        switch kind {
        case .maximumCost: check = .maximumCost(value)
        case .minimumCost: check = .minimumCost(value)
        case .criterionAtLeast: check = .criterionAtLeast(criterionID: selectedCriterionID ?? UUID(), value: value)
        case .criterionAtMost: check = .criterionAtMost(criterionID: selectedCriterionID ?? UUID(), value: value)
        case .criterionMustBeYes: check = .criterionMustBeYes(criterionID: selectedCriterionID ?? UUID())
        case .manual: check = .manual
        }

        var constraint = existing ?? HardConstraint()
        constraint.title = title.popTrimmed
        constraint.details = details.popTrimmed
        constraint.check = check
        onSave(constraint)
        Haptics.success()
        dismiss()
    }
}

private struct CheckKindRow: View {
    let kind: ConstraintCheckKind
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.selection()
            action()
        }) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: kind.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? POPColor.graphite : POPColor.brandOrange)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? POPColor.brandYellow : POPColor.warningSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(POPFont.calloutMedium)
                        .foregroundStyle(POPColor.ink)
                    Text(kind.explanation)
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? POPColor.brandOrange : POPColor.hairline)
                    .padding(.top, 2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? POPColor.brandOrange.opacity(0.45) : POPColor.hairline,
                              lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(POPPressStyle())
    }
}
