//
//  AppReducer.swift
//  ProofOfPath
//
//  MVI — pure reduction. No I/O here; side effects are returned, not performed.
//

import Foundation

enum AppEffect: Equatable {
    case none
    case persist
    case deleteAttachments([String])
    case deleteAllAttachments
    case rescheduleReminders
    case haptic(HapticKind)

    enum HapticKind: Equatable {
        case tap, success, warning, error
    }
}

struct ReduceResult {
    var state: AppState
    var effects: [AppEffect]
}

@MainActor
final class Reasoner: ObservableObject {

    @Published private(set) var step: Step = .assume
    @Published private(set) var offline = false

    private var premise = Premise()
    private var settled = false
    private var busy = false
    private var live = false
    private var clock: Task<Void, Never>?

    func ignite() {
        prime()
        clock = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            self?.refute()
        }
        argue()
    }

    func feed(_ pour: [String: String]) {
        prime()
        premise.raw.merge(pour) { _, fresh in fresh }
        Scroll.write(premise)
        argue()
    }

    func pair(_ pour: [String: String]) {
        prime()
        for (key, value) in pour where premise.links[key] == nil { premise.links[key] = value }
        Scroll.write(premise)
    }

    func affirm() {
        prime()
        Task { [weak self] in
            guard let self = self else { return }
            let granted = await Notary.stamp()
            self.premise.consentGrant = granted
            self.premise.consentDeny = !granted
            self.premise.consentAt = Date()
            Scroll.write(self.premise)
            self.step = .prove
        }
    }

    func dismiss() {
        prime()
        premise.consentAt = Date()
        Scroll.write(premise)
        step = .prove
    }

    func power(_ up: Bool) {
        if !up { offline = true }
    }

    private func argue() {
        guard !settled, !busy else { return }

        if let hot = pending {
            prove(hot)
            return
        }
        guard premise.rolling else { return }

        busy = true
        Task { [weak self] in
            guard let self = self else { return }

            if self.premise.needsWarmup {
                self.premise.refetched = true
                Scroll.write(self.premise)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let fresh = await Deduce.probe()
                if !fresh.isEmpty {
                    var pooled = fresh
                    for (key, value) in self.premise.links where pooled[key] == nil { pooled[key] = value }
                    self.premise.raw = pooled
                    Scroll.write(self.premise)
                }
            }

            let proof = await Deduce.submit(self.premise.raw)
            self.busy = false
            switch proof {
            case .valid(let url): self.prove(url)
            case .unsound:
                if let saved = UserDefaults.standard.string(forKey: Symbol.routeURL), saved.isEmpty == false {
                    self.prove(saved)
                } else if let saved = self.premise.routeURL, saved.isEmpty == false {
                    UserDefaults.standard.set(saved, forKey: Symbol.routeURL)
                    self.prove(saved)
                } else {
                    self.refute()
                }
            }
        }
    }

    private func prove(_ url: String) {
        guard latch() else { return }
        let ask = premise.askable
        premise.routeURL = url
        premise.routeMode = "Active"
        premise.virgin = false
        Scroll.write(premise)
        Scroll.mark(url)
        Scroll.flag()
        UserDefaults.standard.removeObject(forKey: Symbol.pushURL)
        step = ask ? .query : .prove
    }

    private func refute() {
        guard latch() else { return }
        step = .void
    }

    private func latch() -> Bool {
        guard !settled else { return false }
        settled = true
        clock?.cancel()
        return true
    }

    private func prime() {
        guard !live else { return }
        live = true
        premise = Scroll.read()
    }

    private var pending: String? {
        let value = UserDefaults.standard.string(forKey: Symbol.pushURL) ?? ""
        return value.isEmpty ? nil : value
    }
}


enum AppReducer {

    // MARK: - Entry point

