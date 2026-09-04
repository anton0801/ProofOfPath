//
//  ScenarioLabView.swift
//  ProofOfPath
//
//  The baseline can never be overwritten. Every alternative is stored separately.
//

import SwiftUI

struct ScenarioLabView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID

    @State private var selectedScenarioID: UUID?
    @State private var showPresetPicker = false
    @State private var editingScenario: Scenario?
    @State private var pendingDelete: Scenario?

    private var decision: Decision? { store.state.decision(id: decisionID) }

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
    }

    private func content(_ decision: Decision) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                CoinStrikeFeatureBanner(asset: "CoinStrikeScenario")
                POPBanner(
                    kind: .neutral,
                    message: "The baseline is read-only.",
                    detail: "Scenarios never change your real criteria, weights or options — they only show what would happen if they were different."
                )

                baselineCard(decision)

                if decision.scenarios.isEmpty {
                    POPEmptyState(
                        icon: "flask",
                        title: "No scenarios yet",
                        message: "Test what happens if the budget drops, the deadline moves, or one criterion suddenly matters more.",
                        actionTitle: "Create Scenario",
                        action: { showPresetPicker = true }
                    )
                    .popCard(padding: 6)
                } else {
                    ForEach(decision.scenarios) { scenario in
                        scenarioCard(scenario, decision: decision)
                    }
                    POPPrimaryButton(title: "Create Scenario", icon: "plus") {
                        showPresetPicker = true
                    }
                }

                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 10)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationTitle("Scenario Lab")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPresetPicker) {
            ScenarioPresetPicker(decisionID: decisionID) { scenario in
                editingScenario = scenario
            }
        }
        .sheet(item: $editingScenario) { scenario in
            ScenarioEditorSheet(decisionID: decisionID, scenario: scenario,
                                isNew: decision.scenario(id: scenario.id) == nil)
        }
        .alert(
            "Delete this scenario?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { scenario in
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                store.send(.deleteScenario(decisionID: decisionID, scenarioID: scenario.id))
                pendingDelete = nil
            }
        } message: { _ in
            Text("The baseline and your real data are not affected.")
        }
    }

    // MARK: Baseline

    private func baselineCard(_ decision: Decision) -> some View {
        let baseline = ScenarioEngine.baseline(
            decision: decision,
            evidence: store.state.evidence(forDecision: decisionID),
            scaleMax: store.state.scaleMax
        )
        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(POPColor.graphite)
                Text("Baseline")
                    .font(POPFont.sectionTitle)
                    .foregroundStyle(POPColor.ink)
                Spacer()
                POPBadge(text: "Read-only", color: POPColor.inkSecondary, soft: POPColor.neutralSoft, compact: true)
            }

            if let leaderID = baseline.leaderID, let option = decision.option(id: leaderID) {
                HStack(spacing: 10) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(POPColor.brandOrange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(option.displayName)
                            .font(POPFont.cardTitle)
                            .foregroundStyle(POPColor.ink)
                        Text("Baseline leader")
                            .font(POPFont.caption)
                            .foregroundStyle(POPColor.inkSecondary)
                    }
                    Spacer()
                    Text(POPFormat.score(baseline.scoreboard.score(for: leaderID)?.weightedScore ?? 0))
                        .font(POPFont.numeric)
                        .foregroundStyle(POPColor.ink)
                        .monospacedDigit()
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.surfaceSunk))
            } else {
                POPInlineNote(text: "No clear leader in the baseline yet.")
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(decision.sortedCriteria) { criterion in
                    HStack(spacing: 8) {
                        Text(criterion.displayName)
                            .font(POPFont.caption)
                            .foregroundStyle(POPColor.inkSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(POPFormat.percent(criterion.weight))
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundStyle(POPColor.ink)
                            .monospacedDigit()
                    }
                }
            }
        }
        .popCard()
    }

    // MARK: Scenario card

    private func scenarioCard(_ scenario: Scenario, decision: Decision) -> some View {
        let comparison = ScenarioEngine.compare(
            scenario: scenario,
            decision: decision,
            evidence: store.state.evidence(forDecision: decisionID),
            scaleMax: store.state.scaleMax
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: scenario.preset.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(POPColor.brandOrange)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(POPColor.warningSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text(scenario.displayName)
                        .font(POPFont.cardTitle)
                        .foregroundStyle(POPColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Created \(POPFormat.date(scenario.createdAt))")
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkTertiary)
                }
                Spacer(minLength: 0)
                Menu {
                    Button { editingScenario = scenario } label: { Label("Edit Scenario", systemImage: "pencil") }
                    Button {
                        store.send(.duplicateScenario(decisionID: decisionID, scenarioID: scenario.id))
                    } label: { Label("Duplicate Scenario", systemImage: "plus.square.on.square") }
                    Divider()
                    Button(role: .destructive) { pendingDelete = scenario } label: {
                        Label("Delete Scenario", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(POPColor.inkTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Scenario actions"))
            }

            // Scenario leader
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scenario Leader")
                        .font(POPFont.micro)
                        .foregroundStyle(POPColor.inkTertiary)
                    Text(comparison.scenarioLeaderName ?? "No clear leader")
                        .font(POPFont.cardTitle)
                        .foregroundStyle(comparison.scenarioLeaderName == nil ? POPColor.inkTertiary : POPColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if comparison.leaderChanged {
                    POPBadge(text: "Leader changed", icon: "arrow.left.arrow.right",
                             color: POPColor.brandOrange, soft: POPColor.warningSoft, compact: true)
                } else {
                    POPBadge(text: "Same leader", icon: "equal",
                             color: POPColor.success, soft: POPColor.successSoft, compact: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(comparison.leaderChanged ? POPColor.warningSoft : POPColor.successSoft))

            // What changed
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(POPColor.graphite)
                    Text("What Changed?")
                        .font(POPFont.captionMedium)
                        .foregroundStyle(POPColor.ink)
                }
                Text(comparison.explanation)
                    .font(POPFont.callout)
                    .foregroundStyle(POPColor.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if !comparison.changes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(comparison.changes) { change in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(POPColor.brandOrange)
                                    .padding(.top, 3)
                                Text("\(change.label): \(change.detail)")
                                    .font(POPFont.caption)
                                    .foregroundStyle(POPColor.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }

            // Score deltas
            if !comparison.scenario.scoreboard.scores.isEmpty {
                POPDivider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Compare with Baseline")
                        .font(POPFont.micro)
                        .foregroundStyle(POPColor.inkTertiary)
                    ForEach(comparison.scenario.scoreboard.ranked) { score in
                        if let option = decision.option(id: score.optionID) {
                            let delta = comparison.scoreDeltas[score.optionID] ?? 0
                            HStack(spacing: 9) {
                                Text(option.displayName)
                                    .font(POPFont.caption)
                                    .foregroundStyle(score.isEligibleLeader ? POPColor.ink : POPColor.inkTertiary)
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                Text(POPFormat.score(score.weightedScore))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(POPColor.ink)
                                    .monospacedDigit()
                                Text(deltaText(delta))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(deltaColor(delta))
                                    .monospacedDigit()
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }
                    }
                    if !comparison.scenario.excludedOptionIDs.isEmpty {
                        Text("\(comparison.scenario.excludedOptionIDs.count) excluded from this scenario")
                            .font(.system(size: 10.5))
                            .foregroundStyle(POPColor.inkTertiary)
                    }
                }
            }
        }
        .popCard()
    }

    private func deltaText(_ delta: Double) -> String {
        if abs(delta) < 0.05 { return "—" }
        return "\(delta > 0 ? "+" : "")\(POPFormat.score(delta))"
    }

    private func deltaColor(_ delta: Double) -> Color {
        if abs(delta) < 0.05 { return POPColor.inkTertiary }
        return delta > 0 ? POPColor.success : POPColor.danger
    }
}

// MARK: - Preset picker

struct ScenarioPresetPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID
    let onPick: (Scenario) -> Void

    private var decision: Decision? { store.state.decision(id: decisionID) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    POPBanner(
                        kind: .neutral,
                        message: "Presets are a starting point.",
                        detail: "Every value stays editable in the next step, and nothing is saved until you confirm."
                    )

                    ForEach(ScenarioPreset.allCases) { preset in
                        Button(action: {
                            Haptics.tap()
                            guard let decision else { return }
                            let scenario = ScenarioEngine.makeScenario(
                                preset: preset,
                                decision: decision,
                                evidence: store.state.evidence(forDecision: decisionID),
                                scaleMax: store.state.scaleMax
                            )
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                onPick(scenario)
                            }
                        }) {
                            HStack(alignment: .top, spacing: 11) {
                                Image(systemName: preset.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(POPColor.brandOrange)
                                    .frame(width: 36, height: 36)
                                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(POPColor.warningSoft))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.title)
                                        .font(POPFont.cardTitle)
                                        .foregroundStyle(POPColor.ink)
                                    Text(preset.explanation)
                                        .font(POPFont.caption)
                                        .foregroundStyle(POPColor.inkSecondary)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(POPColor.inkTertiary)
                                    .padding(.top, 4)
                            }
                            .padding(11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(POPColor.surface))
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(POPColor.hairline, lineWidth: 1))
                        }
                        .buttonStyle(POPPressStyle())
                    }

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 8)
            }
            .background(POPColor.canvas.ignoresSafeArea())
            .navigationTitle("Create Scenario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(POPColor.inkSecondary)
                }
            }
        }
    }
}

