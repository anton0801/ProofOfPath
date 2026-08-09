//
//  CostEngine.swift
//  ProofOfPath
//
//  Total cost of ownership. Periods are always converted before they are added
//  so monthly and yearly figures are never mixed.
//

import Foundation

struct CostBreakdown: Identifiable, Hashable {
    var id: UUID { optionID }
    let optionID: UUID
    let optionName: String

    let initialCost: Double?
    let requiredExtras: Double?
    /// Recurring cost exactly as the user entered it, with its period.
    let recurringCost: Double?
    let recurringPeriod: CostPeriod
    let maintenancePerYear: Double?
    let savingsPerYear: Double?

    let horizon: CostHorizon
    let currencyCode: String

    var upfront: Double { (initialCost ?? 0) + (requiredExtras ?? 0) }

    var recurringPerYear: Double {
        (recurringCost ?? 0) * recurringPeriod.occurrencesPerYear
    }

    var ongoingPerYear: Double {
        recurringPerYear + (maintenancePerYear ?? 0) - (savingsPerYear ?? 0)
    }

    var ongoingOverHorizon: Double { ongoingPerYear * horizon.years }

    var estimatedTotal: Double { upfront + ongoingOverHorizon }

    /// True when nothing at all has been entered — we must not show a total of 0
    /// as if it were a real figure.
    var hasAnyData: Bool {
        initialCost != nil || requiredExtras != nil || recurringCost != nil
            || maintenancePerYear != nil || savingsPerYear != nil
    }

    var isMissingInitialCost: Bool { initialCost == nil }

    var formattedTotal: String {
        hasAnyData ? POPFormat.money(estimatedTotal, currencyCode: currencyCode) : "—"
    }
}

enum CostEngine {

    static func breakdown(for option: DecisionOption, decision: Decision) -> CostBreakdown {
        CostBreakdown(
            optionID: option.id,
            optionName: option.displayName,
            initialCost: option.estimatedCost,
            requiredExtras: option.cost.requiredExtras,
            recurringCost: option.cost.recurringCost,
            recurringPeriod: option.cost.recurringPeriod,
            maintenancePerYear: option.cost.estimatedMaintenance,
            savingsPerYear: option.cost.potentialSavings,
            horizon: decision.costHorizon,
            currencyCode: decision.currencyCode
        )
    }

    static func breakdowns(for decision: Decision) -> [CostBreakdown] {
        decision.comparableOptions.map { breakdown(for: $0, decision: decision) }
    }

    /// The cheapest total among options that have enough data to compare.
    static func lowestTotal(in breakdowns: [CostBreakdown]) -> CostBreakdown? {
        breakdowns.filter(\.hasAnyData).min { $0.estimatedTotal < $1.estimatedTotal }
    }

    static func highestTotal(in breakdowns: [CostBreakdown]) -> CostBreakdown? {
        breakdowns.filter(\.hasAnyData).max { $0.estimatedTotal < $1.estimatedTotal }
    }

    /// Whether an option's initial cost sits inside the decision's budget range.
    enum BudgetFit: String, Hashable {
        case inside
        case below
        case above
        case unknown
        case noBudgetSet

        var title: String {
            switch self {
            case .inside: return "Within budget"
            case .below: return "Below budget range"
            case .above: return "Over budget"
            case .unknown: return "No price recorded"
            case .noBudgetSet: return "No budget set"
            }
        }
    }

    static func budgetFit(for option: DecisionOption, decision: Decision) -> BudgetFit {
        guard decision.budgetMin != nil || decision.budgetMax != nil else { return .noBudgetSet }
        guard let cost = option.estimatedCost else { return .unknown }
        if let maxValue = decision.budgetMax, cost > maxValue + 0.0001 { return .above }
        if let minValue = decision.budgetMin, cost < minValue - 0.0001 { return .below }
        return .inside
    }
}
