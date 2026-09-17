//
//  AppStoreSessionTests.swift
//  ProofOfPathTests
//
//  The store against a scripted API: nothing is shown until the server says so.
//

import XCTest
@testable import ProofOfPath

/// Records every call and fails on demand.
actor FakeAPI: ProofPathAPI {
    enum Call: Equatable {
        case bootstrap
        case commit([String])
        case importBackup(Int)
        case deleteAccount
        case upload(String)
        case download(String)
        case release(String)
    }

    private(set) var calls: [Call] = []
    var failNextCommit: APIError?
    var failBootstrap: APIError?
    var failDelete: APIError?
    var server = AppData()
    var userID = "USER-1"
    var commitDelay: UInt64 = 0

    func setFailNextCommit(_ error: APIError?) { failNextCommit = error }
    func setFailBootstrap(_ error: APIError?) { failBootstrap = error }
    func setFailDelete(_ error: APIError?) { failDelete = error }
    func setServer(_ data: AppData) { server = data }
    func setCommitDelay(_ nanoseconds: UInt64) { commitDelay = nanoseconds }

    func bootstrap() async throws -> BootstrapPayload {
        calls.append(.bootstrap)
        if let failBootstrap { throw failBootstrap }
        let json = """
        {"user":{"id":"\(userID)"},"settings":\(String(decoding: try POPJSON.makeEncoder().encode(server.settings), as: UTF8.self)),
        "decisions":\(String(decoding: try POPJSON.makeEncoder().encode(server.decisions), as: UTF8.self)),
        "evidence":\(String(decoding: try POPJSON.makeEncoder().encode(server.evidence), as: UTF8.self))}
        """
        return try POPJSON.makeDecoder().decode(BootstrapPayload.self, from: Data(json.utf8))
    }

    func commit(_ operations: [APIOperation]) async throws {
        if commitDelay > 0 { try? await Task.sleep(nanoseconds: commitDelay) }
        if let error = failNextCommit {
            failNextCommit = nil
            calls.append(.commit(operations.map(\.description)))
            throw error
        }
        calls.append(.commit(operations.map(\.description)))
    }

    func importBackup(_ data: AppData) async throws {
        calls.append(.importBackup(data.decisions.count))
        server = data
    }

    func deleteAccount() async throws {
        calls.append(.deleteAccount)
        if let failDelete { throw failDelete }
        server = AppData()
        userID = "USER-2"
    }

    func upload(_ attachment: EvidenceAttachment, from fileURL: URL) async throws {
        calls.append(.upload(attachment.fileName))
    }

    func download(fileName: String) async throws -> Data {
        calls.append(.download(fileName))
        throw APIError.server(status: 404, code: "not_found", message: "", operationIndex: nil)
    }

    func releaseAttachment(_ fileName: String) async throws {
        calls.append(.release(fileName))
    }

    func currentUserID() async -> String? { userID }
    func forgetDevice() async {}
}

@MainActor
final class AppStoreSessionTests: XCTestCase {

    private var cacheDirectory: URL!

    override func setUp() {
        super.setUp()
        cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("store-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        super.tearDown()
    }

    private func makeStore(_ api: FakeAPI, state: AppState? = nil) -> AppStore {
        var initial = state ?? AppState()
        initial.settings.onboardingCompleted = true
        initial.isLoaded = true
        return AppStore(api: api, cache: DataRepository(directory: cacheDirectory), monitor: nil, initialState: initial)
    }

    private func commits(_ api: FakeAPI) async -> [[String]] {
        await api.calls.compactMap { if case .commit(let ops) = $0 { return ops } else { return nil } }
    }

    func testASavedChangeAppearsOnlyAfterTheServerAccepts() async {
        let api = FakeAPI()
        await api.setCommitDelay(150_000_000)
        let store = makeStore(api)

        let pending = Task { await store.perform(.createDecision(makeDraft("Car"))) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(store.state.decisions.isEmpty, "Nothing is shown before the server confirms")
        XCTAssertTrue(store.isSaving)

        let saved = await pending.value
        XCTAssertTrue(saved)
        XCTAssertFalse(store.isSaving)
        XCTAssertEqual(store.state.decisions.map(\.title), ["Car"])
        let sent = await commits(api)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].first, "PUT /decisions/\(store.state.decisions[0].id.uuidString)")
    }

