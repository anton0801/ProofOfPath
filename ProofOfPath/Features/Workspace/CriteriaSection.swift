//
//  CriteriaSection.swift
//  ProofOfPath
//
//  Criteria Workshop — weights must total exactly 100% before comparison opens.
//

import SwiftUI

struct CriteriaSection: View {
    @Environment(AppStore.self) private var store
    let decisionID: UUID

    @State private var editingCriterion: Criterion?
    @State private var showEditor = false
    @State private var pendingDelete: Criterion?
    @State private var isReordering = false
    @State private var showTemplatePicker = false

    private var decision: Decision? { store.state.decision(id: decisionID) }

    var body: some View {
        if let decision {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                WorkspaceSectionIntro(
                    title: "Evaluation Criteria",
                    subtitle: "What you will judge every option against. Weights show how much each one matters.",
                    icon: "list.bullet.indent"
                )

                if decision.criteria.isEmpty {
                    emptyState
                } else {
                    weightSummary(decision)
                    criteriaList(decision)
                    actions(decision)
                }
            }
            .sheet(isPresented: $showEditor, onDismiss: { editingCriterion = nil }) {
                CriterionEditorSheet(
                    decisionID: decisionID,
                    existing: editingCriterion,
                    suggestedWeight: suggestedWeight(decision)
                )
            }
            .sheet(isPresented: $showTemplatePicker) {
                TemplateCriteriaPicker(decisionID: decisionID)
            }
            .alert(
                "Delete this criterion?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete
            ) { criterion in
                Button("Cancel", role: .cancel) { pendingDelete = nil }
                Button("Delete", role: .destructive) {
                    store.send(.deleteCriterion(decisionID: decisionID, criterionID: criterion.id))
                    pendingDelete = nil
                }
            } message: { criterion in
                Text(deleteMessage(for: criterion, in: decision))
            }
        }
    }

    private func deleteMessage(for criterion: Criterion, in decision: Decision) -> String {
        let evaluated = decision.options.filter { option in
            guard let evaluation = option.evaluation(for: criterion.id) else { return false }
            return !evaluation.isEmpty
        }.count
        let evidenceLinks = store.state.evidence(forDecision: decision.id)
            .filter { item in item.links.contains { $0.criterionID == criterion.id } }.count
        let constraints = decision.hardConstraints.filter { $0.check.linkedCriterionID == criterion.id }.count

        var parts: [String] = []
        if evaluated > 0 { parts.append("\(evaluated) \(evaluated == 1 ? "evaluation" : "evaluations")") }
        if evidenceLinks > 0 { parts.append("\(evidenceLinks) evidence \(evidenceLinks == 1 ? "link" : "links")") }
        if constraints > 0 { parts.append("\(constraints) hard \(constraints == 1 ? "constraint" : "constraints") will become manual") }

        if parts.isEmpty {
            return "“\(criterion.displayName)” has no attached data yet."
        }
        return "“\(criterion.displayName)” is used by \(parts.joined(separator: ", ")). Deleting it removes that data."
    }

    private func suggestedWeight(_ decision: Decision) -> Double {
        max(0, min(100, decision.weightRemaining)).rounded(toPlaces: 1)
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            POPEmptyState(
                icon: "list.bullet.indent",
                title: "No criteria yet",
                message: "Decide what matters before you look at options. Criteria are what turn a gut feeling into a comparison.",
                actionTitle: "Add Criterion",
                action: {
                    editingCriterion = nil
                    showEditor = true
                },
                secondaryTitle: "Use a starting structure",
                secondaryAction: { showTemplatePicker = true }
            )
        }
        .popCard(padding: 6)
    }

    // MARK: Weight summary

    private func weightSummary(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Weight")
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                    Text(POPFormat.percent(decision.totalWeight))
                        .font(POPFont.numericLarge)
                        .foregroundStyle(weightColor(decision))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Weight Remaining")
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                    Text(POPFormat.percent(decision.weightRemaining))
                        .font(POPFont.numeric)
                        .foregroundStyle(decision.weightRemaining == 0 ? POPColor.success : POPColor.brandOrange)
                }
            }

            WeightBar(total: decision.totalWeight)

            if decision.isWeightBalanced {
                POPBanner(kind: .success, message: "Weights add up to exactly 100%.",
                          detail: "Comparison and finalization are unlocked.")
            } else if decision.totalWeight > 100 {
                POPBanner(kind: .danger,
                          message: "Criteria weights exceed 100%. Reduce one or more values.",
                          detail: "Currently \(POPFormat.percent(decision.totalWeight)) — that is \(POPFormat.percent(decision.totalWeight - 100)) too much.")
            } else {
                POPBanner(kind: .warning,
                          message: "Assign the remaining weight before comparing options.",
                          detail: "\(POPFormat.percent(decision.weightRemaining)) is still unassigned.",
                          actionTitle: "Balance Criteria",
                          action: { store.send(.balanceCriteriaWeights(decisionID: decisionID)) })
            }

            POPInlineNote(text: "Every criterion carries a weight. Must-Have criteria also act as pass/fail gates — an option that fails one cannot lead, whatever it scores.")
        }
        .popCard()
    }

    private func weightColor(_ decision: Decision) -> Color {
        if decision.isWeightBalanced { return POPColor.success }
        return decision.totalWeight > 100 ? POPColor.danger : POPColor.brandOrange
    }

    // MARK: List

    private func criteriaList(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                POPSectionHeader(title: "\(decision.criteria.count) Criteria", icon: "list.number")
                Spacer()
                POPTextButton(
                    title: isReordering ? "Done" : "Reorder",
                    icon: isReordering ? "checkmark" : "arrow.up.arrow.down"
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { isReordering.toggle() }
                }
            }

            if isReordering {
                ReorderableCriteriaList(decisionID: decisionID, criteria: decision.sortedCriteria)
            } else {
                VStack(spacing: 10) {
                    ForEach(decision.sortedCriteria) { criterion in
                        CriterionRow(
                            criterion: criterion,
                            decision: decision,
                            evidenceCount: evidenceCount(for: criterion, in: decision),
                            onWeightChange: { newValue in
                                store.send(.setCriterionWeight(decisionID: decisionID, criterionID: criterion.id, weight: newValue))
                            },
                            onEdit: {
                                editingCriterion = criterion
                                showEditor = true
                            },
                            onDuplicate: {
                                store.send(.duplicateCriterion(decisionID: decisionID, criterionID: criterion.id))
                            },
                            onDelete: { pendingDelete = criterion }
                        )
                    }
                }
            }
        }
    }

    private func evidenceCount(for criterion: Criterion, in decision: Decision) -> Int {
        store.state.evidence(forDecision: decision.id)
            .filter { item in item.links.contains { $0.criterionID == criterion.id } }
            .count
    }

    // MARK: Actions

    private func actions(_ decision: Decision) -> some View {
        VStack(spacing: 10) {
            POPPrimaryButton(title: "Add Criterion", icon: "plus") {
                editingCriterion = nil
                showEditor = true
            }
            HStack(spacing: 10) {
                POPSecondaryButton(title: "Balance Criteria", icon: "equal.circle") {
                    store.send(.balanceCriteriaWeights(decisionID: decisionID))
                }
                POPSecondaryButton(title: "Add from Structure", icon: "square.grid.2x2") {
                    showTemplatePicker = true
                }
            }
        }
    }
}