// MARK: - Scenario editor

struct ScenarioEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID
    let scenario: Scenario
    let isNew: Bool

    @State private var name = ""
    @State private var budgetText = ""
    @State private var deadline: Date?
    @State private var weights: [String: Double] = [:]
    @State private var excluded: Set<UUID> = []
    @State private var additionalConstraint = ""
    @State private var showValidation = false
    @State private var loaded = false

    private var decision: Decision? { store.state.decision(id: decisionID) }

    private var nameError: String? {
        guard showValidation, name.popIsBlank else { return nil }
        return "Give the scenario a name so you can tell them apart."
    }

    private var budgetError: String? {
        guard !budgetText.popIsBlank else { return nil }
        guard let value = POPFormat.parseNumber(budgetText) else { return "Budget limit must be a number." }
        return value < 0 ? "Budget limit cannot be negative." : nil
    }

    private var weightTotal: Double {
        guard let decision else { return 0 }
        return decision.sortedCriteria.reduce(0) { $0 + (weights[$1.id.uuidString] ?? $1.weight) }
    }

    private var isValid: Bool { !name.popIsBlank && budgetError == nil }

    var body: some View {
        NavigationStack {
            Group {
                if let decision {
                    content(decision)
                } else {
                    POPEmptyState(icon: "questionmark.folder", title: "Decision not found",
                                  message: "", actionTitle: "Close", action: { dismiss() })
                }
            }
        }
        .onAppear(perform: hydrate)
    }

    private func content(_ decision: Decision) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                POPTextField(
                    label: "Scenario Name",
                    text: $name,
                    placeholder: "e.g. If money were tighter",
                    isRequired: true,
                    errorText: nameError,
                    characterLimit: 60
                )

                VStack(alignment: .leading, spacing: 10) {
                    POPSectionHeader(title: "Adjusted Criteria Weights", icon: "slider.horizontal.3")
                    HStack {
                        Text("Scenario total")
                            .font(POPFont.caption)
                            .foregroundStyle(POPColor.inkSecondary)
                        Spacer()
                        Text(POPFormat.percent(weightTotal))
                            .font(POPFont.captionMedium)
                            .foregroundStyle(abs(weightTotal - 100) < 0.05 ? POPColor.success : POPColor.brandOrange)
                    }
                    WeightBar(total: weightTotal)
                    if abs(weightTotal - 100) >= 0.05 {
                        POPInlineNote(
                            text: "Scenario weights do not add up to 100%. Scores are still normalised, so the comparison stays valid — but it is easier to read at exactly 100%.",
                            icon: "info.circle"
                        )
                    }

                    ForEach(decision.sortedCriteria) { criterion in
                        let current = weights[criterion.id.uuidString] ?? criterion.weight
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(criterion.displayName)
                                    .font(POPFont.calloutMedium)
                                    .foregroundStyle(POPColor.ink)
                                    .lineLimit(1)
                                Spacer()
                                Text(POPFormat.percent(current))
                                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(POPColor.ink)
                                    .monospacedDigit()
                                if abs(current - criterion.weight) > 0.01 {
                                    Text("(was \(POPFormat.percent(criterion.weight)))")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(POPColor.brandOrange)
                                }
                            }
                            Slider(
                                value: Binding(
                                    get: { current },
                                    set: { weights[criterion.id.uuidString] = $0.rounded(toPlaces: 0) }
                                ),
                                in: 0...100,
                                step: 1
                            )
                            .tint(POPColor.brandOrange)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.surfaceMuted))
                    }

                    POPTextButton(title: "Reset weights to baseline", icon: "arrow.uturn.backward") {
                        weights = [:]
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    POPSectionHeader(title: "Limits", icon: "gauge.with.dots.needle.bottom.50percent")
                    POPNumberField(
                        label: "Budget Limit",
                        text: $budgetText,
                        hint: "Options priced above this are treated as failing a constraint in this scenario.",
                        errorText: budgetError,
                        prefix: POPFormat.currencySymbol(for: decision.currencyCode)
                    )
                    POPDateField(label: "Deadline", date: $deadline,
                                 hint: "Recorded for context — it does not change any score by itself.")
                }

                if !decision.comparableOptions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        POPSectionHeader(title: "Excluded Options", subtitle: "Options left out of this scenario entirely.", icon: "minus.circle")
                        ForEach(decision.comparableOptions) { option in
                            Button(action: {
                                Haptics.selection()
                                if excluded.contains(option.id) {
                                    excluded.remove(option.id)
                                } else {
                                    excluded.insert(option.id)
                                }
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: excluded.contains(option.id) ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(excluded.contains(option.id) ? POPColor.danger : POPColor.hairline)
                                    Text(option.displayName)
                                        .font(POPFont.calloutMedium)
                                        .foregroundStyle(excluded.contains(option.id) ? POPColor.inkTertiary : POPColor.ink)
                                        .strikethrough(excluded.contains(option.id), color: POPColor.inkTertiary)
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

                POPTextEditor(
                    label: "Additional Constraint",
                    text: $additionalConstraint,
                    placeholder: "Anything else that would be true in this scenario.",
                    hint: "Recorded as a note — it is not evaluated automatically.",
                    characterLimit: 300,
                    minHeight: 78
                )

                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 8)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationTitle(isNew ? "New Scenario" : "Edit Scenario")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(POPColor.inkSecondary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save Scenario") { save() }
                    .font(POPFont.bodyMedium)
                    .foregroundStyle(isValid ? POPColor.brandOrange : POPColor.inkTertiary)
            }
        }
    }

    private func hydrate() {
        guard !loaded else { return }
        loaded = true
        name = scenario.name
        budgetText = POPFormat.editableNumber(scenario.budgetLimit)
        deadline = scenario.deadline
        weights = scenario.weightOverrides
        excluded = Set(scenario.excludedOptionIDs)
        additionalConstraint = scenario.additionalConstraint
    }

    private func save() {
        guard isValid else {
            showValidation = true
            Haptics.error()
            return
        }
        var updated = scenario
        updated.name = name.popTrimmed
        updated.budgetLimit = POPFormat.parseNumber(budgetText)
        updated.deadline = deadline
        updated.weightOverrides = weights
        updated.excludedOptionIDs = Array(excluded)
        updated.additionalConstraint = additionalConstraint.popTrimmed

        if isNew {
            store.send(.addScenario(decisionID: decisionID, scenario: updated))
        } else {
            store.send(.updateScenario(decisionID: decisionID, scenario: updated))
        }
        dismiss()
    }
}
