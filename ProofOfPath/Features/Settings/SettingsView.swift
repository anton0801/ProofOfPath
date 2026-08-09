//
//  SettingsView.swift
//  ProofOfPath
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    @State private var ownerName = ""
    @State private var showDeleteAll = false
    @State private var deleteConfirmationText = ""
    @State private var showImporter = false
    @State private var exportURL: URL?
    @State private var pendingImport: AppData?
    @State private var errorMessage: String?
    @State private var notificationStatusText = ""
    @State private var showAbout = false
    @State private var didLoadOwner = false

    private var settings: AppSettings { store.state.settings }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                preferencesCard
                remindersCard
                dataCard
                storageCard
                aboutCard
                dangerCard
                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 10)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !didLoadOwner {
                ownerName = settings.ownerName
                didLoadOwner = true
            }
            Task {
                await ReminderService.shared.refreshAuthorizationStatus()
                notificationStatusText = authorizationText
            }
        }
        .sheet(item: Binding(
            get: { exportURL.map { ExportFile(url: $0) } },
            set: { exportURL = $0?.url }
        )) { file in
            ShareSheet(items: [file.url])
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .alert("Replace all data?", isPresented: Binding(
            get: { pendingImport != nil },
            set: { if !$0 { pendingImport = nil } }
        ), presenting: pendingImport) { data in
            Button("Cancel", role: .cancel) { pendingImport = nil }
            Button("Replace everything", role: .destructive) {
                store.send(.replaceAllData(data))
                pendingImport = nil
            }
        } message: { data in
            Text("The backup holds \(data.decisions.count) decisions and \(data.evidence.count) evidence items. Everything currently in the app will be replaced. Attachment files are not part of a backup — evidence that had a file will show it as missing.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Delete all data?", isPresented: $showDeleteAll) {
            TextField("Type DELETE to confirm", text: $deleteConfirmationText)
                .textInputAutocapitalization(.characters)
            Button("Cancel", role: .cancel) { deleteConfirmationText = "" }
            Button("Delete everything", role: .destructive) {
                if deleteConfirmationText.popTrimmed.uppercased() == "DELETE" {
                    store.send(.deleteAllData)
                } else {
                    errorMessage = "Nothing was deleted. Type DELETE exactly to confirm."
                }
                deleteConfirmationText = ""
            }
        } message: {
            Text("Every decision, criterion, option, evidence item, claim, risk, scenario and review will be removed from this device permanently. Export a backup first if you might want any of it back.")
        }
        .sheet(isPresented: $showAbout) {
            AboutSheet()
        }
    }

    // MARK: Preferences

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            POPSectionHeader(title: "Preferences", icon: "slider.horizontal.3")

            POPMenuPicker(
                label: "Default Currency",
                options: AppSettings.supportedCurrencies.map { CurrencyOption(code: $0) },
                selection: Binding(
                    get: { CurrencyOption(code: settings.defaultCurrency) },
                    set: { store.send(.setDefaultCurrency($0.code)) }
                ),
                titleFor: { "\($0.code) · \(POPFormat.currencySymbol(for: $0.code))" },
                hint: "Used for new decisions. Existing decisions keep the currency they were created with."
            )

            POPFieldShell(
                label: "Rating Scale",
                hint: "Changing to a smaller scale adjusts existing ratings that would fall outside it."
            ) {
                POPInlineSegments(
                    options: AppSettings.supportedScales.map { ScaleOption(value: $0) },
                    selection: Binding(
                        get: { ScaleOption(value: settings.ratingScaleMax) },
                        set: { store.send(.setRatingScale($0.value)) }
                    ),
                    titleFor: { "1 – \($0.value)" }
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                POPTextField(
                    label: "Decision Owner Name",
                    text: $ownerName,
                    placeholder: "Used as the default owner on new decisions",
                    characterLimit: 60
                )
                if ownerName.popTrimmed != settings.ownerName {
                    POPTextButton(title: "Save name", icon: "checkmark") {
                        store.send(.setOwnerName(ownerName))
                    }
                }
            }

            POPToggleRow(
                title: "Haptic Feedback",
                subtitle: "Small vibrations when you tap, save or hit an error.",
                icon: "hand.tap",
                isOn: Binding(
                    get: { settings.hapticsEnabled },
                    set: { store.send(.setHapticsEnabled($0)) }
                )
            )
        }
        .popCard()
    }

    // MARK: Reminders

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            POPSectionHeader(
                title: "Reminder Settings",
                subtitle: "Local notifications for deadlines, outcome reviews, claim deadlines, risk reviews and follow-up tasks.",
                icon: "bell"
            )

            POPToggleRow(
                title: "Enable Reminders",
                subtitle: notificationStatusText.isEmpty ? nil : notificationStatusText,
                icon: "bell.badge",
                isOn: Binding(
                    get: { settings.remindersEnabled },
                    set: { newValue in
                        if newValue {
                            Task {
                                let granted = await ReminderService.shared.requestAuthorization()
                                notificationStatusText = authorizationText
                                if granted {
                                    store.send(.setRemindersEnabled(true))
                                } else {
                                    store.send(.setRemindersEnabled(false))
                                    errorMessage = "Notifications are not allowed for ProofPath. Turn them on in the iOS Settings app, then try again."
                                }
                            }
                        } else {
                            store.send(.setRemindersEnabled(false))
                        }
                    }
                )
            )

            if settings.remindersEnabled {
                POPFieldShell(label: "Remind me before a deadline") {
                    POPInlineSegments(
                        options: [LeadOption(days: 1), LeadOption(days: 3), LeadOption(days: 7)],
                        selection: Binding(
                            get: { LeadOption(days: settings.reminderLeadDays) },
                            set: { store.send(.setReminderLeadDays($0.days)) }
                        ),
                        titleFor: { $0.days == 1 ? "1 day" : "\($0.days) days" }
                    )
                }
                POPInlineNote(text: "Reminders fire at 09:00 on the day. iOS allows a limited number of pending reminders, so the nearest ones are scheduled first.")
            }
        }
        .popCard()
    }

    private var authorizationText: String {
        switch ReminderService.shared.authorizationStatus {
        case .authorized, .provisional: return "Notifications allowed"
        case .denied: return "Notifications are blocked in iOS Settings"
        case .notDetermined: return "Permission has not been requested yet"
        default: return ""
        }
    }

    // MARK: Data

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            POPSectionHeader(title: "Data", icon: "externaldrive")
                .padding(.horizontal, POPMetrics.cardPadding)
                .padding(.top, POPMetrics.cardPadding)
                .padding(.bottom, 6)

            POPActionRow(
                title: "Export All Data",
                subtitle: "One JSON file with every decision and evidence record.",
                icon: "square.and.arrow.up",
                showsChevron: false
            ) {
                switch store.exportBackup() {
                case .success(let url): exportURL = url
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
            .padding(.horizontal, POPMetrics.cardPadding)
            .padding(.vertical, 4)

            POPDivider(inset: POPMetrics.cardPadding + 41)

            POPActionRow(
                title: "Import Backup",
                subtitle: "Replaces everything currently in the app.",
                icon: "square.and.arrow.down",
                showsChevron: false
            ) {
                showImporter = true
            }
            .padding(.horizontal, POPMetrics.cardPadding)
            .padding(.vertical, 4)

            POPDivider(inset: POPMetrics.cardPadding + 41)

            NavigationLink(value: AppRoute.archived) {
                POPActionRowLabel(
                    title: "Archived Decisions",
                    subtitle: "\(store.state.archivedDecisions.count) archived",
                    icon: "archivebox",
                    tint: POPColor.graphite
                )
            }

            POPDivider(inset: POPMetrics.cardPadding + 41)

            NavigationLink(value: AppRoute.templates) {
                POPActionRowLabel(
                    title: "Starting Structures",
                    subtitle: "Suggested criteria for common decisions",
                    icon: "square.grid.2x2",
                    tint: POPColor.graphite
                )
            }
        }
        .popCard(padding: 0)
        .padding(.bottom, 2)
    }

    // MARK: Storage

    private var storageCard: some View {
        let usage = store.attachmentUsage
        return VStack(alignment: .leading, spacing: 12) {
            POPSectionHeader(
                title: "Attachment Storage",
                subtitle: "Photos and documents you attached, stored on this device only.",
                icon: "internaldrive"
            )
            HStack(spacing: 10) {
                POPStatTile(value: "\(usage.count)", label: "Files", icon: "doc.on.doc")
                POPStatTile(value: POPFormat.fileSize(usage.bytes), label: "Used", icon: "internaldrive")
            }
            POPSecondaryButton(title: "Clean Up Unused Files", icon: "sparkles") {
                let removed = store.pruneOrphanAttachments()
                store.showToast(
                    removed == 0 ? "Nothing to clean up" : "\(removed) unused \(removed == 1 ? "file" : "files") removed",
                    style: removed == 0 ? .info : .success
                )
            }
            POPInlineNote(text: "Attachments are not included in an exported backup — only the records that reference them.")
        }
        .popCard()
    }

    // MARK: About

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            POPActionRow(
                title: "About ProofPath",
                subtitle: "How the app works and what it deliberately does not do",
                icon: "info.circle"
            ) {
                showAbout = true
            }
            .padding(POPMetrics.cardPadding)
        }
        .popCard(padding: 0)
    }

    // MARK: Danger

    private var dangerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            POPDestructiveButton(title: "Delete All Data") {
                showDeleteAll = true
            }
            POPInlineNote(
                text: "This cannot be undone and there is no cloud copy. Export a backup first.",
                icon: "exclamationmark.triangle.fill",
                tint: POPColor.danger
            )
        }
    }

    // MARK: Import

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            switch store.importBackup(from: url) {
            case .success(let data): pendingImport = data
            case .failure(let error): errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Small option wrappers

struct ScaleOption: Identifiable, Hashable {
    let value: Int
    var id: Int { value }
}

struct LeadOption: Identifiable, Hashable {
    let days: Int
    var id: Int { days }
}

// MARK: - About

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(marketing) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ProofPath")
                            .font(POPFont.display(28))
                            .foregroundStyle(POPColor.ink)
                        Text("A workspace for decisions that deserve more than a pros-and-cons list.")
                            .font(POPFont.body)
                            .foregroundStyle(POPColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        POPBadge(text: "Version \(version)", icon: "number")
                    }

                    VStack(alignment: .leading, spacing: 11) {
                        POPSectionHeader(title: "How it works", icon: "arrow.triangle.branch")
                        aboutLine("Everything is stored locally on this device. There is no account and no server.")
                        aboutLine("Every score is calculated from criteria weights and the ratings you enter, renormalised over the criteria you actually evaluated.")
                        aboutLine("Must-Have criteria and hard constraints act as gates: an option that fails one cannot lead, whatever its score.")
                        aboutLine("Finalizing a decision saves a read-only snapshot. Reopening it creates a new version and leaves the old one intact.")
                    }
                    .popCard()

                    VStack(alignment: .leading, spacing: 11) {
                        POPSectionHeader(title: "What it deliberately does not do", icon: "hand.raised")
                        aboutLine("It does not open, fetch or verify links. Evidence marked “Source Not Checked” means exactly that.")
                        aboutLine("It never changes a claim's status because a file was attached. You decide when something is proven.")
                        aboutLine("It does not recommend an option. It shows a ranking that you can trace back to your own inputs.")
                        aboutLine("Insights describe your past decisions. They are not financial, legal or professional advice.")
                    }
                    .popCard()

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 8)
            }
            .background(POPColor.canvas.ignoresSafeArea())
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(POPFont.bodyMedium)
                        .foregroundStyle(POPColor.brandOrange)
                }
            }
        }
    }

    private func aboutLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 4))
                .foregroundStyle(POPColor.brandOrange)
                .padding(.top, 7)
            Text(text)
                .font(POPFont.callout)
                .foregroundStyle(POPColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
