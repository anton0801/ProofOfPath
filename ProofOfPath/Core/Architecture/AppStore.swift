//
//  AppStore.swift
//  ProofOfPath
//
//  MVI — the only object that owns state. Views send Intents; the Reducer
//  produces the next State plus Effects, which are performed here.
//
//  The server is the source of truth. An intent is reduced into a proposed
//  state, the difference is sent to the API as one atomic batch, and only
//  once the server confirms it does the proposed state replace the current
//  one. Nothing the server has not accepted is ever shown or cached.
//

import SwiftUI
import Combine

@MainActor
final class AppStore: ObservableObject {

    /// Whether data is on screen yet.
    enum Phase: Equatable {
        /// Signing in and loading, with nothing cached to show meanwhile.
        case launching
        /// Data is on screen: from the server, or from the cache while offline.
        case ready
        /// Nothing cached and the server could not be reached.
        case unavailable(String)
    }

    enum Connection: Equatable {
        case connecting
        case online
        case offline
    }

    @Published private(set) var state: AppState
    @Published private(set) var phase: Phase
    @Published private(set) var connection: Connection
    /// True while a change is on its way to the server.
    @Published private(set) var isSaving = false
    /// False when the network is fine but the server failed; the banner says which.
    @Published private(set) var lastFailureWasNetwork = true
    /// Bumped when a downloaded attachment lands, so views showing it refresh.
    @Published private(set) var attachmentRevision = 0

    /// Changes can only be made while the server is reachable: the app shows
    /// cached data offline, but it never pretends to have saved something.
    var canEdit: Bool { phase == .ready && connection == .online }

    private let api: ProofPathAPI
    private let cache: DataRepository
    private let attachments: AttachmentStore
    private let monitor: ConnectivityMonitor?
    private var userID: String?
    private var queueTail: Task<Void, Never>?
    private var isConnecting = false
    private var reconnectTask: Task<Void, Never>?
    private var reconnectDelay: TimeInterval = 2
    private var lastRefresh: Date?
    private var downloadsInFlight: Set<String> = []
    /// Files the server could not provide. Not retried until the next refresh,
    /// so a view asking for a missing file cannot trigger a download loop.
    private var failedDownloads: Set<String> = []
    private var hasStarted = false
    private var hasPrunedFiles = false
    private let launchedAt = Date()

    init(
        api: ProofPathAPI = APIClient(),
        credentials: CredentialStore = CredentialStore(),
        cache: DataRepository = .shared,
        attachments: AttachmentStore = .shared,
        monitor: ConnectivityMonitor? = ConnectivityMonitor(),
        initialState: AppState? = nil
    ) {
        self.api = api
        self.cache = cache
        self.attachments = attachments
        self.monitor = monitor

        if let initialState {
            // Tests and previews: data supplied, already "online".
            self.state = initialState
            self.phase = .ready
            self.connection = .online
            self.hasStarted = true
        } else {
            #if DEBUG
            // UI tests pass -POPResetData to start as a brand-new device. The
            // flag only exists in DEBUG builds.
            if ProcessInfo.processInfo.arguments.contains("-POPResetData") {
                credentials.resetDevice()
                cache.deleteStore()
                attachments.deleteAll()
            }
            #endif
            var initial = AppState()
            if let owner = credentials.lastUserID, let cached = cache.load(for: owner) {
                initial.data = cached
                initial.isLoaded = true
                self.userID = owner
                self.phase = .ready
            } else {
                self.phase = .launching
            }
            self.state = initial
            self.connection = .connecting
        }
        Haptics.isEnabled = state.settings.hapticsEnabled
    }

    // MARK: - Session

