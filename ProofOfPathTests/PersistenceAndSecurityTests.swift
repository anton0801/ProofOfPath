//
//  PersistenceAndSecurityTests.swift
//  ProofOfPathTests
//

import XCTest
@testable import ProofOfPath

@MainActor
final class PersistenceAndSecurityTests: XCTestCase {

    // MARK: Numbers

    func testEditableNumbersSurviveARoundTrip() {
        for value in [0, 1, 42, 649, 1249, 1_250_000, 0.5, 12.75, 99.9, 1234.56] as [Double] {
            let text = POPFormat.editableNumber(value)
            XCTAssertEqual(POPFormat.parseNumber(text) ?? .nan, value, accuracy: 0.0001,
                           "\(value) became “\(text)”")
        }
    }

    func testEditableNumbersCarryNoGroupingSeparators() {
        XCTAssertEqual(POPFormat.editableNumber(1_250_000), "1250000")
    }

    func testParsingAcceptsBothDecimalConventions() {
        XCTAssertEqual(POPFormat.parseNumber("1 200,50") ?? .nan, 1200.5, accuracy: 0.001)
        XCTAssertEqual(POPFormat.parseNumber("1,200.50") ?? .nan, 1200.5, accuracy: 0.001)
        XCTAssertNil(POPFormat.parseNumber(""))
        XCTAssertNil(POPFormat.parseNumber("abc"))
    }

    // MARK: Codec

    func testDataSurvivesASaveAndLoadWithoutDrift() throws {
        var state = AppState()
        state = reduce(state, .createDecision(makeDraft("Fridge")))
        let id = state.decisions[0].id
        state = reduce(state, .addCriterion(decisionID: id, criterion: makeCriterion("Price", weight: 100)))
        state = reduce(state, .addOption(decisionID: id, option: makeOption("A", cost: 900)))

        var item = Evidence()
        item.decisionID = id
        item.summary = "Quote"
        state = reduce(state, .addEvidence(item))

        let encoded = try TestCodec.encoder.encode(state.data)
        let decoded = try TestCodec.decoder.decode(AppData.self, from: encoded)

        XCTAssertEqual(decoded.decisions.count, state.decisions.count)
        XCTAssertEqual(decoded.evidence.count, state.evidence.count)
        XCTAssertEqual(decoded.settings, state.settings)

        // ISO-8601 carries milliseconds, so the first pass rounds a sub-millisecond
        // remainder. What must hold is that a second pass changes nothing further.
        let reEncoded = try TestCodec.encoder.encode(decoded)
        let reDecoded = try TestCodec.decoder.decode(AppData.self, from: reEncoded)
        XCTAssertEqual(reDecoded, decoded, "A save/load cycle must not drift")
    }

    func testSameSecondActivityKeepsItsOrderAcrossAReload() throws {
        var decision = Decision()
        let stamp = Date()
        for i in 0..<6 {
            decision.activity.append(ActivityEvent(kind: .criterionAdded, summary: "E\(i)", date: stamp))
        }
        XCTAssertEqual(decision.sortedActivity.map(\.summary), ["E5", "E4", "E3", "E2", "E1", "E0"])

        let decoded = try TestCodec.decoder.decode(
            Decision.self, from: try TestCodec.encoder.encode(decision))
        XCTAssertEqual(decoded.sortedActivity.map(\.summary), decision.sortedActivity.map(\.summary),
                       "Events logged in the same second must not reshuffle")
    }

    func testAWholeSecondFileFromAnEarlierBuildStillOpens() throws {
        let legacy = """
        {"decisions":[],"evidence":[],"schemaVersion":1,
         "settings":{"defaultCurrency":"USD","hapticsEnabled":true,"onboardingCompleted":true,
         "ownerName":"","ratingScaleMax":5,"reminderLeadDays":3,"remindersEnabled":false}}
        """
        XCTAssertNoThrow(try TestCodec.decoder.decode(AppData.self, from: Data(legacy.utf8)))
    }

    // MARK: Attachment path handling

    func testACraftedAttachmentNameCannotEscapeItsFolder() throws {
        let store = AttachmentStore.shared
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let victim = documents.appendingPathComponent("proofpath-unit-test-victim.json")
        try "SENSITIVE".write(to: victim, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: victim) }

        let attacks = [
            "../proofpath-unit-test-victim.json",
            "../../proofpath-unit-test-victim.json",
            "../../../../../../etc/passwd",
            "subdir/../../proofpath-unit-test-victim.json",
            "/etc/passwd", "..", ".", ""
        ]

        for attack in attacks {
            store.delete([attack])
            XCTAssertTrue(FileManager.default.fileExists(atPath: victim.path),
                          "“\(attack)” deleted a file outside the attachments folder")
            XCTAssertNil(store.data(for: attack), "“\(attack)” read a file outside the folder")
            XCTAssertFalse(store.exists(attack), "“\(attack)” resolved outside the folder")
        }
    }

    func testAnOversizedBackupIsRefusedBeforeItIsRead() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("proofpath-oversized-\(UUID().uuidString).json")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }

        let handle = try FileHandle(forWritingTo: url)
        let chunk = Data(repeating: 0x20, count: 1024 * 1024)
        for _ in 0..<51 { handle.write(chunk) }
        try handle.close()

        XCTAssertThrowsError(try DataRepository.shared.importData(from: url)) { error in
            XCTAssertTrue("\(error)".contains("MB") || (error as? RepositoryError) != nil)
        }
    }

    func testTemporaryExportsAreCleanedUp() throws {
        let stale = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProofPath-Backup-stale.json")
        try Data("old".utf8).write(to: stale)
        DataRepository.shared.purgeTemporaryExports()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    }
}