    func testARefusedChangeLeavesEverythingAsItWas() async {
        let api = FakeAPI()
        await api.setFailNextCommit(.server(status: 422, code: "validation_failed", message: "weight must be at most 100.", operationIndex: 1))
        let store = makeStore(api)

        let saved = await store.perform(.createDecision(makeDraft("Car")))
        XCTAssertFalse(saved)
        XCTAssertTrue(store.state.decisions.isEmpty)
        XCTAssertEqual(store.state.toast?.style, .error)
        XCTAssertEqual(store.state.toast?.detail, "weight must be at most 100.")
        XCTAssertEqual(store.connection, .online, "A validation error is not a connection problem")
    }

    func testLosingTheConnectionMidSaveSwitchesToReadOnly() async {
        let api = FakeAPI()
        await api.setFailNextCommit(.offline)
        let store = makeStore(api)

        let saved = await store.perform(.createDecision(makeDraft("Car")))
        XCTAssertFalse(saved)
        XCTAssertTrue(store.state.decisions.isEmpty)
        XCTAssertEqual(store.connection, .offline)
        XCTAssertFalse(store.canEdit)

        // While offline nothing is even attempted.
        let callsBefore = await api.calls.count
        let second = await store.perform(.createDecision(makeDraft("Bike")))
        XCTAssertFalse(second)
        let callsAfter = await api.calls.count
        XCTAssertEqual(callsBefore, callsAfter)
        XCTAssertEqual(store.state.toast?.message, "You're offline")
    }

    func testAValidationMessageNeverReachesTheServer() async {
        let api = FakeAPI()
        let store = makeStore(api)
        await store.perform(.createDecision(makeDraft("Car")))
        let decisionID = store.state.decisions[0].id

        var record = FinalDecision()
        record.whyThisOption = ""
        let saved = await store.perform(.finalizeDecision(decisionID: decisionID, decisionRecord: record))
        XCTAssertFalse(saved)
        XCTAssertEqual(store.state.toast?.style, .error)
        let sent = await commits(api)
        XCTAssertEqual(sent.count, 1, "Only the create was sent")
    }

    func testChangesAreSavedOneAtATimeInOrder() async {
        let api = FakeAPI()
        await api.setCommitDelay(40_000_000)
        let store = makeStore(api)

        async let first = store.perform(.createDecision(makeDraft("One")))
        async let second = store.perform(.createDecision(makeDraft("Two")))
        async let third = store.perform(.createDecision(makeDraft("Three")))
        let results = await [first, second, third]

        XCTAssertEqual(results, [true, true, true])
        XCTAssertEqual(Set(store.state.decisions.map(\.title)), ["One", "Two", "Three"])
        let sent = await commits(api)
        XCTAssertEqual(sent.count, 3)
        // Each batch only carries its own decision: it was planned against the
        // state the previous save left behind.
        for batch in sent {
            XCTAssertEqual(batch.filter { $0.hasPrefix("PUT /decisions/") && !$0.dropFirst(15).contains("/") }.count, 1)
        }
    }

    func testFilesAreUploadedBeforeTheRecordThatUsesThem() async {
        let api = FakeAPI()
        let store = makeStore(api)
        await store.perform(.createDecision(makeDraft("Car")))
        let decisionID = store.state.decisions[0].id

        var evidence = Evidence()
        evidence.decisionID = decisionID
        let fileName = "\(UUID().uuidString).pdf"
        evidence.attachment = EvidenceAttachment(fileName: fileName, originalName: "Quote.pdf", byteSize: 3, isImage: false)
        let saved = await store.perform(.addEvidence(evidence))
        XCTAssertTrue(saved)

        let calls = await api.calls
        let upload = calls.firstIndex(of: .upload(fileName))
        let commit = calls.lastIndex { if case .commit = $0 { return true } else { return false } }
        XCTAssertNotNil(upload)
        XCTAssertLessThan(upload ?? .max, commit ?? .min)
    }