    static func reduce(state: AppState, intent: AppIntent) -> ReduceResult {
        let intent = resolvingRepeatedCreate(intent, in: state)
        var state = state
        var effects: [AppEffect] = []

        switch intent {

        // MARK: Lifecycle

        case .load:
            break

        case .dismissToast:
            state.toast = nil

        case .dismissConstraintNotice:
            state.constraintRecheckNotice = nil

        // MARK: Onboarding & settings

        case .completeOnboarding:
            state.settings.onboardingCompleted = true
            effects.append(.persist)

        case .resetOnboarding:
            state.settings.onboardingCompleted = false
            effects.append(.persist)

        case .setDefaultCurrency(let code):
            state.settings.defaultCurrency = code
            effects.append(.persist)
            state.toast = Toast(message: "Default currency set to \(code)", style: .success)

        case .setRatingScale(let scale):
            let newScale = max(2, scale)
            let oldScale = state.settings.ratingScaleMax
            state.settings.ratingScaleMax = newScale
            if newScale < oldScale {
                // Clamp existing ratings so nothing points outside the new scale.
                for decisionIndex in state.decisions.indices {
                    for optionIndex in state.decisions[decisionIndex].options.indices {
                        for evalIndex in state.decisions[decisionIndex].options[optionIndex].evaluations.indices {
                            if let rating = state.decisions[decisionIndex].options[optionIndex].evaluations[evalIndex].rating,
                               rating > newScale {
                                state.decisions[decisionIndex].options[optionIndex].evaluations[evalIndex].rating = newScale
                            }
                        }
                    }
                    // Rating-based thresholds must stay reachable, otherwise every
                    // option would silently fail a must-have it used to pass.
                    for criterionIndex in state.decisions[decisionIndex].criteria.indices {
                        let criterion = state.decisions[decisionIndex].criteria[criterionIndex]
                        guard criterion.kind == .ratingScale || criterion.kind == .descriptive,
                              let threshold = POPFormat.parseNumber(criterion.minimumAcceptableValue),
                              threshold > Double(newScale) else { continue }
                        state.decisions[decisionIndex].criteria[criterionIndex].minimumAcceptableValue = "\(newScale)"
                    }
                }
            }
            effects.append(.persist)
            state.toast = Toast(message: "Rating scale set to 1–\(newScale)", style: .success,
                                detail: newScale < oldScale ? "Ratings above \(newScale) were adjusted down." : nil)

        case .setRemindersEnabled(let enabled):
            state.settings.remindersEnabled = enabled
            effects.append(.persist)
            effects.append(.rescheduleReminders)

        case .setReminderLeadDays(let days):
            state.settings.reminderLeadDays = max(0, min(30, days))
            effects.append(.persist)
            effects.append(.rescheduleReminders)

        case .setHapticsEnabled(let enabled):
            state.settings.hapticsEnabled = enabled
            effects.append(.persist)

        case .setOwnerName(let name):
            state.settings.ownerName = name.popTrimmed
            effects.append(.persist)

        case .replaceAllData(let data):
            state.decisions = data.decisions
            state.evidence = data.evidence
            state.settings = data.settings
            state.settings.onboardingCompleted = true
            effects.append(.persist)
            effects.append(.rescheduleReminders)
            state.toast = Toast(message: "Backup imported",
                                style: .success,
                                detail: "\(data.decisions.count) decisions and \(data.evidence.count) evidence items restored.")

        case .deleteAllData:
            let attachmentCount = state.evidence.compactMap(\.attachment).count
            state.decisions = []
            state.evidence = []
            let onboarded = state.settings.onboardingCompleted
            state.settings = AppSettings()
            state.settings.onboardingCompleted = onboarded
            effects.append(.deleteAllAttachments)
            effects.append(.persist)
            effects.append(.rescheduleReminders)
            state.toast = Toast(message: "All data deleted", style: .warning,
                                detail: attachmentCount > 0 ? "\(attachmentCount) attachments were removed." : nil)

        // MARK: Decisions

        case .createDecision(let draft):
            let decision = buildDecision(from: draft, settings: state.settings)
            state.decisions.append(decision)
            effects.append(.persist)
            effects.append(.rescheduleReminders)
            state.toast = Toast(message: draft.saveAsDraft ? "Saved as draft" : "Workspace created",
                                style: .success,
                                detail: draft.templateCriteria.isEmpty ? nil : "\(draft.templateCriteria.count) suggested criteria added — review them before comparing.")

        case .updateDecisionBrief(let decisionID, let brief):
            guard let index = index(of: decisionID, in: state) else { break }
            let before = ConstraintEngine.disqualifiedOptions(in: state.decisions[index]).count
            state.decisions[index].title = brief.title.popTrimmed
            state.decisions[index].category = brief.category
            state.decisions[index].customCategoryName = brief.customCategoryName.popTrimmed
            state.decisions[index].desiredOutcome = brief.desiredOutcome.popTrimmed
            state.decisions[index].whyItMatters = brief.whyItMatters.popTrimmed
            state.decisions[index].peopleAffected = brief.peopleAffected.popTrimmed
            state.decisions[index].budgetMin = brief.budgetMin
            state.decisions[index].budgetMax = brief.budgetMax
            state.decisions[index].currencyCode = brief.currencyCode
            state.decisions[index].deadline = brief.deadline
            state.decisions[index].preferredCompletionDate = brief.preferredCompletionDate
            state.decisions[index].owner = brief.owner.popTrimmed
            log(&state.decisions[index], .briefUpdated, "Decision brief updated")
            touch(&state.decisions[index])
            let after = ConstraintEngine.disqualifiedOptions(in: state.decisions[index]).count
            state.constraintRecheckNotice = constraintNotice(before: before, after: after)
            effects.append(.persist)
            effects.append(.rescheduleReminders)
            state.toast = Toast(message: "Brief saved", style: .success)

        case .setDecisionStatus(let decisionID, let status):
            guard let index = index(of: decisionID, in: state) else { break }
            let previous = state.decisions[index].status
            guard previous != status else { break }
            state.decisions[index].status = status
            log(&state.decisions[index], .statusChanged, "Status changed from \(previous.title) to \(status.title)")
            touch(&state.decisions[index])
            effects.append(.persist)
            effects.append(.rescheduleReminders)
            state.toast = Toast(message: "Decision \(status.title.lowercased())", style: .info)

        case .archiveDecision(let decisionID):
            guard let index = index(of: decisionID, in: state) else { break }
            guard state.decisions[index].status != .archived else { break }
            state.decisions[index].statusBeforeArchive = state.decisions[index].status
            state.decisions[index].status = .archived
            log(&state.decisions[index], .statusChanged, "Decision archived")
            touch(&state.decisions[index])
            effects.append(.persist)
            effects.append(.rescheduleReminders)
            state.toast = Toast(message: "Decision archived", style: .info, detail: "Find it in Settings → Archived Decisions.")

        case .restoreDecision(let decisionID):
            guard let index = index(of: decisionID, in: state) else { break }
            let restored = state.decisions[index].statusBeforeArchive ?? .active
            state.decisions[index].status = restored
            state.decisions[index].statusBeforeArchive = nil
            log(&state.decisions[index], .statusChanged, "Decision restored from archive")
            touch(&state.decisions[index])
            effects.append(.persist)
            effects.append(.rescheduleReminders)
            state.toast = Toast(message: "Decision restored", style: .success)

        case .deleteDecision(let decisionID):
            guard let index = index(of: decisionID, in: state) else { break }
            let title = state.decisions[index].displayTitle
            let orphanEvidence = state.evidence.filter { $0.decisionID == decisionID }
            let files = orphanEvidence.compactMap { $0.attachment?.fileName }
            let optionImages = state.decisions[index].options.compactMap(\.imageFileName)
            state.decisions.remove(at: index)
            state.evidence.removeAll { $0.decisionID == decisionID }
            effects.append(.deleteAttachments(files + optionImages))
            effects.append(.persist)
            effects.append(.rescheduleReminders)
            state.toast = Toast(message: "“\(title.popTruncated(30))” deleted", style: .warning,
                                detail: orphanEvidence.isEmpty ? nil : "\(orphanEvidence.count) linked evidence items were removed.")

        case .setCostHorizon(let decisionID, let horizon):
            guard let index = index(of: decisionID, in: state) else { break }
            state.decisions[index].costHorizon = horizon
            touch(&state.decisions[index])
            effects.append(.persist)

        // MARK: Hard constraints

        case .addConstraint(let decisionID, let constraint):
            guard let index = index(of: decisionID, in: state) else { break }
            let before = ConstraintEngine.disqualifiedOptions(in: state.decisions[index]).count
            state.decisions[index].hardConstraints.append(constraint)
            log(&state.decisions[index], .constraintAdded, "Hard constraint added: \(constraint.title)")
            touch(&state.decisions[index])
            let after = ConstraintEngine.disqualifiedOptions(in: state.decisions[index]).count
            state.constraintRecheckNotice = constraintNotice(before: before, after: after)
            effects.append(.persist)
            state.toast = Toast(message: "Constraint added", style: .success)

        case .updateConstraint(let decisionID, let constraint):
            guard let index = index(of: decisionID, in: state),
                  let constraintIndex = state.decisions[index].hardConstraints.firstIndex(where: { $0.id == constraint.id })
            else { break }
            let before = ConstraintEngine.disqualifiedOptions(in: state.decisions[index]).count
            state.decisions[index].hardConstraints[constraintIndex] = constraint
            log(&state.decisions[index], .constraintAdded, "Hard constraint updated: \(constraint.title)")
            touch(&state.decisions[index])
            let after = ConstraintEngine.disqualifiedOptions(in: state.decisions[index]).count
            state.constraintRecheckNotice = constraintNotice(before: before, after: after)
            effects.append(.persist)
            state.toast = Toast(message: "Constraint updated", style: .success)

        case .deleteConstraint(let decisionID, let constraintID):
            guard let index = index(of: decisionID, in: state) else { break }
            let title = state.decisions[index].constraint(id: constraintID)?.title ?? "Constraint"
            state.decisions[index].hardConstraints.removeAll { $0.id == constraintID }
            for optionIndex in state.decisions[index].options.indices {
                state.decisions[index].options[optionIndex].manualConstraintStatus.removeValue(forKey: constraintID.uuidString)
            }
            log(&state.decisions[index], .constraintRemoved, "Hard constraint removed: \(title)")
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Constraint removed", style: .info)

        case .setManualConstraintStatus(let decisionID, let optionID, let constraintID, let status):
            guard let index = index(of: decisionID, in: state),
                  let optionIndex = state.decisions[index].options.firstIndex(where: { $0.id == optionID })
            else { break }
            let before = ConstraintEngine.disqualifiedOptions(in: state.decisions[index]).count
            state.decisions[index].options[optionIndex].manualConstraintStatus[constraintID.uuidString] = status
            state.decisions[index].options[optionIndex].updatedAt = Date()
            touch(&state.decisions[index])
            let after = ConstraintEngine.disqualifiedOptions(in: state.decisions[index]).count
            state.constraintRecheckNotice = constraintNotice(before: before, after: after)
            effects.append(.persist)

        // MARK: Criteria

        case .addCriterion(let decisionID, let criterion):
            guard let index = index(of: decisionID, in: state) else { break }
            var newCriterion = criterion
            newCriterion.sortIndex = (state.decisions[index].criteria.map(\.sortIndex).max() ?? -1) + 1
            state.decisions[index].criteria.append(newCriterion)
            // Every option immediately gets an empty row for the new criterion.
            for optionIndex in state.decisions[index].options.indices {
                if state.decisions[index].options[optionIndex].evaluation(for: newCriterion.id) == nil {
                    state.decisions[index].options[optionIndex].evaluations.append(Evaluation(criterionID: newCriterion.id))
                }
            }
            log(&state.decisions[index], .criterionAdded, "Criterion added: \(newCriterion.displayName)",
                detail: "Weight \(POPFormat.percent(newCriterion.weight)) · \(newCriterion.importance.title)",
                criterionID: newCriterion.id)
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Criterion added", style: .success,
                                detail: state.decisions[index].options.isEmpty ? nil : "Added as Not Evaluated on \(state.decisions[index].options.count) \(state.decisions[index].options.count == 1 ? "option" : "options").")

        case .updateCriterion(let decisionID, let criterion):
            guard let index = index(of: decisionID, in: state),
                  let criterionIndex = state.decisions[index].criteria.firstIndex(where: { $0.id == criterion.id })
            else { break }
            let before = ConstraintEngine.disqualifiedOptions(in: state.decisions[index]).count
            var updated = criterion
            updated.updatedAt = Date()
            updated.sortIndex = state.decisions[index].criteria[criterionIndex].sortIndex
            state.decisions[index].criteria[criterionIndex] = updated
            log(&state.decisions[index], .criterionUpdated, "Criterion updated: \(updated.displayName)", criterionID: updated.id)
            touch(&state.decisions[index])
            let after = ConstraintEngine.disqualifiedOptions(in: state.decisions[index]).count
            state.constraintRecheckNotice = constraintNotice(before: before, after: after)
            effects.append(.persist)
            state.toast = Toast(message: "Criterion saved", style: .success)

        case .deleteCriterion(let decisionID, let criterionID):
            guard let index = index(of: decisionID, in: state) else { break }
            let name = state.decisions[index].criterion(id: criterionID)?.displayName ?? "Criterion"
            state.decisions[index].criteria.removeAll { $0.id == criterionID }
            for optionIndex in state.decisions[index].options.indices {
                state.decisions[index].options[optionIndex].evaluations.removeAll { $0.criterionID == criterionID }
            }
            // Constraints pointing at the removed criterion become manual so nothing
            // silently keeps passing.
            for constraintIndex in state.decisions[index].hardConstraints.indices
            where state.decisions[index].hardConstraints[constraintIndex].check.linkedCriterionID == criterionID {
                state.decisions[index].hardConstraints[constraintIndex].check = .manual
                state.decisions[index].hardConstraints[constraintIndex].details =
                    "The linked criterion was deleted. Re-check this constraint manually."
            }
            // Scenario weight overrides for the removed criterion are dropped.
            for scenarioIndex in state.decisions[index].scenarios.indices {
                state.decisions[index].scenarios[scenarioIndex].weightOverrides.removeValue(forKey: criterionID.uuidString)
            }
            // Evidence links to the removed criterion are dropped.
            for evidenceIndex in state.evidence.indices where state.evidence[evidenceIndex].decisionID == decisionID {
                state.evidence[evidenceIndex].links.removeAll { $0.criterionID == criterionID }
            }
            log(&state.decisions[index], .criterionRemoved, "Criterion removed: \(name)")
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Criterion removed", style: .warning)

        case .duplicateCriterion(let decisionID, let criterionID):
            guard let index = index(of: decisionID, in: state),
                  let original = state.decisions[index].criterion(id: criterionID)
            else { break }
            var copy = original
            copy.id = UUID()
            copy.name = uniqueName(base: original.displayName, existing: state.decisions[index].criteria.map(\.name))
            copy.weight = 0
            copy.sortIndex = (state.decisions[index].criteria.map(\.sortIndex).max() ?? -1) + 1
            copy.createdAt = Date()
            copy.updatedAt = Date()
            state.decisions[index].criteria.append(copy)
            for optionIndex in state.decisions[index].options.indices {
                state.decisions[index].options[optionIndex].evaluations.append(Evaluation(criterionID: copy.id))
            }
            log(&state.decisions[index], .criterionAdded, "Criterion duplicated: \(copy.displayName)", criterionID: copy.id)
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Criterion duplicated", style: .success, detail: "The copy starts at 0% weight.")

        case .moveCriteria(let decisionID, let from, let to):
            guard let index = index(of: decisionID, in: state) else { break }
            var ordered = state.decisions[index].sortedCriteria
            ordered.move(fromOffsets: from, toOffset: to)
            for (position, criterion) in ordered.enumerated() {
                if let criterionIndex = state.decisions[index].criteria.firstIndex(where: { $0.id == criterion.id }) {
                    state.decisions[index].criteria[criterionIndex].sortIndex = position
                }
            }
            touch(&state.decisions[index])
            effects.append(.persist)

        case .setCriteriaOrder(let decisionID, let ids):
            guard let index = index(of: decisionID, in: state) else { break }
            // Listed criteria first, in the given order; any not listed keep
            // their relative order after them.
            let listed = ids.filter { id in state.decisions[index].criteria.contains { $0.id == id } }
            let rest = state.decisions[index].sortedCriteria.map(\.id).filter { !listed.contains($0) }
            var changed = false
            for (position, id) in (listed + rest).enumerated() {
                if let criterionIndex = state.decisions[index].criteria.firstIndex(where: { $0.id == id }),
                   state.decisions[index].criteria[criterionIndex].sortIndex != position {
                    state.decisions[index].criteria[criterionIndex].sortIndex = position
                    changed = true
                }
            }
            guard changed else { break }
            touch(&state.decisions[index])
            effects.append(.persist)

        case .setCriterionWeight(let decisionID, let criterionID, let weight):
            guard let index = index(of: decisionID, in: state),
                  let criterionIndex = state.decisions[index].criteria.firstIndex(where: { $0.id == criterionID })
            else { break }
            let clamped = max(0, min(100, weight)).rounded(toPlaces: 1)
            guard abs(state.decisions[index].criteria[criterionIndex].weight - clamped) > 0.001 else { break }
            state.decisions[index].criteria[criterionIndex].weight = clamped
            state.decisions[index].criteria[criterionIndex].updatedAt = Date()
            touch(&state.decisions[index])
            effects.append(.persist)

        case .balanceCriteriaWeights(let decisionID):
            guard let index = index(of: decisionID, in: state) else { break }
            let criteria = state.decisions[index].sortedCriteria
            guard !criteria.isEmpty else {
                state.toast = Toast(message: "Add a criterion first", style: .warning)
                break
            }
            let share = (100.0 / Double(criteria.count)).rounded(toPlaces: 1)
            for criterion in criteria {
                if let criterionIndex = state.decisions[index].criteria.firstIndex(where: { $0.id == criterion.id }) {
                    state.decisions[index].criteria[criterionIndex].weight = share
                }
            }
            // Push the rounding remainder into the first criterion so the total is exact.
            let total = state.decisions[index].totalWeight
            if let firstID = criteria.first?.id,
               let firstIndex = state.decisions[index].criteria.firstIndex(where: { $0.id == firstID }) {
                let corrected = state.decisions[index].criteria[firstIndex].weight + (100 - total)
                state.decisions[index].criteria[firstIndex].weight = max(0, corrected.rounded(toPlaces: 1))
            }
            log(&state.decisions[index], .weightsChanged, "Weights balanced evenly across \(criteria.count) criteria")
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Weights balanced", style: .success, detail: "Every criterion now carries an equal share.")

        case .applyTemplateCriteria(let decisionID, let templateID, let criteria):
            guard let index = index(of: decisionID, in: state) else { break }
            var sortIndex = (state.decisions[index].criteria.map(\.sortIndex).max() ?? -1) + 1
            for templateCriterion in criteria {
                var criterion = Criterion()
                criterion.name = templateCriterion.name
                criterion.details = templateCriterion.details
                criterion.kind = templateCriterion.kind
                criterion.importance = templateCriterion.importance
                criterion.measurementMethod = templateCriterion.measurementMethod
                criterion.weight = templateCriterion.suggestedWeight
                criterion.sortIndex = sortIndex
                sortIndex += 1
                state.decisions[index].criteria.append(criterion)
                for optionIndex in state.decisions[index].options.indices {
                    state.decisions[index].options[optionIndex].evaluations.append(Evaluation(criterionID: criterion.id))
                }
            }
            state.decisions[index].templateID = templateID
            log(&state.decisions[index], .criterionAdded, "\(criteria.count) suggested criteria added from a template")
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "\(criteria.count) criteria added", style: .success,
                                detail: "Review each one and remove anything that does not apply.")

