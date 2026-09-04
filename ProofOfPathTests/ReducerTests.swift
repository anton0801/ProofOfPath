//
//  ReducerTests.swift
//  ProofOfPathTests
//

import XCTest
@testable import ProofOfPath

@MainActor
final class ReducerTests: XCTestCase {

    private func startedDecision() -> (AppState, UUID) {
        var state = AppState()
        state = reduce(state, .createDecision(makeDraft("Fridge")))
        return (state, state.decisions[0].id)
    }

    // MARK: Creation and seeding

    func testNewOptionIsSeededWithAnEmptyRowPerCriterion() {
        var (state, id) = startedDecision()
        for i in 0..<3 {
            state = reduce(state, .addCriterion(decisionID: id, criterion: makeCriterion("C\(i)", sortIndex: i)))
        }
        let option = makeOption("A")
        state = reduce(state, .addOption(decisionID: id, option: option))

        let stored = state.decisions[0].option(id: option.id)!
        XCTAssertEqual(stored.evaluations.count, 3)
        XCTAssertTrue(stored.evaluations.allSatisfy(\.isEmpty))
    }

    func testACriterionAddedLaterAppearsOnEveryOption() {
        var (state, id) = startedDecision()
        state = reduce(state, .addOption(decisionID: id, option: makeOption("A")))
        state = reduce(state, .addOption(decisionID: id, option: makeOption("B")))

        let late = makeCriterion("Warranty", kind: .higherIsBetter)
        state = reduce(state, .addCriterion(decisionID: id, criterion: late))

        XCTAssertTrue(state.decisions[0].options.allSatisfy {
            $0.evaluation(for: late.id)?.isEmpty == true
        })
    }

    func testDeletingACriterionRemovesItsRowsAndEvidenceLinks() {
        var (state, id) = startedDecision()
        let criterion = makeCriterion("Price", weight: 100)
        state = reduce(state, .addCriterion(decisionID: id, criterion: criterion))
        let option = makeOption("A")
        state = reduce(state, .addOption(decisionID: id, option: option))

        var item = Evidence()
        item.decisionID = id
        item.summary = "s"
        item.links = [EvidenceLink(optionID: option.id, criterionID: criterion.id, relation: .supports)]
        state = reduce(state, .addEvidence(item))

        state = reduce(state, .deleteCriterion(decisionID: id, criterionID: criterion.id))

        XCTAssertNil(state.decisions[0].option(id: option.id)?.evaluation(for: criterion.id))
        XCTAssertTrue(state.evidence[0].links.isEmpty, "A link to a deleted criterion must not survive")
    }

    func testDeletingACriterionDowngradesAConstraintThatPointedAtIt() {
        var (state, id) = startedDecision()
        let criterion = makeCriterion("Fits", kind: .yesNo, weight: 100)
        state = reduce(state, .addCriterion(decisionID: id, criterion: criterion))

        var constraint = HardConstraint()
        constraint.title = "Must fit"
        constraint.check = .criterionMustBeYes(criterionID: criterion.id)
        state = reduce(state, .addConstraint(decisionID: id, constraint: constraint))
        state = reduce(state, .deleteCriterion(decisionID: id, criterionID: criterion.id))

        let stored = state.decisions[0].constraint(id: constraint.id)!
        XCTAssertFalse(stored.check.isAutomatic, "It cannot keep silently passing")
        XCTAssertTrue(stored.details.contains("deleted"))
    }

    // MARK: Weights

    func testBalancingLandsOnExactlyOneHundredForAwkwardCounts() {
        for count in [3, 7, 10, 11] {
            var (state, id) = startedDecision()
            for i in 0..<count {
                state = reduce(state, .addCriterion(decisionID: id, criterion: makeCriterion("C\(i)", sortIndex: i)))
            }
            state = reduce(state, .balanceCriteriaWeights(decisionID: id))
            XCTAssertEqual(state.decisions[0].totalWeight, 100, accuracy: 0.0001,
                           "\(count) criteria did not balance to exactly 100%")
        }
    }