// MARK: - Criterion row

struct CriterionRow: View {
    let criterion: Criterion
    let decision: Decision
    let evidenceCount: Int
    let onWeightChange: (Double) -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var draftWeight: Double = 0
    @State private var isDragging = false

    private var usedByConstraint: Bool {
        decision.hardConstraints.contains { $0.check.linkedCriterionID == criterion.id }
    }

    private var evaluatedCount: Int {
        decision.comparableOptions.filter { option in
            guard let evaluation = option.evaluation(for: criterion.id) else { return false }
            return evaluation.hasJudgement
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(criterion.displayName)
                            .font(POPFont.cardTitle)
                            .foregroundStyle(POPColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if usedByConstraint {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(POPColor.brandOrange)
                        }
                    }
                    HStack(spacing: 6) {
                        POPBadge(text: criterion.importance.title, icon: criterion.importance.icon,
                                 color: criterion.importance.color, soft: criterion.importance.softColor, compact: true)
                        POPBadge(text: criterion.kind.shortTitle, icon: criterion.kind.icon, compact: true)
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    Button { onEdit() } label: { Label("Edit Criterion", systemImage: "pencil") }
                    Button { onDuplicate() } label: { Label("Duplicate Criterion", systemImage: "plus.square.on.square") }
                    Divider()
                    Button(role: .destructive) { onDelete() } label: { Label("Delete Criterion", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(POPColor.inkTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Criterion actions"))
            }

            if !criterion.details.popIsBlank {
                Text(criterion.details)
                    .font(POPFont.caption)
                    .foregroundStyle(POPColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Weight control
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Importance")
                        .font(POPFont.micro)
                        .foregroundStyle(POPColor.inkTertiary)
                    Spacer()
                    Text(POPFormat.percent(isDragging ? draftWeight : criterion.weight))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(POPColor.ink)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { isDragging ? draftWeight : criterion.weight },
                        set: { draftWeight = ($0).rounded(toPlaces: 0) }
                    ),
                    in: 0...100,
                    step: 1,
                    onEditingChanged: { editing in
                        if editing {
                            draftWeight = criterion.weight
                            isDragging = true
                        } else {
                            isDragging = false
                            onWeightChange(draftWeight)
                            Haptics.selection()
                        }
                    }
                )
                .tint(POPColor.brandOrange)
            }

            // Meta row
            HStack(spacing: 12) {
                metaItem(icon: "checkmark.square", text: "\(evaluatedCount)/\(decision.comparableOptions.count) evaluated")
                if evidenceCount > 0 {
                    metaItem(icon: "paperclip", text: "\(evidenceCount) evidence")
                }
                Spacer(minLength: 0)
            }

            if criterion.importance == .mustHave, needsThreshold {
                POPInlineNote(
                    text: "Add a minimum acceptable value so this Must Have can actually be checked.",
                    icon: "exclamationmark.triangle.fill",
                    tint: POPColor.brandOrange
                )
            }
        }
        .padding(POPMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: POPMetrics.cardRadius, style: .continuous).fill(POPColor.surface))
        .overlay(
            RoundedRectangle(cornerRadius: POPMetrics.cardRadius, style: .continuous)
                .strokeBorder(criterion.importance == .mustHave ? POPColor.brandOrange.opacity(0.35) : POPColor.hairline,
                              lineWidth: criterion.importance == .mustHave ? 1.4 : 1)
        )
    }

    private var needsThreshold: Bool {
        criterion.kind != .yesNo && POPFormat.parseNumber(criterion.minimumAcceptableValue) == nil
    }

    private func metaItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(text).font(POPFont.caption)
        }
        .foregroundStyle(POPColor.inkSecondary)
    }
}

