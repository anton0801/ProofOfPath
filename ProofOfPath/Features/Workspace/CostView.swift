//
//  CostView.swift
//  ProofOfPath
//
//  Total Cost View. Periods are always converted before anything is added.
//

import SwiftUI

struct CostView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID

    @State private var editingOptionID: UUID?

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
        let breakdowns = CostEngine.breakdowns(for: decision)
        let lowest = CostEngine.lowestTotal(in: breakdowns)

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                CoinStrikeFeatureBanner(asset: "CoinStrikeCost")
                horizonCard(decision)

                if breakdowns.isEmpty {
                    POPEmptyState(
                        icon: "banknote",
                        title: "No options to cost",
                        message: "Add options with a price to compare the full cost of ownership."
                    )
                    .popCard(padding: 6)
                } else {
                    if breakdowns.allSatisfy({ !$0.hasAnyData }) {
                        POPBanner(
                            kind: .warning,
                            message: "No cost data recorded yet.",
                            detail: "Add an estimated cost to each option so totals can be calculated. Nothing is estimated for you."
                        )
                    }

                    ForEach(breakdowns) { breakdown in
                        costCard(breakdown, decision: decision, isLowest: lowest?.optionID == breakdown.optionID)
                    }

                    assumptionsCard
                }

                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 10)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationTitle("Total Cost View")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { editingOptionID.map { IdentifiableUUID(id: $0) } },
            set: { editingOptionID = $0?.id }
        )) { wrapper in
            CostAssumptionsSheet(decisionID: decisionID, optionID: wrapper.id)
        }
    }

    // MARK: Horizon

    private func horizonCard(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(
                title: "Time Period",
                subtitle: "Totals below cover this whole period. Monthly and yearly figures are converted, never mixed.",
                icon: "calendar"
            )
            POPInlineSegments(
                options: CostHorizon.allCases,
                selection: Binding(
                    get: { decision.costHorizon },
                    set: { store.send(.setCostHorizon(decisionID: decisionID, horizon: $0)) }
                ),
                titleFor: { $0.title }
            )
        }
        .popCard()
    }

    // MARK: Cost card

    private func costCard(_ breakdown: CostBreakdown, decision: Decision, isLowest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(breakdown.optionName)
                        .font(POPFont.cardTitle)
                        .foregroundStyle(POPColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if isLowest && breakdown.hasAnyData {
                        POPBadge(text: "Lowest total", icon: "arrow.down.circle.fill",
                                 color: POPColor.success, soft: POPColor.successSoft, compact: true)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(breakdown.formattedTotal)
                        .font(POPFont.numeric)
                        .foregroundStyle(breakdown.hasAnyData ? POPColor.ink : POPColor.inkTertiary)
                        .monospacedDigit()
                    Text("Estimated Total")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(POPColor.inkTertiary)
                }
            }

            if breakdown.hasAnyData {
                VStack(alignment: .leading, spacing: 8) {
                    costLine(label: "Initial Cost",
                             value: breakdown.initialCost,
                             currency: decision.currencyCode,
                             placeholder: "Not recorded")
                    costLine(label: "Required Extras",
                             value: breakdown.requiredExtras,
                             currency: decision.currencyCode)
                    POPDivider()
                    costLine(label: "Upfront Cost",
                             value: breakdown.upfront,
                             currency: decision.currencyCode,
                             emphasised: true)

                    if let recurring = breakdown.recurringCost, recurring > 0 {
                        POPDivider()
                        HStack {
                            Text("Recurring Cost")
                                .font(POPFont.caption)
                                .foregroundStyle(POPColor.inkSecondary)
                            Spacer()
                            Text("\(POPFormat.money(recurring, currencyCode: decision.currencyCode)) \(breakdown.recurringPeriod.title.lowercased())")
                                .font(POPFont.bodyMedium)
                                .foregroundStyle(POPColor.ink)
                        }
                        if breakdown.recurringPeriod != .yearly {
                            HStack {
                                Text("→ converted to per year (× \(POPFormat.decimal(breakdown.recurringPeriod.occurrencesPerYear, maxFractionDigits: 0)))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(POPColor.inkTertiary)
                                Spacer()
                                Text(POPFormat.money(breakdown.recurringPerYear, currencyCode: decision.currencyCode))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(POPColor.inkSecondary)
                                    .monospacedDigit()
                            }
                        }
                    }

                    costLine(label: "Estimated Maintenance (per year)",
                             value: breakdown.maintenancePerYear,
                             currency: decision.currencyCode)
                    costLine(label: "Potential Savings (per year)",
                             value: breakdown.savingsPerYear,
                             currency: decision.currencyCode,
                             isNegative: true)

                    POPDivider()
                    costLine(label: "Ongoing Cost (per year)",
                             value: breakdown.ongoingPerYear,
                             currency: decision.currencyCode,
                             emphasised: true)
                    costLine(label: "Ongoing over \(breakdown.horizon.title)",
                             value: breakdown.ongoingOverHorizon,
                             currency: decision.currencyCode)

                    POPDivider()
                    HStack {
                        Text("Estimated Total over \(breakdown.horizon.title)")
                            .font(POPFont.calloutMedium)
                            .foregroundStyle(POPColor.ink)
                        Spacer()
                        Text(POPFormat.money(breakdown.estimatedTotal, currencyCode: decision.currencyCode))
                            .font(POPFont.numeric)
                            .foregroundStyle(POPColor.ink)
                            .monospacedDigit()
                    }
                }
                .padding(11)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(POPColor.surfaceMuted))

                if breakdown.isMissingInitialCost {
                    POPInlineNote(
                        text: "No initial cost recorded, so this total only covers ongoing costs.",
                        icon: "exclamationmark.circle",
                        tint: POPColor.brandOrange
                    )
                }
            } else {
                POPInlineNote(text: "No cost figures recorded for this option yet.")
            }

            if let option = decision.option(id: breakdown.optionID), !option.cost.assumptions.popIsBlank {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cost Assumptions")
                        .font(POPFont.micro)
                        .foregroundStyle(POPColor.inkTertiary)
                    Text(option.cost.assumptions)
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            POPSecondaryButton(title: "Edit Assumptions", icon: "square.and.pencil") {
                editingOptionID = breakdown.optionID
            }
            .popRequiresConnection()
        }
        .popCard()
    }

    private func costLine(
        label: String,
        value: Double?,
        currency: String,
        placeholder: String = "—",
        emphasised: Bool = false,
        isNegative: Bool = false
    ) -> some View {
        HStack {
            Text(label)
                .font(emphasised ? POPFont.calloutMedium : POPFont.caption)
                .foregroundStyle(emphasised ? POPColor.ink : POPColor.inkSecondary)
            Spacer()
            Text(value.map { "\(isNegative && $0 > 0 ? "−" : "")\(POPFormat.money($0, currencyCode: currency))" } ?? placeholder)
                .font(emphasised ? POPFont.bodyMedium : POPFont.callout)
                .foregroundStyle(value == nil ? POPColor.inkTertiary : (isNegative ? POPColor.success : POPColor.ink))
                .monospacedDigit()
        }
    }

    private var assumptionsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            POPSectionHeader(title: "How the total is calculated", icon: "function")
            VStack(alignment: .leading, spacing: 6) {
                formulaLine("Upfront = Initial Cost + Required Extras")
                formulaLine("Ongoing per year = Recurring × times per year + Maintenance − Savings")
                formulaLine("Estimated Total = Upfront + Ongoing per year × years in the period")
            }
            POPInlineNote(text: "Maintenance and savings are entered per year. Recurring cost keeps its own period and is converted before being added.")
        }
        .popCard()
    }

    private func formulaLine(_ text: String) -> some View {
        Text(text)
            .font(POPFont.mono)
            .foregroundStyle(POPColor.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(POPColor.surfaceMuted))
    }
}