    func testASingleWeightIsClampedToTheLegalRange() {
        var (state, id) = startedDecision()
        let criterion = makeCriterion("C")
        state = reduce(state, .addCriterion(decisionID: id, criterion: criterion))

        state = reduce(state, .setCriterionWeight(decisionID: id, criterionID: criterion.id, weight: 250))
        XCTAssertEqual(state.decisions[0].criteria[0].weight, 100)

        state = reduce(state, .setCriterionWeight(decisionID: id, criterionID: criterion.id, weight: -5))
        XCTAssertEqual(state.decisions[0].criteria[0].weight, 0)
    }

    func testTheTotalCanStillExceedOneHundredAcrossCriteria() {
        var (state, id) = startedDecision()
        state = reduce(state, .addCriterion(decisionID: id, criterion: makeCriterion("A", weight: 60, sortIndex: 0)))
        state = reduce(state, .addCriterion(decisionID: id, criterion: makeCriterion("B", weight: 60, sortIndex: 1)))
        XCTAssertEqual(state.decisions[0].totalWeight, 120, accuracy: 0.0001)
        XCTAssertFalse(state.decisions[0].isWeightBalanced)
    }

    // MARK: Guardrails

    func testEmptyEvidenceIsRefused() {
        var state = AppState()
        state = reduce(state, .addEvidence(Evidence()))
        XCTAssertTrue(state.evidence.isEmpty)
        XCTAssertEqual(state.toast?.message, "Nothing to save")
    }

    func testAHighHighRiskCannotBeAcceptedWithoutAReason() {
        var (state, id) = startedDecision()
        var risk = Risk()
        risk.title = "Delivery slips"
        risk.likelihood = .high
        risk.impact = .high
        state = reduce(state, .addRisk(decisionID: id, risk: risk))

        let refused = reduce(state, .setRiskState(decisionID: id, riskID: risk.id, state: .accepted, reason: ""))
        XCTAssertEqual(refused.decisions[0].risk(id: risk.id)?.state, .open)
        XCTAssertEqual(refused.toast?.message, "A reason is required")

        let accepted = reduce(state, .setRiskState(decisionID: id, riskID: risk.id,
                                                   state: .accepted, reason: "Worst case is cheap"))
        XCTAssertEqual(accepted.decisions[0].risk(id: risk.id)?.state, .accepted)
    }

    func testFinalizingRequiresAReasonAndACleanOption() {
        var (state, id) = startedDecision()
        let option = makeOption("A", cost: 900)
        state = reduce(state, .addOption(decisionID: id, option: option))

        var record = FinalDecision()
        record.selectedOptionID = option.id
        record.whyThisOption = ""
        let noReason = reduce(state, .finalizeDecision(decisionID: id, decisionRecord: record))
        XCTAssertNotEqual(noReason.decisions[0].status, .finalized)

        record.whyThisOption = "Cheapest that qualifies"
        let finalized = reduce(state, .finalizeDecision(decisionID: id, decisionRecord: record))
        XCTAssertEqual(finalized.decisions[0].status, .finalized)
        XCTAssertEqual(finalized.decisions[0].snapshots.count, 1)
        XCTAssertEqual(finalized.decisions[0].option(id: option.id)?.status, .selected)
    }

    func testFinalizingIsRefusedWhenTheChoiceBreaksAConstraint() {
        var (state, id) = startedDecision()
        let option = makeOption("Pricey", cost: 5000)
        state = reduce(state, .addOption(decisionID: id, option: option))

        var constraint = HardConstraint()
        constraint.title = "Under 1000"
        constraint.check = .maximumCost(1000)
        state = reduce(state, .addConstraint(decisionID: id, constraint: constraint))

        var record = FinalDecision()
        record.selectedOptionID = option.id
        record.whyThisOption = "I want it anyway"
        let refused = reduce(state, .finalizeDecision(decisionID: id, decisionRecord: record))
        XCTAssertNotEqual(refused.decisions[0].status, .finalized)
    }

    func testASnapshotDoesNotChangeWhenTheDecisionLaterDoes() {
        var (state, id) = startedDecision()
        let criterion = makeCriterion("Price", weight: 100)
        state = reduce(state, .addCriterion(decisionID: id, criterion: criterion))
        let option = makeOption("A", cost: 900)
        state = reduce(state, .addOption(decisionID: id, option: option))

        var record = FinalDecision()
        record.selectedOptionID = option.id
        record.whyThisOption = "Because"
        state = reduce(state, .finalizeDecision(decisionID: id, decisionRecord: record))
        let snapshotWeights = state.decisions[0].snapshots[0].criteria.map(\.weight)

        state = reduce(state, .setCriterionWeight(decisionID: id, criterionID: criterion.id, weight: 5))
        XCTAssertEqual(state.decisions[0].snapshots[0].criteria.map(\.weight), snapshotWeights)
    }