    /// Starts the session: signs the device in, loads its data, and keeps
    /// reconnecting while the server is out of reach.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        monitor?.start { [weak self] satisfied in
            guard let self else { return }
            if satisfied, self.connection != .online {
                self.reconnectDelay = 2
                self.refresh()
            }
        }
        refresh()
    }

    /// Loads everything from the server again. Queued behind any save in flight.
    func refresh() {
        guard !isConnecting else { return }
        isConnecting = true
        reconnectTask?.cancel()
        reconnectTask = nil
        if connection != .online { connection = .connecting }
        enqueue { [weak self] in
            guard let self else { return }
            defer { self.isConnecting = false }
            do {
                let payload = try await self.api.bootstrap()
                self.apply(payload)
            } catch {
                self.connectionFailed(APIError.from(error))
            }
        }
    }

    /// The "Try Again" button on the connection screen.
    func retryNow() {
        reconnectDelay = 2
        refresh()
    }

    /// Called when the app returns to the foreground.
    func sceneDidBecomeActive() {
        guard hasStarted else { return }
        if connection != .online {
            reconnectDelay = 2
            refresh()
        } else if let lastRefresh, Date().timeIntervalSince(lastRefresh) > 300 {
            refresh()
        }
    }

    private func apply(_ payload: BootstrapPayload) {
        let owner = payload.user.id
        if userID != owner {
            // A different account than the cache belonged to.
            cache.deleteStore()
        }
        userID = owner
        state.data = payload.data
        state.isLoaded = true
        failedDownloads = []
        phase = .ready
        connection = .online
        reconnectDelay = 2
        lastRefresh = Date()
        Haptics.isEnabled = state.settings.hapticsEnabled
        cache.save(state.data, for: owner)
        rescheduleReminders()
        if !hasPrunedFiles {
            hasPrunedFiles = true
            // A photo picked in an editor opened before this first load is not
            // referenced by anything yet; only files from earlier sessions go.
            let removed = attachments.pruneOrphans(referenced: ChangePlanner.referencedFiles(in: state.data),
                                                   keepingFilesCreatedAfter: launchedAt)
            if removed > 0 { attachmentRevision += 1 }
        }
        downloadMissingAttachments()
        #if DEBUG
        // Lets a UI test start on Home when onboarding is not what it tests.
        // Saved like a real tap, so the server and the app agree.
        if ProcessInfo.processInfo.arguments.contains("-POPSkipOnboarding"), !state.settings.onboardingCompleted {
            send(.completeOnboarding)
        }
        #endif
    }

    private func connectionFailed(_ error: APIError) {
        lastFailureWasNetwork = error.isConnectivity
        connection = .offline
        if phase != .ready {
            phase = .unavailable(error.errorDescription ?? "The server could not be reached.")
        }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 60)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    // MARK: - The MVI loop

    /// Fire-and-forget. Use `perform` when the caller must know whether the
    /// change was saved, e.g. before closing an editor.
    func send(_ intent: AppIntent) {
        if applyLocally(intent) { return }
        Task { await perform(intent) }
    }

    /// Reduces the intent, saves the result to the server and, once the server
    /// confirms, shows it. Returns false when nothing was saved.
    @discardableResult
    func perform(_ intent: AppIntent) async -> Bool {
        if applyLocally(intent) { return true }
        return await enqueue { [weak self] in
            await self?.commit(intent) ?? false
        }
    }

    /// Intents that only touch transient UI state never reach the server.
    private func applyLocally(_ intent: AppIntent) -> Bool {
        switch intent {
        case .load:
            return true
        case .dismissToast:
            state.toast = nil
            return true
        case .dismissConstraintNotice:
            state.constraintRecheckNotice = nil
            return true
        default:
            return false
        }
    }

    /// Saves run one at a time, each reducing against the state the previous
    /// one left behind.
    private func enqueue<T: Sendable>(_ work: @escaping @MainActor () async -> T) async -> T {
        let previous = queueTail
        let task = Task { @MainActor () -> T in
            await previous?.value
            return await work()
        }
        queueTail = Task { @MainActor in _ = await task.value }
        return await task.value
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = queueTail
        queueTail = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    private func commit(_ intent: AppIntent) async -> Bool {
        guard canEdit else {
            showOfflineNotice()
            return false
        }
        switch intent {
        case .replaceAllData(let data):
            return await importBackup(data)
        case .deleteAllData:
            return await deleteAllData()
        default:
            break
        }

        let before = state
        let result = AppReducer.reduce(state: state, intent: intent)
        var proposed = result.state
        proposed.data = proposed.data.conformedToAPI()

        let plan: ChangePlan
        do {
            plan = try ChangePlanner.plan(from: state.data, to: proposed.data)
        } catch {
            saveFailed(.invalidResponse("encode: \(error)"))
            return false
        }

        let reducerToast = proposed.toast != before.toast ? proposed.toast : nil
        let reducerNotice = proposed.constraintRecheckNotice != before.constraintRecheckNotice

        guard !plan.isEmpty else {
            // Nothing to store: a validation message from the reducer, or an
            // edit that changed nothing.
            if let reducerToast { state.toast = reducerToast }
            if reducerNotice { state.constraintRecheckNotice = proposed.constraintRecheckNotice }
            performFeedbackEffects(result.effects)
            return reducerToast?.style != .error
        }

        isSaving = true
        defer { isSaving = false }
        do {
            for name in plan.uploads.keys.sorted() {
                guard let attachment = plan.uploads[name] else { continue }
                try await api.upload(attachment, from: attachments.url(for: name))
            }
            try await api.commit(plan.operations)
        } catch {
            saveFailed(APIError.from(error))
            return false
        }

        // Toasts shown or dismissed while the save was in flight stay as they are.
        state.data = proposed.data
        if let reducerToast { state.toast = reducerToast }
        if reducerNotice { state.constraintRecheckNotice = proposed.constraintRecheckNotice }
        Haptics.isEnabled = state.settings.hapticsEnabled
        for effect in result.effects {
            run(effect)
        }
        persistCache()
        return true
    }

    private func run(_ effect: AppEffect) {
        switch effect {
        case .none, .persist:
            break
        case .deleteAttachments(let fileNames):
            releaseAttachments(fileNames)
        case .deleteAllAttachments:
            attachments.deleteAll()
        case .rescheduleReminders:
            rescheduleReminders()
        case .haptic:
            performFeedbackEffects([effect])
        }
    }

    private func performFeedbackEffects(_ effects: [AppEffect]) {
        for case .haptic(let kind) in effects {
            switch kind {
            case .tap: Haptics.tap()
            case .success: Haptics.success()
            case .warning: Haptics.warning()
            case .error: Haptics.error()
            }
        }
    }

    private func saveFailed(_ error: APIError) {
        Haptics.error()
        if error.isConnectivity {
            lastFailureWasNetwork = true
            connection = .offline
            scheduleReconnect()
            state.toast = Toast(message: "Connection lost", style: .error,
                                detail: "The change may not have been saved. Your data reloads when you're back online — saving again is safe.")
            return
        }
        state.toast = Toast(message: "Not saved", style: .error, detail: error.errorDescription)
        if case .server(_, let code, _, _) = error,
           ["not_found", "invalid_reference", "id_conflict", "parent_mismatch", "snapshot_version_taken"].contains(code) {
            // This device's copy no longer matches the server: reload it.
            refresh()
        }
    }

    private func showOfflineNotice() {
        Haptics.warning()
        state.toast = Toast(message: "You're offline", style: .warning,
                            detail: "Saved data stays visible, but changes need a connection.")
    }

    private func rescheduleReminders() {
        let decisions = state.decisions
        let settings = state.settings
        Task { await ReminderService.shared.reschedule(decisions: decisions, settings: settings) }
    }

    private func persistCache() {
        guard let userID else { return }
        cache.save(state.data, for: userID)
    }

    /// Write the cache immediately — called when the scene leaves the foreground.
    func flush() {
        guard let userID, state.isLoaded else { return }
        cache.flush(state.data, for: userID)
    }

    // MARK: - Whole-account actions

    private func importBackup(_ data: AppData) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            try await api.importBackup(data.conformedToAPI())
        } catch {
            saveFailed(APIError.from(error))
            return false
        }
        do {
            apply(try await api.bootstrap())
        } catch {
            // Stored on the server; it appears as soon as a reload succeeds.
            connectionFailed(APIError.from(error))
        }
        Haptics.success()
        state.toast = Toast(message: "Backup imported", style: .success,
                            detail: "\(data.decisions.count) decisions and \(data.evidence.count) evidence items restored.")
        return true
    }

    /// Deletes the account on the server with everything in it, then starts a
    /// fresh, empty one for this device.
    private func deleteAllData() async -> Bool {
        let wasOnboarded = state.settings.onboardingCompleted
        isSaving = true
        defer { isSaving = false }
        // Dropped first: if the response is lost the account may already be
        // gone, and a later offline launch must not show its data.
        cache.deleteStore()
        do {
            try await api.deleteAccount()
        } catch {
            let apiError = APIError.from(error)
            if !apiError.isConnectivity {
                persistCache()
            }
            // After a lost response the next load tells: a deleted account
            // signs in as a new, empty one.
            saveFailed(apiError)
            return false
        }

        // Gone on the server: gone here too, including version 1.0 leftovers.
        userID = nil
        cache.deleteStore()
        cache.removeLegacyData()
        attachments.deleteAll()
        attachments.removeLegacyFiles()
        state.data = AppData()
        state.data.settings.onboardingCompleted = wasOnboarded
        rescheduleReminders()

        do {
            let payload = try await api.bootstrap()
            apply(payload)
            if wasOnboarded && !state.settings.onboardingCompleted {
                var settings = state.data
                settings.settings.onboardingCompleted = true
                let plan = try ChangePlanner.plan(from: state.data, to: settings)
                try await api.commit(plan.operations)
                state.data = settings
                persistCache()
            }
        } catch {
            connectionFailed(APIError.from(error))
        }
        Haptics.warning()
        state.toast = Toast(message: "All data deleted", style: .warning,
                            detail: "Your decisions, evidence and files were removed from the server and this device.")
        return true
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

    // MARK: - Attachments

    /// Copies a picked file into local storage. It is uploaded when the record
    /// that references it is saved.
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

    /// True when the file is on this device. A file that is only on the server
    /// is fetched in the background; views reading this refresh when it lands.
    func attachmentExists(_ fileName: String?) -> Bool {
        _ = attachmentRevision
        guard let fileName else { return false }
        if attachments.exists(fileName) { return true }
        download(fileName)
        return false
    }

    /// True while a missing file is being fetched.
    func isDownloadingAttachment(_ fileName: String?) -> Bool {
        _ = attachmentRevision
        guard let fileName else { return false }
        return downloadsInFlight.contains(fileName)
    }

    #if canImport(UIKit)
    func image(named fileName: String?) -> UIImage? {
        _ = attachmentRevision
        guard let fileName else { return nil }
        if let image = attachments.loadImage(named: fileName) { return image }
        download(fileName)
        return nil
    }
    #endif

    var attachmentUsage: (count: Int, bytes: Int64) {
        _ = attachmentRevision
        return (attachments.fileCount(), attachments.totalUsedBytes())
    }

    private func download(_ fileName: String) {
        guard connection == .online,
              AttachmentStore.isValidFileName(fileName),
              !downloadsInFlight.contains(fileName),
              !failedDownloads.contains(fileName)
        else { return }
        downloadsInFlight.insert(fileName)
        Task { [weak self] in
            await self?.fetch(fileName)
        }
    }

    private func fetch(_ fileName: String) async {
        do {
            let data = try await api.download(fileName: fileName)
            try attachments.storeDownloaded(data, fileName: fileName)
        } catch {
            failedDownloads.insert(fileName)
        }
        downloadsInFlight.remove(fileName)
        attachmentRevision += 1
    }

    /// Fetches the files current records use, so they can be opened offline.
    private func downloadMissingAttachments() {
        var names = Set(state.evidence.compactMap { $0.attachment?.fileName })
        for decision in state.decisions {
            names.formUnion(decision.options.compactMap(\.imageFileName))
        }
        let missing = names.filter { AttachmentStore.isValidFileName($0) && !attachments.exists($0) }.sorted()
        guard !missing.isEmpty else { return }
        Task { [weak self] in
            for name in missing {
                guard let self, self.connection == .online else { return }
                guard !self.downloadsInFlight.contains(name), !self.attachments.exists(name) else { continue }
                self.downloadsInFlight.insert(name)
                await self.fetch(name)
            }
        }
    }

    /// Files the records no longer use: removed from the server (unless a
    /// history snapshot still shows them) and from this device.
    private func releaseAttachments(_ fileNames: [String]) {
        let stillUsed = ChangePlanner.referencedFiles(in: state.data)
        let released = fileNames.filter { !stillUsed.contains($0) && AttachmentStore.isValidFileName($0) }
        guard !released.isEmpty else { return }
        attachments.delete(released)
        Task { [api] in
            for name in released {
                try? await api.releaseAttachment(name)
            }
        }
    }

    /// Removes local files nothing points at any more.
    @discardableResult
    func pruneOrphanAttachments() -> Int {
        guard state.isLoaded else { return 0 }
        let removed = attachments.pruneOrphans(referenced: ChangePlanner.referencedFiles(in: state.data))
        if removed > 0 { attachmentRevision += 1 }
        return removed
    }

    // MARK: - Export / import

    func purgeTemporaryExports() {
        cache.purgeTemporaryExports()
    }

    func exportBackup() -> Result<URL, Error> {
        do {
            return .success(try cache.exportData(state.data))
        } catch {
            return .failure(error)
        }
    }

    func importBackup(from url: URL) -> Result<AppData, Error> {
        do {
            return .success(try cache.importData(from: url))
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
