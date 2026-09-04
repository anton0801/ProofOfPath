//
//  ScoringEngineTests.swift
//  ProofOfPathTests
//
//  Every number the app shows has to be reproducible by hand.
//

import XCTest
@testable import ProofOfPath

@MainActor
final class ScoringEngineTests: XCTestCase {

    /// Price 50% (must-have, max 1100), Noise 30%, Fits 20% (yes/no must-have).
    private func makeDecision() -> (Decision, Criterion, Criterion, Criterion, DecisionOption, DecisionOption) {
        var state = AppState()
        state = reduce(state, .createDecision(makeDraft("Fridge", outcome: "Quiet and fits")))
        let id = state.decisions[0].id

        let price = makeCriterion("Price", kind: .lowerIsBetter, importance: .mustHave,
                                  weight: 50, minimum: "1100", sortIndex: 0)
        let noise = makeCriterion("Noise", kind: .lowerIsBetter, weight: 30, minimum: "42", sortIndex: 1)
        let fits = makeCriterion("Fits", kind: .yesNo, importance: .mustHave, weight: 20, sortIndex: 2)
        for c in [price, noise, fits] {
            state = reduce(state, .addCriterion(decisionID: id, criterion: c))
        }

        let a = makeOption("Bosch", cost: 949, sortIndex: 0)
        let b = makeOption("Liebherr", cost: 1249, sortIndex: 1)
        state = reduce(state, .addOption(decisionID: id, option: a))
        state = reduce(state, .addOption(decisionID: id, option: b))

        for e in [makeEvaluation(price.id, rating: 4, value: "949", reason: "Quote", confidence: .high),
                  makeEvaluation(noise.id, rating: 4, value: "38", reason: "Spec", confidence: .high),
                  makeEvaluation(fits.id, value: "59.5", bool: true, reason: "Measured", confidence: .high)] {
            state = reduce(state, .saveEvaluation(decisionID: id, optionID: a.id, evaluation: e))
        }
        for e in [makeEvaluation(price.id, rating: 2, value: "1249", reason: "Shop", confidence: .high),
                  makeEvaluation(noise.id, rating: 5, value: "35", reason: "Spec", confidence: .high),
                  makeEvaluation(fits.id, value: "59.7", bool: true, reason: "Measured", confidence: .high)] {
            state = reduce(state, .saveEvaluation(decisionID: id, optionID: b.id, evaluation: e))
        }
        return (state.decisions[0], price, noise, fits, a, b)
    }

    func testWeightedScoreIsReproducibleByHand() {
        let (decision, _, _, _, a, b) = makeDecision()
        let board = ScoringEngine.scoreboard(decision: decision, evidence: [], scaleMax: 5)

        // A: 0.75×50 + 0.75×30 + 1.0×20 = 37.5 + 22.5 + 20 = 80
        XCTAssertEqual(board.score(for: a.id)!.weightedScore, 80, accuracy: 0.001)
        // B: 0.25×50 + 1.0×30 + 1.0×20 = 12.5 + 30 + 20 = 62.5
        XCTAssertEqual(board.score(for: b.id)!.weightedScore, 62.5, accuracy: 0.001)
    }

    func testLeaderIsTheHighestEligibleOption() {
        let (decision, _, _, _, a, _) = makeDecision()
        let board = ScoringEngine.scoreboard(decision: decision, evidence: [], scaleMax: 5)
        XCTAssertEqual(board.leaderID, a.id)
    }

    func testMustHaveThresholdDisqualifiesRegardlessOfScore() {
        let (decision, _, _, _, _, b) = makeDecision()
        let board = ScoringEngine.scoreboard(decision: decision, evidence: [], scaleMax: 5)
        let scoreB = board.score(for: b.id)!
        // 1249 is above the 1100 ceiling on a lower-is-better must-have.
        XCTAssertTrue(scoreB.failsMustHave)
        XCTAssertFalse(scoreB.isEligibleLeader)
    }

