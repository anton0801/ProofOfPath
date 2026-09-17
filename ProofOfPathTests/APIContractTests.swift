//
//  APIContractTests.swift
//  ProofOfPathTests
//
//  The JSON the app sends, and how a user action becomes REST operations.
//

import XCTest
@testable import ProofOfPath

@MainActor
final class APIContractTests: XCTestCase {

    // MARK: - Constraint check wire format

    func testConstraintChecksEncodeAsFlatObjects() throws {
        let criterion = UUID()
        let cases: [(ConstraintCheck, [String: Any])] = [
            (.maximumCost(1100), ["type": "maximumCost", "value": 1100]),
            (.minimumCost(10.5), ["type": "minimumCost", "value": 10.5]),
            (.criterionAtLeast(criterionID: criterion, value: 3), ["type": "criterionAtLeast", "criterionID": criterion.uuidString, "value": 3]),
            (.criterionAtMost(criterionID: criterion, value: 7), ["type": "criterionAtMost", "criterionID": criterion.uuidString, "value": 7]),
            (.criterionMustBeYes(criterionID: criterion), ["type": "criterionMustBeYes", "criterionID": criterion.uuidString]),
            (.manual, ["type": "manual"]),
        ]
        for (check, expected) in cases {
            let data = try POPJSON.makeEncoder().encode(check)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
            XCTAssertEqual(object, expected as NSDictionary, "\(check)")
            XCTAssertEqual(try POPJSON.makeDecoder().decode(ConstraintCheck.self, from: data), check)
        }
    }

