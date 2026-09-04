//
//  SyncReadinessTests.swift
//  ProofOfPathTests
//
//  The app is local-only today. These tests pin down that it stays inert now
//  and that the groundwork behaves the moment an account starts syncing.
//

import XCTest
@testable import ProofOfPath

@MainActor
final class SyncReadinessTests: XCTestCase {

    // MARK: Backward compatibility

    func testAFileWrittenBeforeSyncExistedStillDecodes() throws {
        let legacy = """
        {
          "decisions": [{
            "activity": [], "acceptedUnknowns": [], "claims": [], "createdAt": "2026-01-05T10:00:00Z",
            "criteria": [], "currencyCode": "EUR", "customCategoryName": "", "category": "purchase",
            "costHorizon": "threeYears", "desiredOutcome": "Old outcome", "followUpTasks": [],
            "hardConstraints": [], "id": "11111111-1111-1111-1111-111111111111", "options": [],
            "owner": "", "peopleAffected": "", "risks": [], "scenarios": [], "snapshots": [],
            "status": "active", "title": "Legacy decision", "updatedAt": "2026-01-05T10:00:00Z",
            "whyItMatters": ""
          }],
          "evidence": [], "schemaVersion": 1,
          "settings": {"defaultCurrency":"USD","hapticsEnabled":true,"onboardingCompleted":true,
                       "ownerName":"","ratingScaleMax":5,"reminderLeadDays":3,"remindersEnabled":false}
        }
        """
        let data = try TestCodec.decoder.decode(AppData.self, from: Data(legacy.utf8))

        XCTAssertEqual(data.decisions.first?.title, "Legacy decision")
        XCTAssertEqual(data.decisions.first?.sync.state, .localOnly)
        XCTAssertTrue(data.tombstones.isEmpty)
        XCTAssertTrue(data.outbox.isEmpty)
        XCTAssertEqual(data.account.mode, .local)
        XCTAssertFalse(data.hasAccountRecord)
    }

    func testTheDeviceIdentifierIsStableOnceMaterialised() throws {
        var data = AppData()
        XCTAssertFalse(data.hasAccountRecord)

        data.ensureAccountRecord()
        let first = data.account.deviceID
        XCTAssertEqual(data.account.deviceID, first, "Reading twice must not mint a new identifier")

        data.ensureAccountRecord()
        XCTAssertEqual(data.account.deviceID, first, "Ensure must be idempotent")

        let reloaded = try TestCodec.decoder.decode(AppData.self, from: try TestCodec.encoder.encode(data))
        XCTAssertEqual(reloaded.account.deviceID, first, "It must survive a save and load")
    }

    // MARK: Local-only behaviour

    func testLocalOnlyModeQueuesNothing() {
        var state = AppState()
        state = reduce(state, .createDecision(makeDraft("Local work")))
        let id = state.decisions[0].id
        state = reduce(state, .addCriterion(decisionID: id, criterion: makeCriterion("Cost", weight: 100)))
        state = reduce(state, .addOption(decisionID: id, option: makeOption("A", cost: 10)))

        XCTAssertTrue(state.outbox.isEmpty)
        XCTAssertTrue(state.tombstones.isEmpty)
        XCTAssertEqual(state.pendingSyncCount, 0)
        XCTAssertEqual(state.account.mode, .local)

        state = reduce(state, .deleteDecision(id))
        XCTAssertTrue(state.tombstones.isEmpty, "A local-only delete needs no tombstone")
        XCTAssertTrue(state.decisions.isEmpty)
    }

    func testTheLocalBackendReportsNoServer() async {
        let backend = LocalBackend()
        XCTAssertFalse(backend.isRemote)
        XCTAssertEqual(backend.storageDescription, "On this device")

        let pushed = await backend.push(AppData())
        let pulled = await backend.pull(since: nil)
        XCTAssertEqual(pushed, .notConfigured)
        XCTAssertEqual(pulled, .notConfigured)
    }

    func testTheCoordinatorStaysInertWithoutAServer() async {
        let coordinator = SyncCoordinator(backend: LocalBackend())
        XCTAssertFalse(coordinator.isEnabled)
        let outcome = await coordinator.synchronize(AppData())
        XCTAssertEqual(outcome, .notConfigured, "It must not claim to have synced")
    }

    // MARK: Behaviour once an account is syncing

    private func signedInState() -> (AppState, UUID) {
        var state = AppState()
        state.account.mode = .signedIn
        state = reduce(state, .createDecision(makeDraft("Synced work")))
        return (state, state.decisions[0].id)
    }

    func testACreatedRecordIsQueuedForUpload() {
        let (state, id) = signedInState()
        XCTAssertTrue(state.outbox.contains { $0.entityID == id && $0.operation == .upsert })
    }

    func testASecondEditReplacesTheQueuedEntryRatherThanStacking() {
        var (state, id) = signedInState()
        state = reduce(state, .addCriterion(decisionID: id, criterion: makeCriterion("Speed", weight: 100)))
        XCTAssertEqual(state.outbox.filter { $0.entityID == id }.count, 1)
        XCTAssertTrue(state.decisions[0].sync.state.needsUpload)
    }

    func testDeletingWritesATombstoneAndWithdrawsThePendingUpload() {
        var (state, id) = signedInState()
        var item = Evidence()
        item.decisionID = id
        item.summary = "Doc"
        state = reduce(state, .addEvidence(item))
        XCTAssertTrue(state.outbox.contains { $0.entityID == item.id })

        state = reduce(state, .deleteEvidence(item.id))
        XCTAssertTrue(state.tombstones.contains { $0.entityID == item.id && $0.kind == .evidence })
        XCTAssertFalse(state.outbox.contains { $0.entityID == item.id },
                       "There is no point uploading a record that was deleted")
    }

    func testDeletingEverythingReportsEveryRecord() {
        var (state, id) = signedInState()
        var item = Evidence()
        item.decisionID = id
        item.summary = "Doc"
        state = reduce(state, .addEvidence(item))
        let recordCount = state.decisions.count + state.evidence.count

        state = reduce(state, .deleteAllData)
        XCTAssertEqual(state.tombstones.count, recordCount)
        XCTAssertTrue(state.outbox.isEmpty)
    }

    func testImportingABackupResetsTheSyncBaseline() {
        var (state, _) = signedInState()
        var imported = AppData()
        imported.settings.onboardingCompleted = true

        state = reduce(state, .replaceAllData(imported))
        XCTAssertTrue(state.outbox.isEmpty, "An imported backup is a baseline, not a queue of edits")
        XCTAssertTrue(state.tombstones.isEmpty)
    }

    // MARK: Attachments

    func testANewAttachmentIsLocalUntilUploaded() throws {
        let attachment = EvidenceAttachment(fileName: "a.jpg", originalName: "a.jpg",
                                            byteSize: 10, isImage: true)
        XCTAssertEqual(attachment.uploadState, .localOnly)
        XCTAssertNil(attachment.remoteURL)

        var uploaded = attachment
        uploaded.uploadState = .uploaded
        uploaded.remoteURL = "https://example.invalid/a.jpg"

        let decoded = try TestCodec.decoder.decode(
            EvidenceAttachment.self, from: try TestCodec.encoder.encode(uploaded))
        XCTAssertEqual(decoded.uploadState, .uploaded)
        XCTAssertEqual(decoded.remoteURL, "https://example.invalid/a.jpg")
    }
}