    func testScoreIsRenormalisedOverEvaluatedCriteriaOnly() {
        var (decision, _, noise, _, a, _) = makeDecision()
        let optionIndex = decision.options.firstIndex { $0.id == a.id }!
        let evalIndex = decision.options[optionIndex].evaluations.firstIndex { $0.criterionID == noise.id }!
        decision.options[optionIndex].evaluations[evalIndex] = Evaluation(criterionID: noise.id)

        let board = ScoringEngine.scoreboard(decision: decision, evidence: [], scaleMax: 5)
        let score = board.score(for: a.id)!
        // Evaluated weight 70; sum 0.75×50 + 1.0×20 = 57.5 → 57.5/70×100
        XCTAssertEqual(score.weightedScore, 57.5 / 70 * 100, accuracy: 0.001)
        XCTAssertFalse(score.isComplete)
        XCTAssertEqual(score.incompleteMessage,
                       "Score is incomplete because 1 criterion has not been evaluated.")
    }

    func testAnExactTieProducesNoLeader() {
        var (decision, _, _, _, a, b) = makeDecision()
        let sourceIndex = decision.options.firstIndex { $0.id == a.id }!
        let targetIndex = decision.options.firstIndex { $0.id == b.id }!
        decision.options[targetIndex].evaluations = decision.options[sourceIndex].evaluations.map {
            var copy = $0
            copy.id = UUID()
            return copy
        }
        decision.options[targetIndex].estimatedCost = 949

        let board = ScoringEngine.scoreboard(decision: decision, evidence: [], scaleMax: 5)
        XCTAssertNil(board.leaderID, "The app must not invent a winner between equals")
    }

    func testRatingNormalisationSpansTheWholeScale() {
        let criterion = makeCriterion("R", weight: 100)
        var lowest = Evaluation(criterionID: criterion.id); lowest.rating = 1
        var highest = Evaluation(criterionID: criterion.id); highest.rating = 5

        XCTAssertEqual(ScoringEngine.normalized(evaluation: lowest, criterion: criterion, scaleMax: 5), 0)
        XCTAssertEqual(ScoringEngine.normalized(evaluation: highest, criterion: criterion, scaleMax: 5), 1)
        XCTAssertNil(ScoringEngine.normalized(evaluation: Evaluation(criterionID: criterion.id),
                                              criterion: criterion, scaleMax: 5))
    }

    func testRatingWithoutEvidenceOrReasonStaysPreliminary() {
        let (decision, price, _, _, a, _) = makeDecision()
        let option = decision.option(id: a.id)!
        let criterion = decision.criterion(id: price.id)!

        let status = ScoringEngine.status(evaluation: option.evaluation(for: price.id),
                                          option: option, criterion: criterion, evidence: [])
        XCTAssertEqual(status, .preliminary)
    }

    func testSupportingEvidencePromotesTheStatus() {
        let (decision, price, _, _, a, _) = makeDecision()
        var item = Evidence()
        item.decisionID = decision.id
        item.title = "Written quote"
        item.summary = "949"
        item.verification = .verified
        item.links = [EvidenceLink(optionID: a.id, criterionID: price.id, relation: .supports)]

        let option = decision.option(id: a.id)!
        let criterion = decision.criterion(id: price.id)!
        XCTAssertEqual(
            ScoringEngine.status(evaluation: option.evaluation(for: price.id),
                                 option: option, criterion: criterion, evidence: [item]),
            .evidenceSupported
        )
    }

    func testOutdatedEvidenceStopsCountingAsSupport() {
        let (decision, price, _, _, a, _) = makeDecision()
        var item = Evidence()
        item.decisionID = decision.id
        item.verification = .outdated
        item.summary = "old"
        item.links = [EvidenceLink(optionID: a.id, criterionID: price.id, relation: .supports)]

        let option = decision.option(id: a.id)!
        let criterion = decision.criterion(id: price.id)!
        XCTAssertEqual(
            ScoringEngine.status(evaluation: option.evaluation(for: price.id),
                                 option: option, criterion: criterion, evidence: [item]),
            .preliminary
        )
    }

    func testContradictingEvidenceIsReportedAsAConflict() {
        let (decision, price, _, _, a, _) = makeDecision()
        var against = Evidence()
        against.decisionID = decision.id
        against.summary = "measured 44"
        against.links = [EvidenceLink(optionID: a.id, criterionID: price.id, relation: .contradicts)]

        let option = decision.option(id: a.id)!
        let criterion = decision.criterion(id: price.id)!
        XCTAssertEqual(
            ScoringEngine.status(evaluation: option.evaluation(for: price.id),
                                 option: option, criterion: criterion, evidence: [against]),
            .conflictingEvidence
        )
    }
}