    func testReopeningNeedsAReasonAndBumpsTheVersion() {
        var (state, id) = startedDecision()
        let option = makeOption("A", cost: 900)
        state = reduce(state, .addOption(decisionID: id, option: option))
        var record = FinalDecision()
        record.selectedOptionID = option.id
        record.whyThisOption = "Because"
        state = reduce(state, .finalizeDecision(decisionID: id, decisionRecord: record))

        let refused = reduce(state, .reopenDecision(decisionID: id, reason: ""))
        XCTAssertEqual(refused.decisions[0].status, .finalized)

        let reopened = reduce(state, .reopenDecision(decisionID: id, reason: "Price dropped"))
        XCTAssertEqual(reopened.decisions[0].status, .active)
        XCTAssertEqual(reopened.decisions[0].snapshots.count, 1, "History must survive a reopen")
        XCTAssertEqual(reopened.decisions[0].finalDecision?.version, 2)
    }

    func testOutcomeReviewNeedsBothRequiredAnswers() {
        var (state, id) = startedDecision()
        let option = makeOption("A", cost: 900)
        state = reduce(state, .addOption(decisionID: id, option: option))
        var record = FinalDecision()
        record.selectedOptionID = option.id
        record.whyThisOption = "Because"
        state = reduce(state, .finalizeDecision(decisionID: id, decisionRecord: record))

        var review = OutcomeReview()
        review.actualOutcome = "Fine"
        let incomplete = reduce(state, .completeOutcomeReview(decisionID: id, review: review))
        XCTAssertNotEqual(incomplete.decisions[0].outcomeReview?.isComplete, true)

        review.satisfaction = .satisfied
        review.wouldChooseAgain = .yes
        let complete = reduce(state, .completeOutcomeReview(decisionID: id, review: review))
        XCTAssertEqual(complete.decisions[0].outcomeReview?.isComplete, true)
        XCTAssertEqual(complete.decisions[0].finalDecision?.whyThisOption, "Because",
                       "Reviewing must not rewrite the original decision")
    }

    // MARK: Housekeeping

    func testShrinkingTheRatingScaleClampsRatingsAndThresholds() {
        var (state, id) = startedDecision()
        // Start on the wide scale, so there is something to shrink from.
        state = reduce(state, .setRatingScale(10))

        var criterion = makeCriterion("Q", weight: 100)
        criterion.minimumAcceptableValue = "8"
        state = reduce(state, .addCriterion(decisionID: id, criterion: criterion))
        let option = makeOption("A")
        state = reduce(state, .addOption(decisionID: id, option: option))
        state = reduce(state, .saveEvaluation(decisionID: id, optionID: option.id,
                                              evaluation: makeEvaluation(criterion.id, rating: 9, reason: "x")))
        XCTAssertEqual(state.decisions[0].option(id: option.id)?.evaluation(for: criterion.id)?.rating, 9)

        state = reduce(state, .setRatingScale(5))

        XCTAssertEqual(state.decisions[0].option(id: option.id)?.evaluation(for: criterion.id)?.rating, 5)
        XCTAssertEqual(state.decisions[0].criteria[0].minimumAcceptableValue, "5",
                       "A threshold above the new ceiling would be unreachable")
    }

    func testWideningTheRatingScaleLeavesExistingRatingsAlone() {
        var (state, id) = startedDecision()
        let criterion = makeCriterion("Q", weight: 100)
        state = reduce(state, .addCriterion(decisionID: id, criterion: criterion))
        let option = makeOption("A")
        state = reduce(state, .addOption(decisionID: id, option: option))
        state = reduce(state, .saveEvaluation(decisionID: id, optionID: option.id,
                                              evaluation: makeEvaluation(criterion.id, rating: 4, reason: "x")))

        state = reduce(state, .setRatingScale(10))
        XCTAssertEqual(state.decisions[0].option(id: option.id)?.evaluation(for: criterion.id)?.rating, 4,
                       "Widening the scale must not rewrite a judgement the user already made")
    }

