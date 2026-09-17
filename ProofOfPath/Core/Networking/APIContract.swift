//
//  APIContract.swift
//  ProofOfPath
//
//  Keeps a proposed state inside what the server accepts.
//

import Foundation

extension AppData {

    /// The server checks every reference and every length. The reducer already
    /// cleans references when it deletes something, so this is a safety net:
    /// a dangling id or an over-long name is repaired here instead of making
    /// the whole save fail. The repaired state is what gets committed, so the
    /// app and the server keep agreeing.
    func conformedToAPI() -> AppData {
        var data = self
        let decisionIDs = Set(data.decisions.map(\.id))
        let evidenceIDs = Set(data.evidence.map(\.id))

        data.settings.ownerName = data.settings.ownerName.clamped(to: 255)

        for d in data.decisions.indices {
            var decision = data.decisions[d]
            let criterionIDs = Set(decision.criteria.map(\.id))
            let optionIDs = Set(decision.options.map(\.id))
            let constraintIDs = Set(decision.hardConstraints.map(\.id))
            let riskIDs = Set(decision.risks.map(\.id))

            decision.title = decision.title.clamped(to: 255)
            decision.customCategoryName = decision.customCategoryName.clamped(to: 255)
            decision.owner = decision.owner.clamped(to: 255)
            if let template = decision.templateID, template.count > 64 { decision.templateID = nil }

            for i in decision.hardConstraints.indices {
                decision.hardConstraints[i].title = decision.hardConstraints[i].title.clamped(to: 255)
            }
            for i in decision.criteria.indices {
                decision.criteria[i].name = decision.criteria[i].name.clamped(to: 255)
                decision.criteria[i].targetValue = decision.criteria[i].targetValue.clamped(to: 255)
                decision.criteria[i].minimumAcceptableValue = decision.criteria[i].minimumAcceptableValue.clamped(to: 255)
                decision.criteria[i].weight = min(100, max(0, decision.criteria[i].weight.finiteOrZero))
            }
            for i in decision.options.indices {
                var option = decision.options[i]
                option.name = option.name.clamped(to: 255)
                option.providerOrBrand = option.providerOrBrand.clamped(to: 255)
                option.website = option.website.clamped(to: 2048)
                option.manualConstraintStatus = option.manualConstraintStatus.filter { key, _ in
                    UUID(uuidString: key).map(constraintIDs.contains) ?? false
                }
                var seen = Set<UUID>()
                option.evaluations = option.evaluations.filter { evaluation in
                    criterionIDs.contains(evaluation.criterionID) && seen.insert(evaluation.criterionID).inserted
                }
                for e in option.evaluations.indices {
                    if let rating = option.evaluations[e].rating, !(1...10).contains(rating) {
                        option.evaluations[e].rating = min(10, max(1, rating))
                    }
                }
                decision.options[i] = option
            }
            for i in decision.claims.indices {
                var claim = decision.claims[i]
                claim.claimedBy = claim.claimedBy.clamped(to: 255)
                if let option = claim.optionID, !optionIDs.contains(option) { claim.optionID = nil }
                claim.supportingEvidenceIDs = claim.supportingEvidenceIDs.filter(evidenceIDs.contains).uniqued()
                let supporting = Set(claim.supportingEvidenceIDs)
                claim.contradictingEvidenceIDs = claim.contradictingEvidenceIDs
                    .filter { evidenceIDs.contains($0) && !supporting.contains($0) }
                    .uniqued()
                decision.claims[i] = claim
            }
            for i in decision.risks.indices {
                decision.risks[i].title = decision.risks[i].title.clamped(to: 255)
                if let option = decision.risks[i].optionID, !optionIDs.contains(option) { decision.risks[i].optionID = nil }
            }
            for i in decision.scenarios.indices {
                var scenario = decision.scenarios[i]
                scenario.name = scenario.name.clamped(to: 255)
                scenario.weightOverrides = scenario.weightOverrides
                    .filter { key, _ in UUID(uuidString: key).map(criterionIDs.contains) ?? false }
                    .mapValues { min(100, max(0, $0.finiteOrZero)) }
                scenario.excludedOptionIDs = scenario.excludedOptionIDs.filter(optionIDs.contains).uniqued()
                decision.scenarios[i] = scenario
            }
            for i in decision.followUpTasks.indices {
                decision.followUpTasks[i].title = decision.followUpTasks[i].title.clamped(to: 255)
                if let key = decision.followUpTasks[i].relatedQuestionKey, key.count > 255 {
                    decision.followUpTasks[i].relatedQuestionKey = nil
                }
            }
            if var final = decision.finalDecision {
                if let selected = final.selectedOptionID, !optionIDs.contains(selected) { final.selectedOptionID = nil }
                final.keyEvidenceIDs = final.keyEvidenceIDs.filter(evidenceIDs.contains).uniqued()
                final.confidence = min(5, max(1, final.confidence))
                decision.finalDecision = final
            }
            for i in decision.snapshots.indices {
                decision.snapshots[i].reason = decision.snapshots[i].reason.clamped(to: 255)
                decision.snapshots[i].label = decision.snapshots[i].label.clamped(to: 255)
                decision.snapshots[i].selectedOptionName = decision.snapshots[i].selectedOptionName.clamped(to: 255)
            }
            if var review = decision.outcomeReview {
                review.occurredRiskIDs = review.occurredRiskIDs.filter(riskIDs.contains).uniqued()
                decision.outcomeReview = review
            }
            data.decisions[d] = decision
        }

        for i in data.evidence.indices {
            var item = data.evidence[i]
            item.title = item.title.clamped(to: 255)
            if let decisionID = item.decisionID, !decisionIDs.contains(decisionID) {
                item.decisionID = nil
            }
            let decision = data.decisions.first { $0.id == item.decisionID }
            let optionIDs = Set(decision?.options.map(\.id) ?? [])
            let criterionIDs = Set(decision?.criteria.map(\.id) ?? [])
            item.links = item.links.compactMap { link in
                var link = link
                if let option = link.optionID, !optionIDs.contains(option) { link.optionID = nil }
                if let criterion = link.criterionID, !criterionIDs.contains(criterion) { link.criterionID = nil }
                return link.isEmpty ? nil : link
            }
            if var attachment = item.attachment {
                attachment.originalName = attachment.originalName.clamped(to: 255)
                item.attachment = attachment
            }
            data.evidence[i] = item
        }
        return data
    }
}

private extension String {
    /// The server counts Unicode code points (MySQL characters), which an
    /// emoji sequence has more of than it has visible characters. Cutting
    /// between whole characters keeps the text valid.
    func clamped(to limit: Int) -> String {
        guard unicodeScalars.count > limit else { return self }
        var result = ""
        var used = 0
        for character in self {
            let size = character.unicodeScalars.count
            if used + size > limit { break }
            result.append(character)
            used += size
        }
        return result
    }
}

private extension Double {
    var finiteOrZero: Double { isFinite ? self : 0 }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