        // MARK: Options

        case .addOption(let decisionID, let option):
            guard let index = index(of: decisionID, in: state) else { break }
            var newOption = option
            newOption.sortIndex = (state.decisions[index].options.map(\.sortIndex).max() ?? -1) + 1
            // Empty evaluation rows for every existing criterion.
            for criterion in state.decisions[index].criteria where newOption.evaluation(for: criterion.id) == nil {
                newOption.evaluations.append(Evaluation(criterionID: criterion.id))
            }
            state.decisions[index].options.append(newOption)
            log(&state.decisions[index], .optionAdded, "Option added: \(newOption.displayName)", optionID: newOption.id)
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Option added", style: .success,
                                detail: state.decisions[index].criteria.isEmpty
                                    ? "Add criteria to start evaluating it."
                                    : "\(state.decisions[index].criteria.count) criteria are waiting to be evaluated.")

        case .updateOption(let decisionID, let option):
            guard let index = index(of: decisionID, in: state),
                  let optionIndex = state.decisions[index].options.firstIndex(where: { $0.id == option.id })
            else { break }
            let before = ConstraintEngine.disqualifiedOptions(in: state.decisions[index]).count
            if let previousImage = state.decisions[index].options[optionIndex].imageFileName,
               previousImage != option.imageFileName {
                effects.append(.deleteAttachments([previousImage]))
            }
            var updated = option
            updated.updatedAt = Date()
            updated.sortIndex = state.decisions[index].options[optionIndex].sortIndex
            // Keep evaluation rows aligned with the current criteria.
            for criterion in state.decisions[index].criteria where updated.evaluation(for: criterion.id) == nil {
                updated.evaluations.append(Evaluation(criterionID: criterion.id))
            }
            state.decisions[index].options[optionIndex] = updated
            log(&state.decisions[index], .optionUpdated, "Option updated: \(updated.displayName)", optionID: updated.id)
            touch(&state.decisions[index])
            let after = ConstraintEngine.disqualifiedOptions(in: state.decisions[index]).count
            state.constraintRecheckNotice = constraintNotice(before: before, after: after)
            effects.append(.persist)
            state.toast = Toast(message: "Option saved", style: .success)

        case .setOptionStatus(let decisionID, let optionID, let status):
            guard let index = index(of: decisionID, in: state),
                  let optionIndex = state.decisions[index].options.firstIndex(where: { $0.id == optionID })
            else { break }
            let previous = state.decisions[index].options[optionIndex].status
            guard previous != status else { break }
            state.decisions[index].options[optionIndex].status = status
            state.decisions[index].options[optionIndex].updatedAt = Date()
            log(&state.decisions[index], .optionStatusChanged,
                "\(state.decisions[index].options[optionIndex].displayName): \(previous.title) → \(status.title)",
                optionID: optionID)
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Marked as \(status.title)", style: status == .rejected ? .warning : .info)

        case .duplicateOption(let decisionID, let optionID):
            guard let index = index(of: decisionID, in: state),
                  let original = state.decisions[index].option(id: optionID)
            else { break }
            var copy = original
            copy.id = UUID()
            copy.name = uniqueName(base: original.displayName, existing: state.decisions[index].options.map(\.name))
            copy.sortIndex = (state.decisions[index].options.map(\.sortIndex).max() ?? -1) + 1
            copy.createdAt = Date()
            copy.updatedAt = Date()
            copy.status = .researching
            // The copy shares nothing with the original — fresh evaluation ids.
            copy.evaluations = original.evaluations.map { evaluation in
                var fresh = evaluation
                fresh.id = UUID()
                return fresh
            }
            // The image file is shared; duplicating it would double storage for no gain.
            state.decisions[index].options.append(copy)
            log(&state.decisions[index], .optionAdded, "Option duplicated: \(copy.displayName)", optionID: copy.id)
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Option duplicated", style: .success,
                                detail: "Evidence links were not copied — attach evidence to the new option separately.")

        case .deleteOption(let decisionID, let optionID):
            guard let index = index(of: decisionID, in: state) else { break }
            let name = state.decisions[index].option(id: optionID)?.displayName ?? "Option"
            let image = state.decisions[index].option(id: optionID)?.imageFileName
            state.decisions[index].options.removeAll { $0.id == optionID }
            // Clean every reference so nothing points at a ghost.
            state.decisions[index].risks.removeAll { $0.optionID == optionID }
            for claimIndex in state.decisions[index].claims.indices
            where state.decisions[index].claims[claimIndex].optionID == optionID {
                state.decisions[index].claims[claimIndex].optionID = nil
            }
            for scenarioIndex in state.decisions[index].scenarios.indices {
                state.decisions[index].scenarios[scenarioIndex].excludedOptionIDs.removeAll { $0 == optionID }
            }
            if state.decisions[index].finalDecision?.selectedOptionID == optionID {
                state.decisions[index].finalDecision?.selectedOptionID = nil
            }
            for evidenceIndex in state.evidence.indices where state.evidence[evidenceIndex].decisionID == decisionID {
                state.evidence[evidenceIndex].links.removeAll { $0.optionID == optionID }
            }
            log(&state.decisions[index], .optionRemoved, "Option removed: \(name)")
            touch(&state.decisions[index])
            if let image { effects.append(.deleteAttachments([image])) }
            effects.append(.persist)
            state.toast = Toast(message: "“\(name.popTruncated(24))” deleted", style: .warning)

        case .moveOptions(let decisionID, let from, let to):
            guard let index = index(of: decisionID, in: state) else { break }
            var ordered = state.decisions[index].sortedOptions
            ordered.move(fromOffsets: from, toOffset: to)
            for (position, option) in ordered.enumerated() {
                if let optionIndex = state.decisions[index].options.firstIndex(where: { $0.id == option.id }) {
                    state.decisions[index].options[optionIndex].sortIndex = position
                }
            }
            touch(&state.decisions[index])
            effects.append(.persist)

        case .setOptionImage(let decisionID, let optionID, let fileName):
            guard let index = index(of: decisionID, in: state),
                  let optionIndex = state.decisions[index].options.firstIndex(where: { $0.id == optionID })
            else { break }
            let previous = state.decisions[index].options[optionIndex].imageFileName
            state.decisions[index].options[optionIndex].imageFileName = fileName
            state.decisions[index].options[optionIndex].updatedAt = Date()
            touch(&state.decisions[index])
            if let previous, previous != fileName { effects.append(.deleteAttachments([previous])) }
            effects.append(.persist)

        // MARK: Evaluations

        case .saveEvaluation(let decisionID, let optionID, let evaluation):
            guard let index = index(of: decisionID, in: state),
                  let optionIndex = state.decisions[index].options.firstIndex(where: { $0.id == optionID })
            else { break }
            let before = ConstraintEngine.disqualifiedOptions(in: state.decisions[index]).count
            let optionName = state.decisions[index].options[optionIndex].displayName
            let criterionName = state.decisions[index].criterion(id: evaluation.criterionID)?.displayName ?? "criterion"

            var updated = evaluation
            updated.updatedAt = Date()

            if let existingIndex = state.decisions[index].options[optionIndex].evaluations
                .firstIndex(where: { $0.criterionID == evaluation.criterionID }) {
                let previous = state.decisions[index].options[optionIndex].evaluations[existingIndex]
                updated.id = previous.id
                updated.hasBeenEdited = previous.hasJudgement
                state.decisions[index].options[optionIndex].evaluations[existingIndex] = updated

                // Record exactly what changed.
                if let oldRating = previous.rating, let newRating = updated.rating, oldRating != newRating {
                    log(&state.decisions[index], .evaluationChanged,
                        "\(optionName) · \(criterionName): rating changed from \(oldRating) to \(newRating)",
                        optionID: optionID, criterionID: evaluation.criterionID)
                } else if previous.rating == nil, let newRating = updated.rating {
                    log(&state.decisions[index], .evaluationChanged,
                        "\(optionName) · \(criterionName): rated \(newRating)",
                        optionID: optionID, criterionID: evaluation.criterionID)
                } else if previous.boolValue != updated.boolValue, let newValue = updated.boolValue {
                    log(&state.decisions[index], .evaluationChanged,
                        "\(optionName) · \(criterionName): answered \(newValue ? "Yes" : "No")",
                        optionID: optionID, criterionID: evaluation.criterionID)
                } else if previous.measuredValue != updated.measuredValue {
                    log(&state.decisions[index], .evaluationChanged,
                        "\(optionName) · \(criterionName): measured value updated",
                        optionID: optionID, criterionID: evaluation.criterionID)
                } else if previous.confidence != updated.confidence {
                    log(&state.decisions[index], .evaluationChanged,
                        "\(optionName) · \(criterionName): confidence set to \(updated.confidence.title)",
                        optionID: optionID, criterionID: evaluation.criterionID)
                }
            } else {
                state.decisions[index].options[optionIndex].evaluations.append(updated)
                log(&state.decisions[index], .evaluationChanged,
                    "\(optionName) · \(criterionName): first evaluation recorded",
                    optionID: optionID, criterionID: evaluation.criterionID)
            }

            state.decisions[index].options[optionIndex].updatedAt = Date()
            touch(&state.decisions[index])
            let after = ConstraintEngine.disqualifiedOptions(in: state.decisions[index]).count
            state.constraintRecheckNotice = constraintNotice(before: before, after: after)
            effects.append(.persist)
            state.toast = Toast(message: "Evaluation saved", style: .success)

        case .clearEvaluation(let decisionID, let optionID, let criterionID):
            guard let index = index(of: decisionID, in: state),
                  let optionIndex = state.decisions[index].options.firstIndex(where: { $0.id == optionID }),
                  let evalIndex = state.decisions[index].options[optionIndex].evaluations
                    .firstIndex(where: { $0.criterionID == criterionID })
            else { break }
            let optionName = state.decisions[index].options[optionIndex].displayName
            let criterionName = state.decisions[index].criterion(id: criterionID)?.displayName ?? "criterion"
            state.decisions[index].options[optionIndex].evaluations[evalIndex] = Evaluation(criterionID: criterionID)
            state.decisions[index].options[optionIndex].updatedAt = Date()
            log(&state.decisions[index], .evaluationChanged,
                "\(optionName) · \(criterionName): evaluation cleared",
                optionID: optionID, criterionID: criterionID)
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Evaluation cleared", style: .info)

        // MARK: Evidence

        case .addEvidence(let item):
            guard item.hasMinimumContent else {
                state.toast = Toast(message: "Nothing to save", style: .error,
                                    detail: "Add a source, a summary or an attachment.")
                effects.append(.haptic(.error))
                break
            }
            state.evidence.append(item)
            if let decisionID = item.decisionID, let index = index(of: decisionID, in: state) {
                log(&state.decisions[index], .evidenceAdded, "Evidence added: \(item.displayTitle)")
                touch(&state.decisions[index])
            }
            effects.append(.persist)
            state.toast = Toast(message: "Evidence saved", style: .success,
                                detail: item.hasExternalSource && !item.sourceChecked ? "Marked as Source Not Checked — the app does not verify links." : nil)

        case .updateEvidence(let item):
            guard let evidenceIndex = state.evidence.firstIndex(where: { $0.id == item.id }) else { break }
            guard item.hasMinimumContent else {
                state.toast = Toast(message: "Nothing to save", style: .error,
                                    detail: "Add a source, a summary or an attachment.")
                effects.append(.haptic(.error))
                break
            }
            let previousAttachment = state.evidence[evidenceIndex].attachment?.fileName
            var updated = item
            updated.updatedAt = Date()
            // Links point at options and criteria of one decision; moving the
            // item to another decision leaves them pointing at nothing.
            if updated.decisionID != state.evidence[evidenceIndex].decisionID {
                updated.links = []
            }
            state.evidence[evidenceIndex] = updated
            if let previousAttachment, previousAttachment != updated.attachment?.fileName {
                effects.append(.deleteAttachments([previousAttachment]))
            }
            if let decisionID = updated.decisionID, let index = index(of: decisionID, in: state) {
                log(&state.decisions[index], .evidenceUpdated, "Evidence updated: \(updated.displayTitle)")
                touch(&state.decisions[index])
            }
            effects.append(.persist)
            state.toast = Toast(message: "Evidence saved", style: .success)

        case .deleteEvidence(let evidenceID):
            guard let evidenceIndex = state.evidence.firstIndex(where: { $0.id == evidenceID }) else { break }
            let item = state.evidence[evidenceIndex]
            state.evidence.remove(at: evidenceIndex)
            // Detach it from any claim that referenced it.
            for decisionIndex in state.decisions.indices {
                for claimIndex in state.decisions[decisionIndex].claims.indices {
                    state.decisions[decisionIndex].claims[claimIndex].supportingEvidenceIDs.removeAll { $0 == evidenceID }
                    state.decisions[decisionIndex].claims[claimIndex].contradictingEvidenceIDs.removeAll { $0 == evidenceID }
                }
                if state.decisions[decisionIndex].finalDecision?.keyEvidenceIDs.contains(evidenceID) == true {
                    state.decisions[decisionIndex].finalDecision?.keyEvidenceIDs.removeAll { $0 == evidenceID }
                }
            }
            if let decisionID = item.decisionID, let index = index(of: decisionID, in: state) {
                log(&state.decisions[index], .evidenceRemoved, "Evidence removed: \(item.displayTitle)")
                touch(&state.decisions[index])
            }
            if let file = item.attachment?.fileName { effects.append(.deleteAttachments([file])) }
            effects.append(.persist)
            state.toast = Toast(message: "Evidence deleted", style: .warning)

        case .setEvidenceVerification(let evidenceID, let status):
            guard let evidenceIndex = state.evidence.firstIndex(where: { $0.id == evidenceID }) else { break }
            state.evidence[evidenceIndex].verification = status
            state.evidence[evidenceIndex].updatedAt = Date()
            // Only a record that actually has an external source can be marked
            // as source-checked.
            if status == .verified, !state.evidence[evidenceIndex].source.popIsBlank {
                state.evidence[evidenceIndex].sourceChecked = true
            }
            if let decisionID = state.evidence[evidenceIndex].decisionID, let index = index(of: decisionID, in: state) {
                log(&state.decisions[index],
                    status == .verified ? .evidenceVerified : .evidenceUpdated,
                    "\(state.evidence[evidenceIndex].displayTitle) marked as \(status.title)")
                touch(&state.decisions[index])
            }
            effects.append(.persist)
            state.toast = Toast(message: "Marked as \(status.title)", style: status == .verified ? .success : .info)

        case .addEvidenceLink(let evidenceID, let link):
            guard let evidenceIndex = state.evidence.firstIndex(where: { $0.id == evidenceID }) else { break }
            guard !link.isEmpty else {
                state.toast = Toast(message: "Choose an option or a criterion", style: .warning)
                break
            }
            let alreadyLinked = state.evidence[evidenceIndex].links.contains {
                $0.optionID == link.optionID && $0.criterionID == link.criterionID
            }
            if alreadyLinked {
                state.toast = Toast(message: "Already linked", style: .warning,
                                    detail: "Change the existing link instead of adding a duplicate.")
                break
            }
            state.evidence[evidenceIndex].links.append(link)
            state.evidence[evidenceIndex].updatedAt = Date()
            effects.append(.persist)
            state.toast = Toast(message: "Link added", style: .success)

        case .updateEvidenceLink(let evidenceID, let link):
            guard let evidenceIndex = state.evidence.firstIndex(where: { $0.id == evidenceID }),
                  let linkIndex = state.evidence[evidenceIndex].links.firstIndex(where: { $0.id == link.id })
            else { break }
            state.evidence[evidenceIndex].links[linkIndex] = link
            state.evidence[evidenceIndex].updatedAt = Date()
            effects.append(.persist)

        case .removeEvidenceLink(let evidenceID, let linkID):
            guard let evidenceIndex = state.evidence.firstIndex(where: { $0.id == evidenceID }) else { break }
            state.evidence[evidenceIndex].links.removeAll { $0.id == linkID }
            state.evidence[evidenceIndex].updatedAt = Date()
            effects.append(.persist)
            state.toast = Toast(message: "Link removed", style: .info)

        // MARK: Claims

        case .addClaim(let decisionID, let claim):
            guard let index = index(of: decisionID, in: state) else { break }
            state.decisions[index].claims.append(claim)
            log(&state.decisions[index], .claimAdded, "Claim added: \(claim.displayText.popTruncated(60))", optionID: claim.optionID)
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Claim recorded", style: .success)

        case .updateClaim(let decisionID, let claim):
            guard let index = index(of: decisionID, in: state),
                  let claimIndex = state.decisions[index].claims.firstIndex(where: { $0.id == claim.id })
            else { break }
            var updated = claim
            updated.updatedAt = Date()
            let previousStatus = state.decisions[index].claims[claimIndex].status
            state.decisions[index].claims[claimIndex] = updated
            if previousStatus != updated.status {
                log(&state.decisions[index], .claimStatusChanged,
                    "Claim status: \(previousStatus.title) → \(updated.status.title)", optionID: updated.optionID)
            } else {
                log(&state.decisions[index], .claimAdded, "Claim updated: \(updated.displayText.popTruncated(60))", optionID: updated.optionID)
            }
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Claim saved", style: .success)

        case .deleteClaim(let decisionID, let claimID):
            guard let index = index(of: decisionID, in: state) else { break }
            let text = state.decisions[index].claim(id: claimID)?.displayText ?? "Claim"
            state.decisions[index].claims.removeAll { $0.id == claimID }
            log(&state.decisions[index], .claimRemoved, "Claim removed: \(text.popTruncated(60))")
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Claim deleted", style: .warning)

        case .setClaimStatus(let decisionID, let claimID, let status):
            guard let index = index(of: decisionID, in: state),
                  let claimIndex = state.decisions[index].claims.firstIndex(where: { $0.id == claimID })
            else { break }
            let previous = state.decisions[index].claims[claimIndex].status
            guard previous != status else { break }
            state.decisions[index].claims[claimIndex].status = status
            state.decisions[index].claims[claimIndex].updatedAt = Date()
            log(&state.decisions[index], .claimStatusChanged, "Claim status: \(previous.title) → \(status.title)")
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Status: \(status.title)", style: status == .verified ? .success : .info)

        case .linkClaimEvidence(let decisionID, let claimID, let evidenceID, let supporting):
            guard let index = index(of: decisionID, in: state),
                  let claimIndex = state.decisions[index].claims.firstIndex(where: { $0.id == claimID })
            else { break }
            // A single item cannot both support and contradict the same claim.
            state.decisions[index].claims[claimIndex].supportingEvidenceIDs.removeAll { $0 == evidenceID }
            state.decisions[index].claims[claimIndex].contradictingEvidenceIDs.removeAll { $0 == evidenceID }
            if supporting {
                state.decisions[index].claims[claimIndex].supportingEvidenceIDs.append(evidenceID)
            } else {
                state.decisions[index].claims[claimIndex].contradictingEvidenceIDs.append(evidenceID)
            }
            state.decisions[index].claims[claimIndex].updatedAt = Date()
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: supporting ? "Added as supporting evidence" : "Added as contradicting evidence",
                                style: .success,
                                detail: "The claim status stays as it is — change it yourself when you are sure.")

        case .unlinkClaimEvidence(let decisionID, let claimID, let evidenceID):
            guard let index = index(of: decisionID, in: state),
                  let claimIndex = state.decisions[index].claims.firstIndex(where: { $0.id == claimID })
            else { break }
            state.decisions[index].claims[claimIndex].supportingEvidenceIDs.removeAll { $0 == evidenceID }
            state.decisions[index].claims[claimIndex].contradictingEvidenceIDs.removeAll { $0 == evidenceID }
            state.decisions[index].claims[claimIndex].updatedAt = Date()
            touch(&state.decisions[index])
            effects.append(.persist)

        case .requestClaimVerification(let decisionID, let claimID, let deadline):
            guard let index = index(of: decisionID, in: state),
                  let claimIndex = state.decisions[index].claims.firstIndex(where: { $0.id == claimID })
            else { break }
            state.decisions[index].claims[claimIndex].verificationRequested = true
            state.decisions[index].claims[claimIndex].verificationDeadline = deadline
            state.decisions[index].claims[claimIndex].updatedAt = Date()
            let title = state.decisions[index].claims[claimIndex].displayText.popTruncated(50)
            var task = FollowUpTask(title: "Verify: \(title)")
            task.dueDate = deadline
            task.notes = "Created from Claim Check."
            state.decisions[index].followUpTasks.append(task)
            log(&state.decisions[index], .followUpCreated, "Verification requested for a claim")
            touch(&state.decisions[index])
            effects.append(.persist)
            effects.append(.rescheduleReminders)
            state.toast = Toast(message: "Follow-up created", style: .success,
                                detail: "Find it in Open Questions → Follow-up tasks.")

        // MARK: Risks

        case .addRisk(let decisionID, let risk):
            guard let index = index(of: decisionID, in: state) else { break }
            state.decisions[index].risks.append(risk)
            log(&state.decisions[index], .riskAdded, "Risk added: \(risk.displayTitle)", optionID: risk.optionID)
            touch(&state.decisions[index])
            effects.append(.persist)
            effects.append(.rescheduleReminders)
            state.toast = Toast(message: "Risk added", style: .success, detail: "Category: \(risk.category.title)")

        case .updateRisk(let decisionID, let risk):
            guard let index = index(of: decisionID, in: state),
                  let riskIndex = state.decisions[index].risks.firstIndex(where: { $0.id == risk.id })
            else { break }
            var updated = risk
            updated.updatedAt = Date()
            state.decisions[index].risks[riskIndex] = updated
            log(&state.decisions[index], .riskUpdated, "Risk updated: \(updated.displayTitle)", optionID: updated.optionID)
            touch(&state.decisions[index])
            effects.append(.persist)
            effects.append(.rescheduleReminders)
            state.toast = Toast(message: "Risk saved", style: .success)

        case .deleteRisk(let decisionID, let riskID):
            guard let index = index(of: decisionID, in: state) else { break }
            let title = state.decisions[index].risk(id: riskID)?.displayTitle ?? "Risk"
            state.decisions[index].risks.removeAll { $0.id == riskID }
            state.decisions[index].outcomeReview?.occurredRiskIDs.removeAll { $0 == riskID }
            log(&state.decisions[index], .riskRemoved, "Risk removed: \(title)")
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Risk deleted", style: .warning)

        case .setRiskState(let decisionID, let riskID, let riskState, let reason):
            guard let index = index(of: decisionID, in: state),
                  let riskIndex = state.decisions[index].risks.firstIndex(where: { $0.id == riskID })
            else { break }
            let risk = state.decisions[index].risks[riskIndex]
            // High/High risks may only be accepted with a written reason.
            if riskState == .accepted, risk.isHighHigh, !risk.hasMitigation, reason.popIsBlank {
                state.toast = Toast(message: "A reason is required", style: .error,
                                    detail: "High likelihood and high impact — write why you accept it without a plan.")
                effects.append(.haptic(.error))
                break
            }
            state.decisions[index].risks[riskIndex].state = riskState
            if riskState == .accepted { state.decisions[index].risks[riskIndex].acceptWithoutMitigationReason = reason.popTrimmed }
            state.decisions[index].risks[riskIndex].updatedAt = Date()
            log(&state.decisions[index], .riskUpdated, "\(risk.displayTitle) marked as \(riskState.title)", optionID: risk.optionID)
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Marked as \(riskState.title)", style: riskState == .occurred ? .warning : .info)

        // MARK: Scenarios

        case .addScenario(let decisionID, let scenario):
            guard let index = index(of: decisionID, in: state) else { break }
            state.decisions[index].scenarios.append(scenario)
            log(&state.decisions[index], .scenarioCreated, "Scenario created: \(scenario.displayName)")
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Scenario saved", style: .success, detail: "The baseline is unchanged.")

        case .updateScenario(let decisionID, let scenario):
            guard let index = index(of: decisionID, in: state),
                  let scenarioIndex = state.decisions[index].scenarios.firstIndex(where: { $0.id == scenario.id })
            else { break }
            var updated = scenario
            updated.updatedAt = Date()
            state.decisions[index].scenarios[scenarioIndex] = updated
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Scenario updated", style: .success)

        case .duplicateScenario(let decisionID, let scenarioID):
            guard let index = index(of: decisionID, in: state),
                  let original = state.decisions[index].scenario(id: scenarioID)
            else { break }
            var copy = original
            copy.id = UUID()
            copy.name = uniqueName(base: original.displayName, existing: state.decisions[index].scenarios.map(\.name))
            copy.createdAt = Date()
            copy.updatedAt = Date()
            state.decisions[index].scenarios.append(copy)
            log(&state.decisions[index], .scenarioCreated, "Scenario duplicated: \(copy.displayName)")
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Scenario duplicated", style: .success)

        case .deleteScenario(let decisionID, let scenarioID):
            guard let index = index(of: decisionID, in: state) else { break }
            let name = state.decisions[index].scenario(id: scenarioID)?.displayName ?? "Scenario"
            state.decisions[index].scenarios.removeAll { $0.id == scenarioID }
            log(&state.decisions[index], .scenarioRemoved, "Scenario removed: \(name)")
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Scenario deleted", style: .warning)

        // MARK: Open questions

        case .acceptUnknown(let decisionID, let draft):
            guard let index = index(of: decisionID, in: state) else { break }
            guard !draft.reason.popIsBlank else {
                state.toast = Toast(message: "Explain why", style: .error,
                                    detail: "Write why you are comfortable proceeding without this.")
                effects.append(.haptic(.error))
                break
            }
            state.decisions[index].acceptedUnknowns.removeAll { $0.questionKey == draft.questionKey }
            state.decisions[index].acceptedUnknowns.append(
                AcceptedUnknown(questionKey: draft.questionKey, kind: draft.kind, label: draft.label, reason: draft.reason.popTrimmed)
            )
            log(&state.decisions[index], .unknownAccepted, "Accepted as unknown: \(draft.label.popTruncated(60))")
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Accepted as a known gap", style: .info)

        case .removeAcceptedUnknown(let decisionID, let unknownID):
            guard let index = index(of: decisionID, in: state) else { break }
            state.decisions[index].acceptedUnknowns.removeAll { $0.id == unknownID }
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Back in Open Questions", style: .info)

        case .addFollowUp(let decisionID, let task):
            guard let index = index(of: decisionID, in: state) else { break }
            state.decisions[index].followUpTasks.append(task)
            log(&state.decisions[index], .followUpCreated, "Follow-up created: \(task.title.popTruncated(60))")
            touch(&state.decisions[index])
            effects.append(.persist)
            effects.append(.rescheduleReminders)
            state.toast = Toast(message: "Follow-up added", style: .success)

        case .toggleFollowUp(let decisionID, let taskID):
            guard let index = index(of: decisionID, in: state),
                  let taskIndex = state.decisions[index].followUpTasks.firstIndex(where: { $0.id == taskID })
            else { break }
            state.decisions[index].followUpTasks[taskIndex].isDone.toggle()
            touch(&state.decisions[index])
            effects.append(.persist)
            effects.append(.rescheduleReminders)

        case .setFollowUpDone(let decisionID, let taskID, let isDone):
            guard let index = index(of: decisionID, in: state),
                  let taskIndex = state.decisions[index].followUpTasks.firstIndex(where: { $0.id == taskID }),
                  state.decisions[index].followUpTasks[taskIndex].isDone != isDone
            else { break }
            state.decisions[index].followUpTasks[taskIndex].isDone = isDone
            touch(&state.decisions[index])
            effects.append(.persist)
            effects.append(.rescheduleReminders)

        case .deleteFollowUp(let decisionID, let taskID):
            guard let index = index(of: decisionID, in: state) else { break }
            state.decisions[index].followUpTasks.removeAll { $0.id == taskID }
            touch(&state.decisions[index])
            effects.append(.persist)
            effects.append(.rescheduleReminders)

        // MARK: Finalize

        case .saveFinalDecisionDraft(let decisionID, let record):
            guard let index = index(of: decisionID, in: state) else { break }
            var draft = record
            draft.isDraft = true
            draft.finalizedAt = nil
            draft.version = state.decisions[index].finalDecision?.version ?? 1
            state.decisions[index].finalDecision = draft
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Draft saved", style: .success, detail: "The decision is not finalized yet.")

        case .finalizeDecision(let decisionID, let record):
            guard let index = index(of: decisionID, in: state) else { break }
            guard let selectedID = record.selectedOptionID,
                  let selected = state.decisions[index].option(id: selectedID) else {
                state.toast = Toast(message: "Choose an option", style: .error,
                                    detail: "The selected option must still exist.")
                effects.append(.haptic(.error))
                break
            }
            guard !record.whyThisOption.popIsBlank else {
                state.toast = Toast(message: "Explain your choice", style: .error,
                                    detail: "“Why this option?” is required.")
                effects.append(.haptic(.error))
                break
            }
            let violations = ConstraintEngine.violations(for: selected, decision: state.decisions[index])
            guard violations.isEmpty else {
                state.toast = Toast(message: "Hard constraint violated", style: .error,
                                    detail: "\(selected.displayName) breaks \(violations.count) hard \(violations.count == 1 ? "constraint" : "constraints").")
                effects.append(.haptic(.error))
                break
            }

            var final = record
            final.isDraft = false
            final.finalizedAt = Date()
            final.version = (state.decisions[index].snapshots.map(\.version).max() ?? 0) + 1

            // Immutable snapshot of everything the choice was based on.
            let scoreboard = ScoringEngine.scoreboard(
                decision: state.decisions[index],
                evidence: state.evidence.filter { $0.decisionID == decisionID },
                scaleMax: state.scaleMax
            )
            let snapshot = DecisionSnapshot(
                version: final.version,
                reason: "Decision finalized",
                label: "Version \(final.version)",
                criteria: state.decisions[index].criteria,
                options: state.decisions[index].options,
                evidence: state.evidence.filter { $0.decisionID == decisionID },
                claims: state.decisions[index].claims,
                risks: state.decisions[index].risks,
                hardConstraints: state.decisions[index].hardConstraints,
                finalDecision: final,
                selectedOptionName: selected.displayName,
                leaderScore: scoreboard.score(for: selectedID)?.weightedScore
            )
            state.decisions[index].snapshots.append(snapshot)
            state.decisions[index].finalDecision = final
            state.decisions[index].status = .finalized

            // Mark the chosen option and step everything else down from Selected.
            for optionIndex in state.decisions[index].options.indices {
                if state.decisions[index].options[optionIndex].id == selectedID {
                    state.decisions[index].options[optionIndex].status = .selected
                } else if state.decisions[index].options[optionIndex].status == .selected {
                    state.decisions[index].options[optionIndex].status = .shortlisted
                }
            }

            log(&state.decisions[index], .decisionFinalized,
                "Decision finalized: \(selected.displayName)",
                detail: "Version \(final.version) snapshot saved")
            touch(&state.decisions[index])
            effects.append(.persist)
            effects.append(.rescheduleReminders)
            effects.append(.haptic(.success))
            state.toast = Toast(message: "Decision finalized", style: .success,
                                detail: "A read-only snapshot of version \(final.version) was saved.")

        case .reopenDecision(let decisionID, let reason):
            guard let index = index(of: decisionID, in: state) else { break }
            guard !reason.popIsBlank else {
                state.toast = Toast(message: "A reason is required", style: .error,
                                    detail: "Say why you are reopening this decision.")
                effects.append(.haptic(.error))
                break
            }
            let nextVersion = (state.decisions[index].snapshots.map(\.version).max() ?? 1) + 1
            state.decisions[index].status = .active
            state.decisions[index].finalDecision?.isDraft = true
            state.decisions[index].finalDecision?.version = nextVersion
            log(&state.decisions[index], .decisionReopened, "Decision reopened", detail: reason.popTrimmed)
            touch(&state.decisions[index])
            effects.append(.persist)
            effects.append(.rescheduleReminders)
            state.toast = Toast(message: "Decision reopened", style: .info,
                                detail: "The previous version stays available in History.")

        // MARK: Outcome review

        case .saveOutcomeReviewDraft(let decisionID, let review):
            guard let index = index(of: decisionID, in: state) else { break }
            var draft = review
            draft.isDraft = true
            draft.completedAt = nil
            draft.updatedAt = Date()
            state.decisions[index].outcomeReview = draft
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Review draft saved", style: .success)

        case .completeOutcomeReview(let decisionID, let review):
            guard let index = index(of: decisionID, in: state) else { break }
            guard review.canComplete else {
                state.toast = Toast(message: "Two answers are required", style: .error,
                                    detail: "Choose Overall Satisfaction and answer “Would you choose it again?”.")
                effects.append(.haptic(.error))
                break
            }
            var completed = review
            completed.isDraft = false
            completed.completedAt = Date()
            completed.updatedAt = Date()
            state.decisions[index].outcomeReview = completed
            // Risks the user says occurred are recorded as such.
            for riskIndex in state.decisions[index].risks.indices
            where completed.occurredRiskIDs.contains(state.decisions[index].risks[riskIndex].id) {
                state.decisions[index].risks[riskIndex].state = .occurred
            }
            log(&state.decisions[index], .outcomeReviewed, "Outcome review completed",
                detail: "Satisfaction: \(completed.satisfaction?.title ?? "—")")
            touch(&state.decisions[index])
            effects.append(.persist)
            effects.append(.rescheduleReminders)
            effects.append(.haptic(.success))
            state.toast = Toast(message: "Outcome review completed", style: .success,
                                detail: "Your original decision was not changed.")

        case .markPurchaseCompleted(let decisionID):
            guard let index = index(of: decisionID, in: state) else { break }
            log(&state.decisions[index], .statusChanged, "Marked as completed in the real world")
            touch(&state.decisions[index])
            effects.append(.persist)
            state.toast = Toast(message: "Marked as completed", style: .success)
        }

        return ReduceResult(state: state, effects: effects)
    }

    // MARK: - Repeated creates

    /// A create whose response was lost may already be stored — the next refresh
    /// brings the record in — and the user then taps Save again. Editors keep
    /// the new record's id, so the repeat is recognised here and applied as an
    /// update: never a second copy.
    private static func resolvingRepeatedCreate(_ intent: AppIntent, in state: AppState) -> AppIntent {
        switch intent {
        case .createDecision(let draft) where state.decision(id: draft.id) != nil:
            return .load
        case .addConstraint(let decisionID, let constraint) where state.decision(id: decisionID)?.constraint(id: constraint.id) != nil:
            return .updateConstraint(decisionID: decisionID, constraint: constraint)
        case .addCriterion(let decisionID, let criterion) where state.decision(id: decisionID)?.criterion(id: criterion.id) != nil:
            return .updateCriterion(decisionID: decisionID, criterion: criterion)
        case .addOption(let decisionID, let option) where state.decision(id: decisionID)?.option(id: option.id) != nil:
            return .updateOption(decisionID: decisionID, option: option)
        case .addEvidence(let item) where state.evidenceItem(id: item.id) != nil:
            return .updateEvidence(item)
        case .addClaim(let decisionID, let claim) where state.decision(id: decisionID)?.claim(id: claim.id) != nil:
            return .updateClaim(decisionID: decisionID, claim: claim)
        case .addRisk(let decisionID, let risk) where state.decision(id: decisionID)?.risk(id: risk.id) != nil:
            return .updateRisk(decisionID: decisionID, risk: risk)
        case .addScenario(let decisionID, let scenario) where state.decision(id: decisionID)?.scenario(id: scenario.id) != nil:
            return .updateScenario(decisionID: decisionID, scenario: scenario)
        case .addFollowUp(let decisionID, let task) where state.decision(id: decisionID)?.followUpTasks.contains(where: { $0.id == task.id }) == true:
            return .load
        default:
            return intent
        }
    }

    // MARK: - Helpers

    private static func index(of decisionID: UUID, in state: AppState) -> Int? {
        state.decisions.firstIndex { $0.id == decisionID }
    }

    private static func touch(_ decision: inout Decision) {
        decision.updatedAt = Date()
    }

    private static func log(
        _ decision: inout Decision,
        _ kind: ActivityKind,
        _ summary: String,
        detail: String = "",
        optionID: UUID? = nil,
        criterionID: UUID? = nil
    ) {
        decision.activity.append(
            ActivityEvent(kind: kind, summary: summary, detail: detail, optionID: optionID, criterionID: criterionID)
        )
        // Keep the log bounded; the newest 500 entries are more than enough.
        if decision.activity.count > 500 {
            decision.activity.removeFirst(decision.activity.count - 500)
        }
    }

    private static func constraintNotice(before: Int, after: Int) -> String? {
        guard after != before, after > 0 else {
            return after == 0 && before > 0 ? "All options now meet your hard constraints." : nil
        }
        return "\(after) \(after == 1 ? "option no longer meets" : "options no longer meet") your hard constraints."
    }

    private static func uniqueName(base: String, existing: [String]) -> String {
        let taken = Set(existing.map { $0.popNormalizedForCompare })
        var candidate = "\(base) (copy)"
        var counter = 2
        while taken.contains(candidate.popNormalizedForCompare) {
            candidate = "\(base) (copy \(counter))"
            counter += 1
        }
        return candidate
    }

    private static func buildDecision(from draft: DecisionDraft, settings: AppSettings) -> Decision {
        var decision = Decision()
        decision.id = draft.id
        decision.title = draft.title.popTrimmed
        decision.category = draft.category
        decision.customCategoryName = draft.customCategoryName.popTrimmed
        decision.desiredOutcome = draft.desiredOutcome.popTrimmed
        decision.whyItMatters = draft.whyItMatters.popTrimmed
        decision.peopleAffected = draft.peopleAffected.popTrimmed
        decision.budgetMin = draft.budgetMin
        decision.budgetMax = draft.budgetMax
        decision.currencyCode = draft.currencyCode
        decision.deadline = draft.deadline
        decision.preferredCompletionDate = draft.preferredCompletionDate
        decision.hardConstraints = draft.hardConstraints
        decision.owner = draft.owner.popIsBlank ? settings.ownerName : draft.owner.popTrimmed
        decision.status = draft.saveAsDraft ? .draft : .active
        decision.templateID = draft.templateID

        var sortIndex = 0
        for templateCriterion in draft.templateCriteria {
            var criterion = Criterion()
            criterion.name = templateCriterion.name
            criterion.details = templateCriterion.details
            criterion.kind = templateCriterion.kind
            criterion.importance = templateCriterion.importance
            criterion.measurementMethod = templateCriterion.measurementMethod
            criterion.weight = templateCriterion.suggestedWeight
            criterion.sortIndex = sortIndex
            sortIndex += 1
            decision.criteria.append(criterion)
        }

        decision.activity.append(
            ActivityEvent(kind: .decisionCreated,
                          summary: "Decision created",
                          detail: draft.templateCriteria.isEmpty
                            ? "Started from scratch"
                            : "Started from the “\(DecisionTemplateLibrary.template(id: draft.templateID)?.title ?? "template")” structure")
        )
        return decision
    }
}
