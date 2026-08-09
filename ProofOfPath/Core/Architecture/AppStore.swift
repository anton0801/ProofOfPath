//
//  AppStore.swift
//  ProofOfPath
//
//  MVI — the only object that owns state. Views send Intents; the Reducer
//  produces the next State plus Effects, which are performed here.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AppStore {

    private(set) var state: AppState

    @ObservationIgnored private let repository: DataRepository
    @ObservationIgnored private let attachments: AttachmentStore

    init(
        repository: DataRepository = .shared,
        attachments: AttachmentStore = .shared,
        initialState: AppState? = nil
    ) {
        self.repository = repository
        self.attachments = attachments
        if let initialState {
            self.state = initialState
        } else {
            // UI tests pass -POPResetData so each run starts from a clean slate.
            // The flag only exists in DEBUG builds, so a release build cannot be
            // made to wipe a real user's data by launching it with an argument.
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-POPResetData") {
                repository.deleteStore()
                attachments.deleteAll()
            }
            #endif
            var loaded = AppState()
            let data = repository.load()
            loaded.decisions = data.decisions
            loaded.evidence = data.evidence
            loaded.settings = data.settings
            loaded.isLoaded = true
            #if DEBUG
            // Lets a UI test start on Home when onboarding is not what it is
            // testing. Onboarding itself is covered by its own tests.
            if ProcessInfo.processInfo.arguments.contains("-POPSkipOnboarding") {
                loaded.settings.onboardingCompleted = true
            }
            #endif
            self.state = loaded
        }
        Haptics.isEnabled = state.settings.hapticsEnabled
    }

    // MARK: - The MVI loop

    func send(_ intent: AppIntent) {
        let result = AppReducer.reduce(state: state, intent: intent)
        state = result.state
        Haptics.isEnabled = state.settings.hapticsEnabled
        for effect in result.effects {
            perform(effect)
        }
    }

    private func perform(_ effect: AppEffect) {
        switch effect {
        case .none:
            break

        case .persist:
            repository.save(state.data)

        case .deleteAttachments(let fileNames):
            attachments.delete(fileNames)

        case .deleteAllAttachments:
            attachments.deleteAll()

        case .rescheduleReminders:
            let decisions = state.decisions
            let settings = state.settings
            Task { await ReminderService.shared.reschedule(decisions: decisions, settings: settings) }

        case .haptic(let kind):
            switch kind {
            case .tap: Haptics.tap()
            case .success: Haptics.success()
            case .warning: Haptics.warning()
            case .error: Haptics.error()
            }
        }
    }

    /// Write immediately — called when the scene leaves the foreground.
    func flush() {
        repository.flush(state.data)
    }

    // MARK: - Toast helpers (runtime-only state)

    func showToast(_ message: String, style: Toast.Style = .info, detail: String? = nil) {
        state.toast = Toast(message: message, style: style, detail: detail)
    }

    func dismissToast() {
        state.toast = nil
    }

    func dismissConstraintNotice() {
        state.constraintRecheckNotice = nil
    }

    // MARK: - Attachments (I/O that must report errors to the caller)

    func importAttachment(from url: URL) -> Result<EvidenceAttachment, Error> {
        do {
            return .success(try attachments.importFile(from: url))
        } catch {
            return .failure(error)
        }
    }

    func importImageData(_ data: Data, name: String) -> Result<EvidenceAttachment, Error> {
        do {
            return .success(try attachments.importImageData(data, suggestedName: name))
        } catch {
            return .failure(error)
        }
    }

    func attachmentURL(_ fileName: String) -> URL { attachments.url(for: fileName) }

    func attachmentExists(_ fileName: String?) -> Bool { attachments.exists(fileName) }

    #if canImport(UIKit)
    func image(named fileName: String?) -> UIImage? { attachments.loadImage(named: fileName) }
    #endif

    var attachmentUsage: (count: Int, bytes: Int64) {
        (attachments.fileCount(), attachments.totalUsedBytes())
    }

    /// Removes attachment files nothing points at any more.
    @discardableResult
    func pruneOrphanAttachments() -> Int {
        var referenced = Set(state.evidence.compactMap { $0.attachment?.fileName })
        for decision in state.decisions {
            for option in decision.options {
                if let image = option.imageFileName { referenced.insert(image) }
            }
            for snapshot in decision.snapshots {
                for item in snapshot.evidence {
                    if let file = item.attachment?.fileName { referenced.insert(file) }
                }
                for option in snapshot.options {
                    if let image = option.imageFileName { referenced.insert(image) }
                }
            }
        }
        return attachments.pruneOrphans(referenced: referenced)
    }

    // MARK: - Export / import

    func purgeTemporaryExports() {
        repository.purgeTemporaryExports()
    }

    func exportBackup() -> Result<URL, Error> {
        do {
            return .success(try repository.exportData(state.data))
        } catch {
            return .failure(error)
        }
    }

    func importBackup(from url: URL) -> Result<AppData, Error> {
        do {
            let data = try repository.importData(from: url)
            return .success(data)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Derived reads used across screens

    func scoreboard(for decision: Decision) -> DecisionScoreboard {
        ScoringEngine.scoreboard(
            decision: decision,
            evidence: state.evidence(forDecision: decision.id),
            scaleMax: state.scaleMax
        )
    }

    func progress(for decision: Decision) -> DecisionProgress {
        ProgressEngine.progress(for: decision, evidence: state.evidence, scaleMax: state.scaleMax)
    }

    func readiness(for decision: Decision, selectedOptionID: UUID? = nil) -> ReadinessReport {
        ReadinessEngine.report(
            for: decision,
            evidence: state.evidence(forDecision: decision.id),
            scaleMax: state.scaleMax,
            selectedOptionID: selectedOptionID
        )
    }

    func openQuestions(for decision: Decision) -> [OpenQuestion] {
        OpenQuestionsEngine.unresolved(
            for: decision,
            evidence: state.evidence(forDecision: decision.id),
            scaleMax: state.scaleMax
        )
    }

    func allOpenQuestions(for decision: Decision) -> [OpenQuestion] {
        OpenQuestionsEngine.questions(
            for: decision,
            evidence: state.evidence(forDecision: decision.id),
            scaleMax: state.scaleMax
        )
    }

    var insights: InsightsReport {
        InsightsEngine.report(decisions: state.decisions)
    }
}
