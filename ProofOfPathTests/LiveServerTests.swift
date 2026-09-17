//
//  LiveServerTests.swift
//  ProofOfPathTests
//
//  Drives the real store and API client against a running ProofPath server and
//  checks after every step that the server holds exactly what the app shows.
//
//  Start the server first (see Server/README.md), then run the tests. Without
//  a reachable server the test is skipped. Another address can be given with
//  the TEST_RUNNER_POP_TEST_API environment variable.
//

import XCTest
@testable import ProofOfPath

@MainActor
final class LiveServerTests: XCTestCase {

    private var baseURL: URL {
        URL(string: ProcessInfo.processInfo.environment["POP_TEST_API"] ?? "http://127.0.0.1:8080/api/v1")!
    }

    private var keychainService = ""
    private var cacheDirectory: URL!

    override func setUp() async throws {
        keychainService = "live-tests-\(UUID().uuidString)"
        cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID().uuidString)")
        var request = URLRequest(url: baseURL.appendingPathComponent("bootstrap"))
        request.timeoutInterval = 3
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 401 else {
                throw XCTSkip("No ProofPath API at \(baseURL)")
            }
        } catch let skip as XCTSkip {
            throw skip
        } catch {
            throw XCTSkip("No ProofPath API at \(baseURL): \(error.localizedDescription)")
        }
    }

    override func tearDown() async throws {
        CredentialStore(keychain: KeychainStore(service: keychainService)).resetDevice()
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    func testEveryKindOfChangeReachesTheServerExactly() async throws {
        let credentials = CredentialStore(keychain: KeychainStore(service: keychainService))
        let api = APIClient(baseURL: baseURL, credentials: credentials)
        let store = AppStore(api: api, credentials: credentials, cache: DataRepository(directory: cacheDirectory), monitor: nil)

        // First launch: the device signs in and loads an empty account.
        store.start()
        try await waitUntil { store.phase == .ready }
        XCTAssertEqual(store.connection, .online)
        XCTAssertTrue(store.state.decisions.isEmpty)
        XCTAssertFalse(store.state.settings.onboardingCompleted)

        func step(_ name: String, _ intent: AppIntent, file: StaticString = #filePath, line: UInt = #line) async throws {
            let saved = await store.perform(intent)
            XCTAssertTrue(saved, "\(name) was not saved: \(store.state.toast?.detail ?? store.state.toast?.message ?? "")", file: file, line: line)
            try await assertInSync(store, api, after: name, file: file, line: line)
        }

        // Settings
        try await step("complete onboarding", .completeOnboarding)
        try await step("currency", .setDefaultCurrency("EUR"))
        try await step("rating scale", .setRatingScale(10))
        try await step("owner", .setOwnerName("Анна 👩‍💻"))
        try await step("haptics", .setHapticsEnabled(false))
        try await step("lead days", .setReminderLeadDays(7))

        // Decision
        var draft = makeDraft("Laptop for design work", outcome: "Fast, quiet, lasts 4 years")
        draft.templateID = "product"
        draft.templateCriteria = DecisionTemplateLibrary.template(id: "product")?.criteria ?? []
        draft.budgetMin = 900
        draft.budgetMax = 1600
        draft.currencyCode = "EUR"
        draft.deadline = Date().addingTimeInterval(86_400 * 30)
        var budget = HardConstraint()
        budget.title = "Under 1500"
        budget.check = .maximumCost(1500)
        draft.hardConstraints = [budget]
        try await step("create decision", .createDecision(draft))
        let decisionID = try XCTUnwrap(store.state.decisions.first?.id)
        func decision() throws -> Decision { try XCTUnwrap(store.state.decision(id: decisionID)) }

        var brief = DecisionBriefEdit(decision: try decision())
        brief.title = "Laptop"
        brief.budgetMin = nil
        brief.preferredCompletionDate = Date().addingTimeInterval(86_400 * 10)
        try await step("edit brief, clearing a value", .updateDecisionBrief(decisionID: decisionID, brief: brief))
        XCTAssertNil(try decision().budgetMin)
        try await step("cost horizon", .setCostHorizon(decisionID: decisionID, horizon: .fiveYears))

        // Criteria
        var battery = Criterion()
        battery.name = "Battery hours"
        battery.kind = .higherIsBetter
        battery.weight = 20
        try await step("add criterion", .addCriterion(decisionID: decisionID, criterion: battery))
        var ports = Criterion()
        ports.name = "Has HDMI"
        ports.kind = .yesNo
        ports.importance = .mustHave
        try await step("add yes/no criterion", .addCriterion(decisionID: decisionID, criterion: ports))
        battery.details = "Measured in reviews"
        try await step("update criterion", .updateCriterion(decisionID: decisionID, criterion: battery))
        try await step("criterion weight", .setCriterionWeight(decisionID: decisionID, criterionID: battery.id, weight: 33.3))
        try await step("balance weights", .balanceCriteriaWeights(decisionID: decisionID))
        try await step("duplicate criterion", .duplicateCriterion(decisionID: decisionID, criterionID: battery.id))
        try await step("move criteria", .moveCriteria(decisionID: decisionID, from: IndexSet(integer: 0), to: 3))
        try await step("apply structure", .applyTemplateCriteria(decisionID: decisionID, templateID: "product",
                                                                  criteria: Array((DecisionTemplateLibrary.template(id: "product")?.criteria ?? []).prefix(1))))

        // Constraints
        var atLeast = HardConstraint()
        atLeast.title = "Battery at least 8h"
        atLeast.check = .criterionAtLeast(criterionID: battery.id, value: 8)
        try await step("criterion constraint", .addConstraint(decisionID: decisionID, constraint: atLeast))
        var manual = HardConstraint()
        manual.title = "Fits the bag"
        try await step("manual constraint", .addConstraint(decisionID: decisionID, constraint: manual))
        atLeast.details = "Reviewers' numbers"
        try await step("update constraint", .updateConstraint(decisionID: decisionID, constraint: atLeast))

        // Options
        var mac = makeOption("MacBook Air", cost: 1299)
        mac.providerOrBrand = "Apple"
        mac.cost.recurringCost = 9.99
        mac.cost.recurringPeriod = .monthly
        mac.website = "https://example.com/mac"
        try await step("add option", .addOption(decisionID: decisionID, option: mac))
        var think = makeOption("ThinkPad X1", cost: 1450)
        think.cost.requiredExtras = 49
        try await step("add second option", .addOption(decisionID: decisionID, option: think))
        let dell = makeOption("XPS 13", cost: 1700)
        try await step("add third option", .addOption(decisionID: decisionID, option: dell))
        mac.keyDetails = "M3, 16 GB"
        mac.cost.assumptions = "Student discount"
        try await step("update option", .updateOption(decisionID: decisionID, option: mac))
        try await step("option status", .setOptionStatus(decisionID: decisionID, optionID: think.id, status: .shortlisted))
        try await step("duplicate option", .duplicateOption(decisionID: decisionID, optionID: mac.id))
        try await step("move options", .moveOptions(decisionID: decisionID, from: IndexSet(integer: 0), to: 2))
        try await step("manual constraint status", .setManualConstraintStatus(decisionID: decisionID, optionID: mac.id, constraintID: manual.id, status: .meets))

        let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        guard case .success(let photo) = store.importImageData(pixel, name: "Mac photo") else { return XCTFail("image import") }
        try await step("option image (uploads a file)", .setOptionImage(decisionID: decisionID, optionID: mac.id, fileName: photo.fileName))

        // Evaluations
        try await step("rating", .saveEvaluation(decisionID: decisionID, optionID: mac.id,
                                                 evaluation: makeEvaluation(try decision().sortedCriteria[0].id, rating: 9, reason: "Benchmarks", confidence: .high)))
        try await step("measured value", .saveEvaluation(decisionID: decisionID, optionID: mac.id,
                                                         evaluation: makeEvaluation(battery.id, value: "15.5")))
        try await step("yes/no", .saveEvaluation(decisionID: decisionID, optionID: think.id,
                                                 evaluation: makeEvaluation(ports.id, bool: true)))
        try await step("replace evaluation", .saveEvaluation(decisionID: decisionID, optionID: mac.id,
                                                             evaluation: makeEvaluation(battery.id, value: "16")))
        try await step("clear evaluation", .clearEvaluation(decisionID: decisionID, optionID: think.id, criterionID: ports.id))

        // Evidence with an uploaded file
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("Quote-\(UUID().uuidString).pdf")
        try Data("%PDF-1.4 quote".utf8).write(to: fileURL)
        guard case .success(let quoteFile) = store.importAttachment(from: fileURL) else { return XCTFail("file import") }
        var quote = Evidence()
        quote.decisionID = decisionID
        quote.title = "Price quote"
        quote.type = .receipt
        quote.summary = "1299 with discount"
        quote.attachment = quoteFile
        var link = EvidenceLink()
        link.optionID = mac.id
        quote.links = [link]
        try await step("evidence with file", .addEvidence(quote))
        quote = try XCTUnwrap(store.state.evidenceItem(id: quote.id))
        quote.source = "https://example.com/quote"
        try await step("update evidence", .updateEvidence(quote))
        try await step("verify evidence", .setEvidenceVerification(evidenceID: quote.id, status: .verified))
        var batteryLink = EvidenceLink()
        batteryLink.optionID = mac.id
        batteryLink.criterionID = battery.id
        batteryLink.relation = .supports
        try await step("add link", .addEvidenceLink(evidenceID: quote.id, link: batteryLink))
        batteryLink.relation = .contradicts
        try await step("update link", .updateEvidenceLink(evidenceID: quote.id, link: batteryLink))
        try await step("remove link", .removeEvidenceLink(evidenceID: quote.id, linkID: link.id))

        var note = Evidence()
        note.decisionID = decisionID
        note.type = .personalNote
        note.summary = "Store visit"
        try await step("second evidence", .addEvidence(note))

        // Claims
        var claim = Claim()
        claim.text = "18 hours battery"
        claim.claimedBy = "Apple"
        claim.optionID = mac.id
        try await step("add claim", .addClaim(decisionID: decisionID, claim: claim))
        claim.whyItMatters = "Travel"
        try await step("update claim", .updateClaim(decisionID: decisionID, claim: claim))
        try await step("claim status", .setClaimStatus(decisionID: decisionID, claimID: claim.id, status: .partiallySupported))
        try await step("support claim", .linkClaimEvidence(decisionID: decisionID, claimID: claim.id, evidenceID: quote.id, supporting: true))
        try await step("contradict claim", .linkClaimEvidence(decisionID: decisionID, claimID: claim.id, evidenceID: note.id, supporting: false))
        try await step("unlink claim evidence", .unlinkClaimEvidence(decisionID: decisionID, claimID: claim.id, evidenceID: note.id))
        try await step("request verification", .requestClaimVerification(decisionID: decisionID, claimID: claim.id, deadline: Date().addingTimeInterval(86_400)))

        // Risks
        var risk = Risk()
        risk.title = "Battery degrades"
        risk.optionID = mac.id
        risk.likelihood = .high
        risk.impact = .high
        try await step("add risk", .addRisk(decisionID: decisionID, risk: risk))
        risk.warningSigns = "Cycle count"
        try await step("update risk", .updateRisk(decisionID: decisionID, risk: risk))
        try await step("accept risk", .setRiskState(decisionID: decisionID, riskID: risk.id, state: .accepted, reason: "Warranty covers it"))
        var thinkRisk = Risk()
        thinkRisk.title = "Fan noise"
        thinkRisk.optionID = think.id
        try await step("risk on another option", .addRisk(decisionID: decisionID, risk: thinkRisk))

        // Scenarios
        var scenario = Scenario()
        scenario.name = "Tight budget"
        scenario.preset = .lowerBudget
        scenario.budgetLimit = 1300
        scenario.weightOverrides = [battery.id.uuidString: 70]
        scenario.excludedOptionIDs = [dell.id]
        try await step("add scenario", .addScenario(decisionID: decisionID, scenario: scenario))
        scenario.weightOverrides = [:]
        try await step("update scenario, clearing overrides", .updateScenario(decisionID: decisionID, scenario: scenario))
        try await step("duplicate scenario", .duplicateScenario(decisionID: decisionID, scenarioID: scenario.id))
        try await step("delete scenario", .deleteScenario(decisionID: decisionID, scenarioID: scenario.id))

        // Open questions
        let question = AcceptedUnknownDraft(questionKey: "eval:\(dell.id.uuidString):\(battery.id.uuidString)",
                                            kind: .unevaluatedCriterion, label: "XPS battery", reason: "Out of budget anyway")
        try await step("accept unknown", .acceptUnknown(decisionID: decisionID, question: question))
        let unknownID = try XCTUnwrap(try decision().acceptedUnknowns.first?.id)
        var task = FollowUpTask(title: "Call the store")
        task.dueDate = Date().addingTimeInterval(3600)
        try await step("add follow-up", .addFollowUp(decisionID: decisionID, task: task))
        try await step("toggle follow-up", .toggleFollowUp(decisionID: decisionID, taskID: task.id))
        try await step("remove accepted unknown", .removeAcceptedUnknown(decisionID: decisionID, unknownID: unknownID))
        try await step("delete follow-up", .deleteFollowUp(decisionID: decisionID, taskID: task.id))

        // Delete the constraints so the chosen option can be finalized.
        try await step("delete constraint", .deleteConstraint(decisionID: decisionID, constraintID: atLeast.id))
        try await step("delete manual constraint", .deleteConstraint(decisionID: decisionID, constraintID: manual.id))
        try await step("delete budget constraint", .deleteConstraint(decisionID: decisionID, constraintID: budget.id))

        // Finalize, reopen, finalize again
        var record = FinalDecision()
        record.selectedOptionID = mac.id
        record.keyEvidenceIDs = [quote.id]
        record.confidence = 4
        try await step("final decision draft", .saveFinalDecisionDraft(decisionID: decisionID, decisionRecord: record))
        record.whyThisOption = "Best battery for the price"
        try await step("finalize", .finalizeDecision(decisionID: decisionID, decisionRecord: record))
        XCTAssertEqual(try decision().status, .finalized)
        XCTAssertEqual(try decision().snapshots.count, 1)
        try await step("reopen", .reopenDecision(decisionID: decisionID, reason: "New model announced"))
        record.acceptedTradeOffs = "Fewer ports"
        try await step("finalize again", .finalizeDecision(decisionID: decisionID, decisionRecord: record))
        XCTAssertEqual(try decision().snapshots.map(\.version), [1, 2])

        // Outcome review
        var review = OutcomeReview()
        review.expectedOutcome = "Fast"
        try await step("review draft", .saveOutcomeReviewDraft(decisionID: decisionID, review: review))
        review.satisfaction = .satisfied
        review.wouldChooseAgain = .yes
        review.occurredRiskIDs = [risk.id]
        try await step("complete review", .completeOutcomeReview(decisionID: decisionID, review: review))
        try await step("mark completed", .markPurchaseCompleted(decisionID: decisionID))

        // Status changes
        try await step("pause", .setDecisionStatus(decisionID: decisionID, status: .paused))
        try await step("archive", .archiveDecision(decisionID))
        try await step("restore", .restoreDecision(decisionID))

        // Deletions and what cascades from them
        try await step("delete claim", .deleteClaim(decisionID: decisionID, claimID: claim.id))
        try await step("delete risk", .deleteRisk(decisionID: decisionID, riskID: thinkRisk.id))
        try await step("delete criterion", .deleteCriterion(decisionID: decisionID, criterionID: battery.id))
        try await step("delete option", .deleteOption(decisionID: decisionID, optionID: think.id))
        try await step("delete evidence", .deleteEvidence(note.id))

        try await step("second decision", .createDecision(makeDraft("Holiday")))
        let holiday = try XCTUnwrap(store.state.decisions.first { $0.title == "Holiday" }?.id)
        var inbox = Evidence()
        inbox.decisionID = holiday
        inbox.summary = "Brochure"
        try await step("evidence on second decision", .addEvidence(inbox))
        try await step("delete second decision", .deleteDecision(holiday))

        // Files are on the server: a fresh device cache can fetch them.
        let image = try await api.download(fileName: photo.fileName)
        XCTAssertEqual(image, pixel)

        // Backup round trip through the server
        let backup = store.state.data
        let decisionCount = backup.decisions.count
        try await stepWithoutSync(store, "import backup", .replaceAllData(backup))
        XCTAssertEqual(store.state.decisions.count, decisionCount)
        XCTAssertNotEqual(store.state.decisions.first?.id, decisionID, "Imported records get fresh ids")
        try await assertInSync(store, api, after: "import")

        // Delete everything
        try await stepWithoutSync(store, "delete all data", .deleteAllData)
        XCTAssertTrue(store.state.decisions.isEmpty)
        XCTAssertTrue(store.state.settings.onboardingCompleted)
        try await assertInSync(store, api, after: "delete all data")
        try await stepWithoutSync(store, "clean up", .deleteAllData)
    }

    // MARK: - Helpers

    private func stepWithoutSync(_ store: AppStore, _ name: String, _ intent: AppIntent) async throws {
        let saved = await store.perform(intent)
        XCTAssertTrue(saved, "\(name) failed: \(store.state.toast?.detail ?? store.state.toast?.message ?? "")")
    }

    /// The server's copy, decoded exactly as the app decodes it, must equal what
    /// the app shows. Local dates carry sub-millisecond digits the wire format
    /// does not, so the local copy goes through the same JSON first.
    private func assertInSync(_ store: AppStore, _ api: APIClient, after step: String,
                              file: StaticString = #filePath, line: UInt = #line) async throws {
        let server = try await api.bootstrap().data
        let local = try POPJSON.makeDecoder().decode(AppData.self, from: POPJSON.makeEncoder().encode(store.state.data))
        let lhs = normalized(local)
        let rhs = normalized(server)
        guard lhs != rhs else { return }
        let encoder = POPJSON.makeEncoder(pretty: true)
        let localText = String(decoding: try encoder.encode(lhs), as: UTF8.self).components(separatedBy: "\n")
        let serverText = String(decoding: try encoder.encode(rhs), as: UTF8.self).components(separatedBy: "\n")
        let firstDifference = zip(localText, serverText).enumerated().first { $0.element.0 != $0.element.1 }
        let context = firstDifference.map { index, pair in
            "line \(index): app \(pair.0.trimmingCharacters(in: .whitespaces)) · server \(pair.1.trimmingCharacters(in: .whitespaces))"
        } ?? "lengths differ: \(localText.count) vs \(serverText.count)"
        XCTFail("Out of sync after “\(step)”: \(context)", file: file, line: line)
    }

    /// Arrays whose order the app does not rely on are compared as sets.
    private func normalized(_ data: AppData) -> AppData {
        var data = data
        for d in data.decisions.indices {
            data.decisions[d].criteria.sort { $0.id.uuidString < $1.id.uuidString }
            data.decisions[d].options.sort { $0.id.uuidString < $1.id.uuidString }
            for o in data.decisions[d].options.indices {
                data.decisions[d].options[o].evaluations.sort { $0.criterionID.uuidString < $1.criterionID.uuidString }
            }
        }
        data.decisions.sort { $0.id.uuidString < $1.id.uuidString }
        return data
    }

    private func waitUntil(timeout: TimeInterval = 15, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(condition(), "Timed out")
    }
}