    func testVersionOneConstraintChecksStillDecode() throws {
        let criterion = UUID()
        let legacy: [(String, ConstraintCheck)] = [
            (#"{"maximumCost":{"_0":1100}}"#, .maximumCost(1100)),
            (#"{"minimumCost":{"_0":5}}"#, .minimumCost(5)),
            (#"{"criterionAtLeast":{"criterionID":"\#(criterion.uuidString)","value":3}}"#, .criterionAtLeast(criterionID: criterion, value: 3)),
            (#"{"criterionAtMost":{"criterionID":"\#(criterion.uuidString)","value":2}}"#, .criterionAtMost(criterionID: criterion, value: 2)),
            (#"{"criterionMustBeYes":{"criterionID":"\#(criterion.uuidString)"}}"#, .criterionMustBeYes(criterionID: criterion)),
            (#"{"manual":{}}"#, .manual),
        ]
        for (json, expected) in legacy {
            XCTAssertEqual(try POPJSON.makeDecoder().decode(ConstraintCheck.self, from: Data(json.utf8)), expected, json)
        }
        XCTAssertThrowsError(try POPJSON.makeDecoder().decode(ConstraintCheck.self, from: Data(#"{"magic":{}}"#.utf8)))
    }

    func testAVersionOneBackupWithSyncFieldsStillImports() throws {
        let json = """
        {"schemaVersion":2,"decisions":[{"id":"\(UUID().uuidString)","title":"Old","category":"purchase","customCategoryName":"",
        "desiredOutcome":"x","whyItMatters":"","peopleAffected":"","currencyCode":"USD","owner":"","status":"active",
        "hardConstraints":[{"id":"\(UUID().uuidString)","title":"Budget","details":"","check":{"maximumCost":{"_0":900}},"createdAt":"2025-01-01T10:00:00Z"}],
        "criteria":[],"options":[],"claims":[],"risks":[],"scenarios":[],"activity":[],"snapshots":[],"acceptedUnknowns":[],
        "followUpTasks":[],"costHorizon":"threeYears","createdAt":"2025-01-01T10:00:00Z","updatedAt":"2025-01-01T10:00:00Z",
        "syncStored":{"revision":0,"state":"localOnly"}}],
        "evidence":[],"settings":{"defaultCurrency":"USD","ratingScaleMax":5,"remindersEnabled":false,"reminderLeadDays":3,
        "hapticsEnabled":true,"ownerName":"","onboardingCompleted":true},
        "tombstonesStored":[],"outboxStored":[],"accountStored":{"mode":"local","deviceID":"x"}}
        """
        let data = try POPJSON.makeDecoder().decode(AppData.self, from: Data(json.utf8))
        XCTAssertEqual(data.decisions.first?.hardConstraints.first?.check, .maximumCost(900))
    }

    // MARK: - Planning

    private func sample() -> AppState {
        var state = AppState()
        state.settings.onboardingCompleted = true
        var draft = makeDraft("Laptop")
        draft.templateCriteria = [
            TemplateCriterion(name: "Performance", details: "", kind: .ratingScale, importance: .mustHave, measurementMethod: "", suggestedWeight: 60),
            TemplateCriterion(name: "Battery", details: "", kind: .higherIsBetter, importance: .niceToHave, measurementMethod: "", suggestedWeight: 40),
        ]
        state = reduce(state, .createDecision(draft))
        let decisionID = state.decisions[0].id
        state = reduce(state, .addOption(decisionID: decisionID, option: makeOption("A", cost: 900)))
        state = reduce(state, .addOption(decisionID: decisionID, option: makeOption("B", cost: 1200, sortIndex: 1)))
        return state
    }

    func testNoChangeMeansNoRequest() throws {
        let state = sample()
        XCTAssertTrue(try ChangePlanner.plan(from: state.data, to: state.data).isEmpty)
    }

    func testCreatingADecisionWritesParentsBeforeChildren() throws {
        var draft = makeDraft("Move")
        draft.templateCriteria = [TemplateCriterion(name: "Rent", details: "", kind: .lowerIsBetter, importance: .mustHave, measurementMethod: "", suggestedWeight: 100)]
        draft.hardConstraints = [HardConstraint(title: "Under 2000", check: .maximumCost(2000))]
        let after = reduce(AppState(), .createDecision(draft))
        let plan = try ChangePlanner.plan(from: AppState().data, to: after.data)
        let decision = after.decisions[0]

        let paths = plan.operations.map(\.description)
        XCTAssertEqual(paths.first, "PUT /decisions/\(decision.id.uuidString)")
        let constraint = try XCTUnwrap(paths.firstIndex(of: "PUT /decisions/\(decision.id.uuidString)/constraints/\(decision.hardConstraints[0].id.uuidString)"))
        let criterion = try XCTUnwrap(paths.firstIndex(of: "PUT /decisions/\(decision.id.uuidString)/criteria/\(decision.criteria[0].id.uuidString)"))
        let activity = try XCTUnwrap(paths.firstIndex(of: "POST /decisions/\(decision.id.uuidString)/activity"))
        XCTAssertLessThan(constraint, criterion)
        XCTAssertLessThan(criterion, activity)

        // The decision body carries only the decision's own fields.
        let body = try XCTUnwrap(plan.operations[0].body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["title"] as? String, "Move")
        XCTAssertEqual((object["criteria"] as? [Any])?.count, 0)
        XCTAssertNil(object["finalDecision"])
    }

    func testDeletingAnOptionRunsAfterEveryWrite() throws {
        var state = sample()
        let decisionID = state.decisions[0].id
        let option = state.decisions[0].sortedOptions[0]
        let criterion = state.decisions[0].sortedCriteria[0]
        state = reduce(state, .saveEvaluation(decisionID: decisionID, optionID: option.id, evaluation: makeEvaluation(criterion.id, rating: 4)))
        var evidence = Evidence()
        evidence.decisionID = decisionID
        evidence.summary = "Spec sheet"
        evidence.links = [EvidenceLink(optionID: option.id, criterionID: criterion.id, relation: .supports)]
        state = reduce(state, .addEvidence(evidence))
        var risk = Risk()
        risk.title = "Battery"
        risk.optionID = option.id
        state = reduce(state, .addRisk(decisionID: decisionID, risk: risk))

        let after = reduce(state, .deleteOption(decisionID: decisionID, optionID: option.id))
        let plan = try ChangePlanner.plan(from: state.data, to: after.data)
        let descriptions = plan.operations.map(\.description)

        let lastWrite = try XCTUnwrap(plan.operations.lastIndex { $0.method != .delete })
        let firstDelete = try XCTUnwrap(plan.operations.firstIndex { $0.method == .delete })
        XCTAssertLessThan(lastWrite, firstDelete, "Deletions must come after every write")
        XCTAssertTrue(descriptions.contains("PUT /evidence/\(evidence.id.uuidString)"), "The evidence loses its link first")
        XCTAssertTrue(descriptions.contains("DELETE /options/\(option.id.uuidString)"))
        XCTAssertTrue(descriptions.contains("DELETE /risks/\(risk.id.uuidString)"))
        XCTAssertFalse(descriptions.contains { $0.contains("/evaluations/") }, "Evaluations go with their option on the server")
        XCTAssertEqual(descriptions.filter { $0 == "DELETE /options/\(option.id.uuidString)" }.count, 1)
    }

    func testDeletingADecisionSendsOneDeleteNotOnePerChild() throws {
        var state = sample()
        let decisionID = state.decisions[0].id
        var evidence = Evidence()
        evidence.decisionID = decisionID
        evidence.summary = "Quote"
        state = reduce(state, .addEvidence(evidence))
        let after = reduce(state, .deleteDecision(decisionID))
        let plan = try ChangePlanner.plan(from: state.data, to: after.data)
        XCTAssertEqual(Set(plan.operations.map(\.description)), [
            "DELETE /decisions/\(decisionID.uuidString)",
            "DELETE /evidence/\(evidence.id.uuidString)",
        ])
    }

    func testClearingAnEvaluationReplacesItWithAnEmptyOne() throws {
        var state = sample()
        let decisionID = state.decisions[0].id
        let option = state.decisions[0].sortedOptions[0]
        let criterion = state.decisions[0].sortedCriteria[0]
        state = reduce(state, .saveEvaluation(decisionID: decisionID, optionID: option.id, evaluation: makeEvaluation(criterion.id, rating: 4)))
        let after = reduce(state, .clearEvaluation(decisionID: decisionID, optionID: option.id, criterionID: criterion.id))
        let plan = try ChangePlanner.plan(from: state.data, to: after.data)
        let put = try XCTUnwrap(plan.operations.first { $0.description == "PUT /options/\(option.id.uuidString)/evaluations/\(criterion.id.uuidString)" })
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(put.body)) as? [String: Any])
        XCTAssertNil(body["rating"], "A cleared evaluation carries no rating")

        // An evaluation removed from the list altogether is deleted.
        var removed = state
        let optionIndex = try XCTUnwrap(removed.decisions[0].options.firstIndex { $0.id == option.id })
        let expected = Set(removed.decisions[0].options[optionIndex].evaluations.map {
            "DELETE /options/\(option.id.uuidString)/evaluations/\($0.criterionID.uuidString)"
        })
        removed.decisions[0].options[optionIndex].evaluations = []
        let deletePlan = try ChangePlanner.plan(from: state.data, to: removed.data)
        XCTAssertEqual(Set(deletePlan.operations.map(\.description)), expected)
        XCTAssertTrue(expected.contains("DELETE /options/\(option.id.uuidString)/evaluations/\(criterion.id.uuidString)"))
    }

    func testOnlyNewFilesAreUploaded() throws {
        var state = sample()
        let decisionID = state.decisions[0].id
        var evidence = Evidence()
        evidence.decisionID = decisionID
        evidence.attachment = EvidenceAttachment(fileName: "\(UUID().uuidString).pdf", originalName: "Quote.pdf", byteSize: 10, isImage: false)
        let withFile = reduce(state, .addEvidence(evidence))
        let firstPlan = try ChangePlanner.plan(from: state.data, to: withFile.data)
        XCTAssertEqual(Array(firstPlan.uploads.keys), [evidence.attachment!.fileName])

        state = withFile
        let edited = reduce(state, .setEvidenceVerification(evidenceID: evidence.id, status: .verified))
        XCTAssertTrue(try ChangePlanner.plan(from: state.data, to: edited.data).uploads.isEmpty)

        let optionID = state.decisions[0].sortedOptions[0].id
        let image = "\(UUID().uuidString).jpg"
        let withImage = reduce(state, .setOptionImage(decisionID: decisionID, optionID: optionID, fileName: image))
        XCTAssertEqual(Array(try ChangePlanner.plan(from: state.data, to: withImage.data).uploads.keys), [image])
    }

    func testTheBatchBodyIsValidJSON() throws {
        let state = sample()
        let plan = try ChangePlanner.plan(from: AppState().data, to: state.data)
        let body = try APIClient.batchBody(plan.operations)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let operations = try XCTUnwrap(object["operations"] as? [[String: Any]])
        XCTAssertEqual(operations.count, plan.operations.count)
        XCTAssertEqual(operations.first?["method"] as? String, "PUT")
        XCTAssertNotNil(operations.first?["body"] as? [String: Any])
        let emptyMap = try APIClient.batchBody([APIOperation(method: .put, path: "/x", body: try POPJSON.makeEncoder().encode(Scenario()))])
        XCTAssertTrue(String(decoding: emptyMap, as: UTF8.self).contains(#""weightOverrides":{}"#), "An empty dictionary must stay an object")
    }

    // MARK: - Keeping data inside what the server accepts

    func testDanglingReferencesAreRepaired() {
        var state = sample()
        let decisionID = state.decisions[0].id
        state.decisions[0].options[0].manualConstraintStatus[UUID().uuidString] = .meets
        state.decisions[0].options[0].evaluations = [makeEvaluation(UUID(), rating: 3)]
        var claim = Claim()
        claim.optionID = UUID()
        claim.supportingEvidenceIDs = [UUID()]
        state.decisions[0].claims = [claim]
        var scenario = Scenario()
        scenario.weightOverrides = [UUID().uuidString: 50]
        scenario.excludedOptionIDs = [UUID()]
        state.decisions[0].scenarios = [scenario]
        var final = FinalDecision()
        final.selectedOptionID = UUID()
        state.decisions[0].finalDecision = final
        var evidence = Evidence()
        evidence.decisionID = decisionID
        evidence.links = [EvidenceLink(optionID: UUID(), criterionID: nil, relation: .supports)]
        var orphan = Evidence()
        orphan.decisionID = UUID()
        state.evidence = [evidence, orphan]

        let fixed = state.data.conformedToAPI()
        XCTAssertTrue(fixed.decisions[0].options[0].manualConstraintStatus.isEmpty)
        XCTAssertTrue(fixed.decisions[0].options[0].evaluations.isEmpty)
        XCTAssertNil(fixed.decisions[0].claims[0].optionID)
        XCTAssertTrue(fixed.decisions[0].claims[0].supportingEvidenceIDs.isEmpty)
        XCTAssertTrue(fixed.decisions[0].scenarios[0].weightOverrides.isEmpty)
        XCTAssertTrue(fixed.decisions[0].scenarios[0].excludedOptionIDs.isEmpty)
        XCTAssertNil(fixed.decisions[0].finalDecision?.selectedOptionID)
        XCTAssertTrue(fixed.evidence[0].links.isEmpty)
        XCTAssertNil(fixed.evidence[1].decisionID)
    }

    func testLongTextIsCutToTheServerLimitInCodePoints() {
        var state = sample()
        state.decisions[0].title = String(repeating: "a", count: 300)
        // Each family emoji is several code points but one visible character.
        state.decisions[0].options[0].name = String(repeating: "👨‍👩‍👧‍👦", count: 100)
        let fixed = state.data.conformedToAPI()
        XCTAssertEqual(fixed.decisions[0].title.unicodeScalars.count, 255)
        let name = fixed.decisions[0].options[0].name
        XCTAssertLessThanOrEqual(name.unicodeScalars.count, 255)
        XCTAssertTrue(name.allSatisfy { $0 == "👨‍👩‍👧‍👦" }, "Cut between whole characters")
    }

    func testAttachmentNamesFollowTheServerRule() {
        XCTAssertTrue(AttachmentStore.isValidFileName("\(UUID().uuidString).jpg"))
        XCTAssertFalse(AttachmentStore.isValidFileName("\(UUID().uuidString.lowercased()).jpg"))
        XCTAssertFalse(AttachmentStore.isValidFileName("../\(UUID().uuidString).jpg"))
        XCTAssertFalse(AttachmentStore.isValidFileName("\(UUID().uuidString).tar.gz"))
    }
}

private extension EvidenceLink {
    init(optionID: UUID?, criterionID: UUID?, relation: EvidenceRelation) {
        self.init()
        self.optionID = optionID
        self.criterionID = criterionID
        self.relation = relation
    }
}

private extension HardConstraint {
    init(title: String, check: ConstraintCheck) {
        self.init()
        self.title = title
        self.check = check
    }
}