    func testDeletingADecisionTakesItsEvidenceWithIt() {
        var (state, id) = startedDecision()
        var item = Evidence()
        item.decisionID = id
        item.summary = "s"
        state = reduce(state, .addEvidence(item))

        state = reduce(state, .deleteDecision(id))
        XCTAssertTrue(state.decisions.isEmpty)
        XCTAssertTrue(state.evidence.isEmpty)
    }

    func testRestoringAnArchivedDecisionReturnsItsPreviousStatus() {
        var (state, id) = startedDecision()
        state = reduce(state, .setDecisionStatus(decisionID: id, status: .paused))
        state = reduce(state, .archiveDecision(id))
        XCTAssertEqual(state.decisions[0].status, .archived)

        state = reduce(state, .restoreDecision(id))
        XCTAssertEqual(state.decisions[0].status, .paused)
    }

    func testDuplicatingAnOptionProducesAnIndependentCopy() {
        var (state, id) = startedDecision()
        state = reduce(state, .addCriterion(decisionID: id, criterion: makeCriterion("C", weight: 100)))
        let original = makeOption("Liebherr", cost: 1249)
        state = reduce(state, .addOption(decisionID: id, option: original))
        state = reduce(state, .duplicateOption(decisionID: id, optionID: original.id))

        let copies = state.decisions[0].options.filter { $0.name.contains("Liebherr") }
        XCTAssertEqual(copies.count, 2)
        XCTAssertEqual(Set(copies.map(\.id)).count, 2)
        XCTAssertEqual(Set(copies.map(\.name)).count, 2)
        let evaluationIDs = copies.flatMap { $0.evaluations.map(\.id) }
        XCTAssertEqual(Set(evaluationIDs).count, evaluationIDs.count,
                       "A copy must not share evaluation identities with its original")
    }

    func testAnUnknownIdentifierIsASafeNoOp() {
        let (state, _) = startedDecision()
        let after = reduce(state, .deleteOption(decisionID: UUID(), optionID: UUID()))
        XCTAssertEqual(after.decisions.count, state.decisions.count)
    }

    func testAcceptingAnUnknownRequiresAnExplanation() {
        var (state, id) = startedDecision()
        state = reduce(state, .addOption(decisionID: id, option: makeOption("No price")))
        let questions = OpenQuestionsEngine.questions(for: state.decisions[0], evidence: [], scaleMax: 5)
        let key = questions.first { $0.kind == .optionWithoutCost }!.key

        let refused = reduce(state, .acceptUnknown(
            decisionID: id,
            question: AcceptedUnknownDraft(questionKey: key, kind: .optionWithoutCost, label: "L", reason: "")))
        XCTAssertTrue(refused.decisions[0].acceptedUnknowns.isEmpty)

        let accepted = reduce(state, .acceptUnknown(
            decisionID: id,
            question: AcceptedUnknownDraft(questionKey: key, kind: .optionWithoutCost,
                                           label: "L", reason: "Cannot change the ranking")))
        XCTAssertEqual(accepted.decisions[0].acceptedUnknowns.count, 1)

        let remaining = OpenQuestionsEngine.unresolved(for: accepted.decisions[0], evidence: [], scaleMax: 5)
        XCTAssertFalse(remaining.contains { $0.key == key })
    }

    func testSavingAnEvaluationRequestsAWrite() {
        var (state, id) = startedDecision()
        let criterion = makeCriterion("C", weight: 100)
        state = reduce(state, .addCriterion(decisionID: id, criterion: criterion))
        let option = makeOption("A")
        state = reduce(state, .addOption(decisionID: id, option: option))

        let produced = effects(state, .saveEvaluation(decisionID: id, optionID: option.id,
                                                      evaluation: makeEvaluation(criterion.id, rating: 3)))
        XCTAssertTrue(produced.contains(.persist))
    }

    func testANoOpStatusChangeProducesNoEffects() {
        let (state, id) = startedDecision()
        let current = state.decisions[0].status
        XCTAssertTrue(effects(state, .setDecisionStatus(decisionID: id, status: current)).isEmpty)
    }
}
