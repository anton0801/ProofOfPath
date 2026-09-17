//
//  RetryAndRepeatTests.swift
//  ProofOfPathTests
//
//  Saving again after a lost response, and tapping twice before the first save
//  lands, must never duplicate or undo anything.
//

import XCTest
@testable import ProofOfPath

@MainActor
final class RetryAndRepeatTests: XCTestCase {

    private func workspace() -> (AppState, UUID) {
        var state = AppState()
        state.settings.onboardingCompleted = true
        state = reduce(state, .createDecision(makeDraft("Laptop")))
        return (state, state.decisions[0].id)
    }

    func testCreatingTheSameDecisionTwiceKeepsOne() {
        var draft = makeDraft("Laptop")
        let once = reduce(AppState(), .createDecision(draft))
        draft.title = "Laptop (typed again)"
        let twice = reduce(once, .createDecision(draft))
        XCTAssertEqual(twice.decisions.count, 1)
        XCTAssertEqual(twice.decisions[0].id, draft.id)
    }

    func testAddingARecordThatAlreadyExistsUpdatesIt() {
        var (state, decisionID) = workspace()
        var option = makeOption("First name")
        state = reduce(state, .addOption(decisionID: decisionID, option: option))
        option.name = "Corrected name"
        state = reduce(state, .addOption(decisionID: decisionID, option: option))
        XCTAssertEqual(state.decisions[0].options.map(\.name), ["Corrected name"])

        var evidence = Evidence()
        evidence.decisionID = decisionID
        evidence.summary = "Quote"
        state = reduce(state, .addEvidence(evidence))
        state = reduce(state, .addEvidence(evidence))
        XCTAssertEqual(state.evidence.count, 1)

        let task = FollowUpTask(title: "Call")
        state = reduce(state, .addFollowUp(decisionID: decisionID, task: task))
        state = reduce(state, .addFollowUp(decisionID: decisionID, task: task))
        XCTAssertEqual(state.decisions[0].followUpTasks.count, 1)

        var claim = Claim()
        claim.text = "Fast"
        state = reduce(state, .addClaim(decisionID: decisionID, claim: claim))
        state = reduce(state, .addClaim(decisionID: decisionID, claim: claim))
        XCTAssertEqual(state.decisions[0].claims.count, 1)
    }

    func testOrderingByIdIsTheSameWhenSentTwice() {
        var (state, decisionID) = workspace()
        for name in ["A", "B", "C"] {
            state = reduce(state, .addCriterion(decisionID: decisionID, criterion: makeCriterion(name)))
        }
        let ids = state.decisions[0].sortedCriteria.map(\.id)
        let wanted = [ids[1], ids[0], ids[2]]
        let once = reduce(state, .setCriteriaOrder(decisionID: decisionID, ids: wanted))
        let twice = reduce(once, .setCriteriaOrder(decisionID: decisionID, ids: wanted))
        XCTAssertEqual(once.decisions[0].sortedCriteria.map(\.id), wanted)
        XCTAssertEqual(twice.decisions[0].sortedCriteria.map(\.id), wanted)
        XCTAssertEqual(effects(once, .setCriteriaOrder(decisionID: decisionID, ids: wanted)), [], "An unchanged order saves nothing")
    }

    func testMarkingDoneTwiceStaysDone() {
        var (state, decisionID) = workspace()
        let task = FollowUpTask(title: "Call")
        state = reduce(state, .addFollowUp(decisionID: decisionID, task: task))
        state = reduce(state, .setFollowUpDone(decisionID: decisionID, taskID: task.id, isDone: true))
        state = reduce(state, .setFollowUpDone(decisionID: decisionID, taskID: task.id, isDone: true))
        XCTAssertEqual(state.decisions[0].followUpTasks.first?.isDone, true)
    }

    func testReplacingAnOptionPhotoReleasesTheOldFile() {
        var (state, decisionID) = workspace()
        var option = makeOption("Mac")
        option.imageFileName = "\(UUID().uuidString).jpg"
        state = reduce(state, .addOption(decisionID: decisionID, option: option))
        let old = option.imageFileName!
        option.imageFileName = "\(UUID().uuidString).jpg"
        XCTAssertTrue(effects(state, .updateOption(decisionID: decisionID, option: option)).contains(.deleteAttachments([old])))
    }

    // MARK: - Store

    private func store(_ api: FakeAPI, directory: URL) -> AppStore {
        var initial = AppState()
        initial.settings.onboardingCompleted = true
        initial.isLoaded = true
        return AppStore(api: api, cache: DataRepository(directory: directory), monitor: nil, initialState: initial)
    }

    func testAnImportTheServerAcceptedCountsAsDoneEvenIfReloadingFails() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("retry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = FakeAPI()
        await api.setFailBootstrap(.offline)
        let store = store(api, directory: directory)
        var backup = AppData()
        backup.decisions = [reduce(AppState(), .createDecision(makeDraft("Imported"))).decisions[0]]

        let imported = await store.perform(.replaceAllData(backup))
        XCTAssertTrue(imported)
        XCTAssertEqual(store.state.toast?.message, "Backup imported")
        XCTAssertEqual(store.connection, .offline, "The reload is retried once the connection is back")
    }

    func testAnEarlierErrorToastDoesNotMakeANoOpFail() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("retry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store(FakeAPI(), directory: directory)
        store.showToast("Something failed", style: .error)
        let saved = await store.perform(.load)
        XCTAssertTrue(saved)
        let unchanged = await store.perform(.setCriteriaOrder(decisionID: UUID(), ids: []))
        XCTAssertTrue(unchanged)
    }

    func testAFailedAccountDeletionOfUnknownOutcomeLeavesNoCache() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("retry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = FakeAPI()
        let store = store(api, directory: directory)
        await store.perform(.createDecision(makeDraft("Private")))
        let cache = DataRepository(directory: directory)
        cache.flush(store.state.data, for: "USER-1")

        await api.setFailDelete(.offline)
        let deleted = await store.perform(.deleteAllData)
        XCTAssertFalse(deleted)
        XCTAssertNil(DataRepository(directory: directory).load(for: "USER-1"),
                     "If the account may be gone, its data must not reappear offline")
    }
}