    func testDeletingAFileReleasesItOnTheServer() async {
        let api = FakeAPI()
        let store = makeStore(api)
        await store.perform(.createDecision(makeDraft("Car")))
        var evidence = Evidence()
        evidence.decisionID = store.state.decisions[0].id
        let fileName = "\(UUID().uuidString).pdf"
        evidence.attachment = EvidenceAttachment(fileName: fileName, originalName: "Quote.pdf", byteSize: 3, isImage: false)
        await store.perform(.addEvidence(evidence))

        await store.perform(.deleteEvidence(evidence.id))
        try? await Task.sleep(nanoseconds: 100_000_000)
        let calls = await api.calls
        XCTAssertTrue(calls.contains(.release(fileName)))
    }

    func testBootstrapReplacesTheCachedCopy() async {
        let api = FakeAPI()
        var server = AppData()
        server.settings.onboardingCompleted = true
        server.decisions = [reduce(AppState(), .createDecision(makeDraft("From server"))).decisions[0]]
        await api.setServer(server)

        let store = AppStore(api: api, credentials: CredentialStore(keychain: KeychainStore(service: "tests-\(UUID().uuidString)")),
                             cache: DataRepository(directory: cacheDirectory), monitor: nil)
        XCTAssertEqual(store.phase, .launching)
        XCTAssertFalse(store.canEdit)
        store.start()
        await waitUntil { store.phase == .ready }
        XCTAssertEqual(store.state.decisions.map(\.title), ["From server"])
        XCTAssertEqual(store.connection, .online)
        XCTAssertTrue(store.canEdit)
    }

    func testWithoutCacheAndServerTheAppSaysSo() async {
        let api = FakeAPI()
        await api.setFailBootstrap(.offline)
        let store = AppStore(api: api, credentials: CredentialStore(keychain: KeychainStore(service: "tests-\(UUID().uuidString)")),
                             cache: DataRepository(directory: cacheDirectory), monitor: nil)
        store.start()
        await waitUntil { if case .unavailable = store.phase { return true } else { return false } }
        XCTAssertEqual(store.connection, .offline)
        XCTAssertFalse(store.canEdit)
    }

    func testTheCacheIsNeverShownToAnotherAccount() {
        let cache = DataRepository(directory: cacheDirectory)
        var data = AppData()
        data.decisions = [reduce(AppState(), .createDecision(makeDraft("Private"))).decisions[0]]
        cache.flush(data, for: "USER-1")
        XCTAssertEqual(cache.load(for: "USER-1")?.decisions.count, 1)
        XCTAssertNil(cache.load(for: "USER-2"))
    }

    func testDeleteAllDataStartsAFreshAccount() async {
        let api = FakeAPI()
        let store = makeStore(api)
        await store.perform(.createDecision(makeDraft("Car")))
        XCTAssertEqual(store.state.decisions.count, 1)

        let deleted = await store.perform(.deleteAllData)
        XCTAssertTrue(deleted)
        XCTAssertTrue(store.state.decisions.isEmpty)
        XCTAssertTrue(store.state.settings.onboardingCompleted, "Deleting data does not replay onboarding")
        let calls = await api.calls
        XCTAssertTrue(calls.contains(.deleteAccount))
        XCTAssertEqual(calls.last.map { if case .commit(let ops) = $0 { return ops } else { return [] } }, ["PUT /settings"])
    }

    func testImportGoesThroughTheServer() async {
        let api = FakeAPI()
        let store = makeStore(api)
        var backup = AppData()
        backup.decisions = [reduce(AppState(), .createDecision(makeDraft("Imported"))).decisions[0]]
        backup.settings.onboardingCompleted = true

        let imported = await store.perform(.replaceAllData(backup))
        XCTAssertTrue(imported)
        XCTAssertEqual(store.state.decisions.map(\.title), ["Imported"])
        let calls = await api.calls
        XCTAssertEqual(Array(calls.suffix(2)), [.importBackup(1), .bootstrap])
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), "Timed out")
    }
}