// MARK: - Reordering

/// Explicit move buttons rather than drag-to-reorder: a nested List inside a
/// ScrollView needs a hard-coded height, which breaks at larger text sizes,
/// and buttons are reachable with VoiceOver and Switch Control too.
struct ReorderableCriteriaList: View {
    @Environment(AppStore.self) private var store
    let decisionID: UUID
    let criteria: [Criterion]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(criteria.enumerated()), id: \.element.id) { index, criterion in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(POPColor.inkSecondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(POPColor.surfaceMuted))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(criterion.displayName)
                            .font(POPFont.bodyMedium)
                            .foregroundStyle(POPColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(criterion.importance.title) · \(POPFormat.percent(criterion.weight))")
                            .font(POPFont.caption)
                            .foregroundStyle(POPColor.inkSecondary)
                    }
                    Spacer(minLength: 8)

                    moveButton(icon: "chevron.up", isEnabled: index > 0, label: "Move \(criterion.displayName) up") {
                        move(from: index, to: index - 1)
                    }
                    moveButton(icon: "chevron.down", isEnabled: index < criteria.count - 1,
                               label: "Move \(criterion.displayName) down") {
                        move(from: index, to: index + 2)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(POPColor.surface))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(POPColor.hairline, lineWidth: 1))
            }
        }
    }

    private func moveButton(icon: String, isEnabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            guard isEnabled else { return }
            Haptics.selection()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isEnabled ? POPColor.graphite : POPColor.hairline)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(POPColor.surfaceMuted))
        }
        .buttonStyle(POPPressStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(Text(label))
    }

    /// `to` follows the `move(fromOffsets:toOffset:)` convention, where moving
    /// down needs the index after the target.
    private func move(from index: Int, to destination: Int) {
        store.send(.moveCriteria(decisionID: decisionID, from: IndexSet(integer: index), to: destination))
    }
}