// MARK: - Wrapper for sheet(item:)

struct IdentifiableUUID: Identifiable, Hashable {
    let id: UUID
}

// MARK: - Cost assumptions editor

struct CostAssumptionsSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var submission = POPSubmission()

    let decisionID: UUID
    let optionID: UUID

    @State private var initialCostText = ""
    @State private var recurringText = ""
    @State private var recurringPeriod: CostPeriod = .monthly
    @State private var extrasText = ""
    @State private var maintenanceText = ""
    @State private var savingsText = ""
    @State private var assumptions = ""
    @State private var loaded = false
    @State private var showValidation = false

    private var decision: Decision? { store.state.decision(id: decisionID) }
    private var option: DecisionOption? { decision?.option(id: optionID) }
    private var currency: String { decision?.currencyCode ?? "USD" }

    private func error(_ text: String, label: String) -> String? {
        guard !text.popIsBlank else { return nil }
        guard let value = POPFormat.parseNumber(text) else { return "\(label) must be a number." }
        return value < 0 ? "\(label) cannot be negative." : nil
    }

    private var isValid: Bool {
        error(initialCostText, label: "Initial cost") == nil
            && error(recurringText, label: "Recurring cost") == nil
            && error(extrasText, label: "Required extras") == nil
            && error(maintenanceText, label: "Maintenance") == nil
            && error(savingsText, label: "Savings") == nil
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                    if let option {
                        Text(option.displayName)
                            .font(POPFont.title)
                            .foregroundStyle(POPColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    POPNumberField(
                        label: "Initial Cost",
                        text: $initialCostText,
                        errorText: showValidation ? error(initialCostText, label: "Initial cost") : nil,
                        prefix: POPFormat.currencySymbol(for: currency)
                    )

                    HStack(alignment: .top, spacing: 10) {
                        POPNumberField(
                            label: "Recurring Cost",
                            text: $recurringText,
                            errorText: showValidation ? error(recurringText, label: "Recurring cost") : nil,
                            prefix: POPFormat.currencySymbol(for: currency)
                        )
                        POPMenuPicker(
                            label: "Period",
                            options: CostPeriod.allCases,
                            selection: $recurringPeriod,
                            titleFor: { $0.title }
                        )
                    }

                    POPNumberField(
                        label: "Required Extras",
                        text: $extrasText,
                        hint: "One-off things you must also buy for it to work.",
                        errorText: showValidation ? error(extrasText, label: "Required extras") : nil,
                        prefix: POPFormat.currencySymbol(for: currency)
                    )

                    POPNumberField(
                        label: "Estimated Maintenance",
                        text: $maintenanceText,
                        hint: "Per year.",
                        errorText: showValidation ? error(maintenanceText, label: "Maintenance") : nil,
                        prefix: POPFormat.currencySymbol(for: currency),
                        suffix: "/yr"
                    )

                    POPNumberField(
                        label: "Potential Savings",
                        text: $savingsText,
                        hint: "Per year. Subtracted from the ongoing cost.",
                        errorText: showValidation ? error(savingsText, label: "Savings") : nil,
                        prefix: POPFormat.currencySymbol(for: currency),
                        suffix: "/yr"
                    )

                    POPTextEditor(
                        label: "Cost Assumptions",
                        text: $assumptions,
                        placeholder: "What are these numbers based on? Which prices did you use?",
                        hint: "Assumptions written now save you from re-deriving them in six months.",
                        characterLimit: 600,
                        minHeight: 100
                    )

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 8)
            }
            .background(POPColor.canvas.ignoresSafeArea())
            .navigationTitle("Cost Assumptions")
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
        guard !loaded, let option else { return }
        loaded = true
        initialCostText = POPFormat.editableNumber(option.estimatedCost)
        recurringText = POPFormat.editableNumber(option.cost.recurringCost)
        recurringPeriod = option.cost.recurringPeriod
        extrasText = POPFormat.editableNumber(option.cost.requiredExtras)
        maintenanceText = POPFormat.editableNumber(option.cost.estimatedMaintenance)
        savingsText = POPFormat.editableNumber(option.cost.potentialSavings)
        assumptions = option.cost.assumptions
    }

    private func save() {
        guard isValid, var option else {
            showValidation = true
            Haptics.error()
            return
        }
        option.estimatedCost = POPFormat.parseNumber(initialCostText)
        option.cost.recurringCost = POPFormat.parseNumber(recurringText)
        option.cost.recurringPeriod = recurringPeriod
        option.cost.requiredExtras = POPFormat.parseNumber(extrasText)
        option.cost.estimatedMaintenance = POPFormat.parseNumber(maintenanceText)
        option.cost.potentialSavings = POPFormat.parseNumber(savingsText)
        option.cost.assumptions = assumptions.popTrimmed
        submission.run(store, .updateOption(decisionID: decisionID, option: option)) { dismiss() }
    }
}