// MARK: - Criterion editor

struct CriterionEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID
    let existing: Criterion?
    var suggestedWeight: Double = 0

    @State private var name = ""
    @State private var details = ""
    @State private var importance: CriterionImportance = .niceToHave
    @State private var kind: CriterionKind = .ratingScale
    @State private var measurementMethod = ""
    @State private var targetValue = ""
    @State private var minimumAcceptable = ""
    @State private var weightText = ""
    @State private var showValidation = false
    @State private var loaded = false

    private var decision: Decision? { store.state.decision(id: decisionID) }

    private var weight: Double? { POPFormat.parseNumber(weightText) }

    private var nameError: String? {
        guard showValidation else { return nil }
        if name.popIsBlank { return "The criterion needs a name." }
        if let decision {
            let duplicate = decision.criteria.contains {
                $0.id != existing?.id && $0.name.popNormalizedForCompare == name.popNormalizedForCompare
            }
            if duplicate { return "A criterion with this name already exists in this decision." }
        }
        return nil
    }

    private var weightError: String? {
        guard showValidation else { return nil }
        guard let weight else { return weightText.popIsBlank ? nil : "Weight must be a number." }
        if weight < 0 { return "Weight cannot be negative." }
        if weight > 100 { return "Weight cannot exceed 100%." }
        return nil
    }

    private var projectedTotal: Double {
        guard let decision else { return weight ?? 0 }
        let others = decision.criteria
            .filter { $0.id != existing?.id }
            .reduce(0) { $0 + $1.weight }
        return others + (weight ?? 0)
    }

    private var minimumLabel: String {
        switch kind {
        case .lowerIsBetter: return "Maximum Acceptable Value"
        case .yesNo: return "Minimum Acceptable Value"
        default: return "Minimum Acceptable Value"
        }
    }

    private var minimumHint: String {
        switch kind {
        case .higherIsBetter: return "An option measuring below this fails the criterion."
        case .lowerIsBetter: return "An option measuring above this fails the criterion."
        case .yesNo: return "Yes/No criteria are checked by the answer itself."
        case .ratingScale, .descriptive: return "The lowest rating you would still accept, e.g. 3."
        }
    }

    private var isValid: Bool {
        guard !name.popIsBlank else { return false }
        if let decision {
            let duplicate = decision.criteria.contains {
                $0.id != existing?.id && $0.name.popNormalizedForCompare == name.popNormalizedForCompare
            }
            if duplicate { return false }
        }
        if !weightText.popIsBlank {
            guard let weight, weight >= 0, weight <= 100 else { return false }
        }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                    POPTextField(
                        label: "Criterion Name",
                        text: $name,
                        placeholder: "e.g. Warranty length",
                        isRequired: true,
                        errorText: nameError,
                        characterLimit: 60
                    )

                    POPTextEditor(
                        label: "Description",
                        text: $details,
                        placeholder: "What exactly does this criterion cover?",
                        characterLimit: 400,
                        minHeight: 80
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        POPSectionHeader(title: "Importance", icon: "exclamationmark.circle")
                        POPSegmentedPicker(
                            label: "Set Importance",
                            options: CriterionImportance.allCases,
                            selection: $importance,
                            titleFor: { $0.title },
                            iconFor: { $0.icon },
                            columns: 2
                        )
                        POPInlineNote(
                            text: importance == .mustHave
                                ? "Must Have: an option that fails it is marked “Does Not Meet Must-Have Requirements” and can never be the leader."
                                : "Nice to Have: contributes to the score through its weight, but never disqualifies an option."
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        POPNumberField(
                            label: "Weight",
                            text: $weightText,
                            placeholder: "0",
                            hint: "Percent of the total. All criteria share one 100% budget.",
                            errorText: weightError,
                            suffix: "%"
                        )
                        HStack(spacing: 6) {
                            Text("Total after saving:")
                                .font(POPFont.caption)
                                .foregroundStyle(POPColor.inkSecondary)
                            Text(POPFormat.percent(projectedTotal))
                                .font(POPFont.captionMedium)
                                .foregroundStyle(abs(projectedTotal - 100) < 0.05 ? POPColor.success
                                                 : (projectedTotal > 100 ? POPColor.danger : POPColor.brandOrange))
                            Spacer()
                            if suggestedWeight > 0 && existing == nil {
                                POPTextButton(title: "Use remaining \(POPFormat.percent(suggestedWeight))") {
                                    weightText = POPFormat.editableNumber(suggestedWeight)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        POPSectionHeader(title: "Criterion Type", icon: "slider.horizontal.3")
                        POPSegmentedPicker(
                            label: "How Is It Judged?",
                            options: CriterionKind.allCases,
                            selection: $kind,
                            titleFor: { $0.title },
                            iconFor: { $0.icon },
                            columns: 1
                        )
                        POPInlineNote(text: kind.explanation)
                    }

                    POPTextField(
                        label: "Measurement Method",
                        text: $measurementMethod,
                        placeholder: "How will you actually measure this?",
                        hint: "Written down now, this stops you from guessing later.",
                        characterLimit: 160
                    )

                    HStack(alignment: .top, spacing: 10) {
                        POPTextField(
                            label: "Target Value",
                            text: $targetValue,
                            placeholder: kind.expectsNumericValue ? "e.g. 24" : "e.g. Excellent",
                            characterLimit: 40
                        )
                        POPTextField(
                            label: minimumLabel,
                            text: $minimumAcceptable,
                            placeholder: kind == .yesNo ? "—" : "e.g. 12",
                            characterLimit: 40,
                            keyboard: kind == .yesNo ? .default : .decimalPad
                        )
                    }
                    POPInlineNote(text: minimumHint)

                    if importance == .mustHave, kind != .yesNo, POPFormat.parseNumber(minimumAcceptable) == nil {
                        POPBanner(
                            kind: .warning,
                            message: "This Must Have has no numeric threshold yet.",
                            detail: "Without one the app cannot decide whether an option passes or fails it."
                        )
                    }

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 8)
            }
            .background(POPColor.canvas.ignoresSafeArea())
            .navigationTitle(existing == nil ? "Add Criterion" : "Edit Criterion")
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

    private func hydrate() {
        guard !loaded else { return }
        loaded = true
        if let existing {
            name = existing.name
            details = existing.details
            importance = existing.importance
            kind = existing.kind
            measurementMethod = existing.measurementMethod
            targetValue = existing.targetValue
            minimumAcceptable = existing.minimumAcceptableValue
            weightText = POPFormat.editableNumber(existing.weight)
        } else if suggestedWeight > 0 {
            weightText = POPFormat.editableNumber(suggestedWeight)
        }
    }

    private func save() {
        guard isValid else {
            showValidation = true
            Haptics.error()
            return
        }
        var criterion = existing ?? Criterion()
        criterion.name = name.popTrimmed
        criterion.details = details.popTrimmed
        criterion.importance = importance
        criterion.kind = kind
        criterion.measurementMethod = measurementMethod.popTrimmed
        criterion.targetValue = targetValue.popTrimmed
        criterion.minimumAcceptableValue = minimumAcceptable.popTrimmed
        criterion.weight = max(0, min(100, weight ?? 0))

        if existing == nil {
            store.send(.addCriterion(decisionID: decisionID, criterion: criterion))
        } else {
            store.send(.updateCriterion(decisionID: decisionID, criterion: criterion))
        }
        dismiss()
    }
}

// MARK: - Template criteria picker

struct TemplateCriteriaPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID

    @State private var selectedTemplate: DecisionTemplate?
    @State private var selectedNames: Set<String> = []

    private var decision: Decision? { store.state.decision(id: decisionID) }

    private var availableTemplates: [DecisionTemplate] {
        DecisionTemplateLibrary.all.filter { !$0.criteria.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                    POPBanner(
                        kind: .neutral,
                        message: "Starting structures add suggested criteria only.",
                        detail: "They never create options, evidence or ratings. Review every criterion and remove what does not apply."
                    )

                    if let template = selectedTemplate {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                POPSectionHeader(title: template.title, subtitle: template.subtitle, icon: template.icon)
                                Spacer()
                                POPTextButton(title: "Change", icon: "arrow.left") {
                                    selectedTemplate = nil
                                    selectedNames = []
                                }
                            }

                            ForEach(Array(template.criteria.enumerated()), id: \.offset) { _, criterion in
                                let alreadyExists = decision?.criteria.contains {
                                    $0.name.popNormalizedForCompare == criterion.name.popNormalizedForCompare
                                } ?? false

                                Button(action: {
                                    guard !alreadyExists else { return }
                                    Haptics.selection()
                                    if selectedNames.contains(criterion.name) {
                                        selectedNames.remove(criterion.name)
                                    } else {
                                        selectedNames.insert(criterion.name)
                                    }
                                }) {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: alreadyExists
                                              ? "checkmark.circle.fill"
                                              : (selectedNames.contains(criterion.name) ? "checkmark.square.fill" : "square"))
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(alreadyExists ? POPColor.inkTertiary
                                                             : (selectedNames.contains(criterion.name) ? POPColor.brandOrange : POPColor.hairline))
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(criterion.name)
                                                    .font(POPFont.calloutMedium)
                                                    .foregroundStyle(alreadyExists ? POPColor.inkTertiary : POPColor.ink)
                                                POPBadge(text: criterion.importance.title,
                                                         color: criterion.importance.color,
                                                         soft: criterion.importance.softColor, compact: true)
                                            }
                                            Text(alreadyExists ? "Already in this decision" : criterion.details)
                                                .font(POPFont.caption)
                                                .foregroundStyle(POPColor.inkSecondary)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                            HStack(spacing: 7) {
                                                POPBadge(text: criterion.kind.shortTitle, icon: criterion.kind.icon, compact: true)
                                                POPBadge(text: "suggested \(POPFormat.percent(criterion.suggestedWeight))",
                                                         color: POPColor.brandOrange, soft: POPColor.warningSoft, compact: true)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(11)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surface))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(POPColor.hairline, lineWidth: 1))
                                    .opacity(alreadyExists ? 0.55 : 1)
                                }
                                .buttonStyle(POPPressStyle())
                                .disabled(alreadyExists)
                            }

                            if !selectedNames.isEmpty, let decision {
                                let addedWeight = template.criteria
                                    .filter { selectedNames.contains($0.name) }
                                    .reduce(0) { $0 + $1.suggestedWeight }
                                POPBanner(
                                    kind: abs(decision.totalWeight + addedWeight - 100) < 0.05 ? .success : .warning,
                                    message: "Total weight after adding: \(POPFormat.percent(decision.totalWeight + addedWeight))",
                                    detail: abs(decision.totalWeight + addedWeight - 100) < 0.05
                                        ? "That is exactly 100%."
                                        : "You will need to rebalance to reach exactly 100%."
                                )
                            }
                        }
                    } else {
                        VStack(spacing: 9) {
                            ForEach(availableTemplates) { template in
                                TemplateChoiceRow(template: template, isSelected: false) {
                                    selectedTemplate = template
                                    selectedNames = Set(
                                        template.criteria
                                            .filter { candidate in
                                                !(decision?.criteria.contains {
                                                    $0.name.popNormalizedForCompare == candidate.name.popNormalizedForCompare
                                                } ?? false)
                                            }
                                            .map(\.name)
                                    )
                                }
                            }
                        }
                    }

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 8)
            }
            .background(POPColor.canvas.ignoresSafeArea())
            .navigationTitle("Review Suggested Criteria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(POPColor.inkSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add \(selectedNames.count)") { add() }
                        .font(POPFont.bodyMedium)
                        .foregroundStyle(selectedNames.isEmpty ? POPColor.inkTertiary : POPColor.brandOrange)
                        .disabled(selectedNames.isEmpty)
                }
            }
        }
    }

    private func add() {
        guard let template = selectedTemplate, !selectedNames.isEmpty else { return }
        let chosen = template.criteria.filter { selectedNames.contains($0.name) }
        store.send(.applyTemplateCriteria(decisionID: decisionID, templateID: template.id, criteria: chosen))
        dismiss()
    }
}
