//
//  EvidenceEditorSheet.swift
//  ProofOfPath
//
//  At least one of Source, Summary or Attachment is required.
//  A failed attachment never wipes the form.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct EvidenceEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let existing: Evidence?
    var presetDecisionID: UUID?
    var presetOptionID: UUID?
    var presetCriterionID: UUID?

    @State private var title = ""
    @State private var type: EvidenceType = .website
    @State private var source = ""
    @State private var dateCollected = Date()
    @State private var summary = ""
    @State private var confidence: ConfidenceLevel = .medium
    @State private var verification: VerificationStatus = .unreviewed
    @State private var sourceChecked = false
    @State private var decisionID: UUID?
    @State private var attachment: EvidenceAttachment?

    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var isLoadingAttachment = false
    @State private var attachmentError: String?
    @State private var showValidation = false
    @State private var loaded = false

    // Optional first link created together with the item.
    @State private var linkOptionID: UUID?
    @State private var linkCriterionID: UUID?
    @State private var linkRelation: EvidenceRelation = .supports

    private var decision: Decision? { store.state.decision(id: decisionID) }

    private var availableDecisions: [Decision] {
        store.state.decisions.filter { $0.status != .archived }
    }

    private var hasMinimumContent: Bool {
        !source.popIsBlank || !summary.popIsBlank || attachment != nil
    }

    private var contentError: String? {
        guard showValidation, !hasMinimumContent else { return nil }
        return "Add a source, a summary or an attachment. An empty record cannot be saved."
    }

    private var decisionError: String? {
        guard showValidation, decisionID == nil else { return nil }
        return "Choose which decision this belongs to."
    }

    private var isValid: Bool { hasMinimumContent && decisionID != nil }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {

                    if availableDecisions.isEmpty {
                        POPBanner(kind: .warning, message: "No decisions available.",
                                  detail: "Evidence always belongs to a decision. Create one first.")
                    }

                    POPTextField(
                        label: "Evidence Title",
                        text: $title,
                        placeholder: "e.g. Manufacturer spec sheet",
                        hint: "Optional, but a title makes the inbox usable.",
                        characterLimit: 90
                    )

                    POPSegmentedPicker(
                        label: "Evidence Type",
                        options: EvidenceType.allCases,
                        selection: $type,
                        titleFor: { $0.title },
                        iconFor: { $0.icon },
                        columns: 2
                    )

                    if !availableDecisions.isEmpty {
                        POPFieldShell(label: "Decision", isRequired: true, errorText: decisionError) {
                            Menu {
                                ForEach(availableDecisions) { candidate in
                                    Button(action: {
                                        Haptics.selection()
                                        if decisionID != candidate.id {
                                            decisionID = candidate.id
                                            linkOptionID = nil
                                            linkCriterionID = nil
                                        }
                                    }) {
                                        if decisionID == candidate.id {
                                            Label(candidate.displayTitle, systemImage: "checkmark")
                                        } else {
                                            Text(candidate.displayTitle)
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: decision?.category.icon ?? "folder")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(POPColor.brandOrange)
                                    Text(decision?.displayTitle ?? "Choose a decision")
                                        .font(POPFont.body)
                                        .foregroundStyle(decision == nil ? POPColor.inkTertiary : POPColor.ink)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(POPColor.inkTertiary)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 46)
                                .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.surface))
                                .overlay(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                                    .strokeBorder(decisionError != nil ? POPColor.danger : POPColor.hairline, lineWidth: 1))
                            }
                        }
                    }

                    POPTextField(
                        label: "Source",
                        text: $source,
                        placeholder: type.expectsSourceURL ? "https://" : "Where did this come from?",
                        hint: type.expectsSourceURL
                            ? "Saved exactly as you type it. The app never opens or verifies links."
                            : "A person, shop, document name — anything you could go back to.",
                        keyboard: type.expectsSourceURL ? .URL : .default,
                        capitalization: type.expectsSourceURL ? .never : .sentences,
                        autocorrect: !type.expectsSourceURL
                    )

                    POPTextEditor(
                        label: "Summary",
                        text: $summary,
                        placeholder: "What does this actually say? Write it so future-you understands without opening the source.",
                        errorText: contentError,
                        characterLimit: 1000,
                        minHeight: 100
                    )

                    attachmentSection

                    POPDateField(
                        label: "Date Collected",
                        date: Binding(get: { dateCollected }, set: { dateCollected = $0 ?? Date() }),
                        hint: "When you found it — not today's date by default if you are entering it later."
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        POPSectionHeader(title: "Confidence Level", subtitle: "How much would you bet on this being accurate?", icon: "gauge.medium")
                        POPInlineSegments(
                            options: ConfidenceLevel.allCases,
                            selection: $confidence,
                            titleFor: { $0.title },
                            tintFor: { $0.color }
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        POPSectionHeader(title: "Verification Status", icon: "checkmark.seal")
                        POPSegmentedPicker(
                            label: "Where does it stand?",
                            options: VerificationStatus.allCases,
                            selection: $verification,
                            titleFor: { $0.title },
                            iconFor: { $0.icon },
                            columns: 2
                        )
                        if !source.popIsBlank {
                            POPToggleRow(
                                title: "I checked this source myself",
                                subtitle: sourceChecked ? nil : "Until you tick this, the item is marked Source Not Checked.",
                                icon: "checkmark.shield",
                                isOn: $sourceChecked
                            )
                        }
                    }

                    if existing == nil, let decision, !decision.options.isEmpty {
                        firstLinkSection(decision)
                    }

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 8)
            }
            .background(POPColor.canvas.ignoresSafeArea())
            .navigationTitle(existing == nil ? "Add Evidence" : "Edit Evidence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(POPColor.inkSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .font(POPFont.bodyMedium)
                        .foregroundStyle(isValid ? POPColor.brandOrange : POPColor.inkTertiary)
                }
            }
        }
        .onAppear(perform: hydrate)
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            loadPhoto(newItem)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .plainText, .rtf, .image, .spreadsheet, .presentation, .commaSeparatedText, .data],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: Attachment

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            POPFieldShell(label: "Attachment", hint: "Stored on this device only. Maximum 25 MB.") {
                VStack(spacing: 10) {
                    if isLoadingAttachment {
                        HStack(spacing: 9) {
                            ProgressView().tint(POPColor.brandOrange)
                            Text("Attaching…")
                                .font(POPFont.callout)
                                .foregroundStyle(POPColor.inkSecondary)
                            Spacer()
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surface))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(POPColor.hairline, lineWidth: 1))
                    } else if let attachment {
                        HStack(spacing: 11) {
                            if attachment.isImage, let image = store.image(named: attachment.fileName) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 46, height: 46)
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            } else {
                                Image(systemName: attachment.isImage ? "photo" : "doc.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(POPColor.brandOrange)
                                    .frame(width: 46, height: 46)
                                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(POPColor.warningSoft))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(attachment.originalName)
                                    .font(POPFont.calloutMedium)
                                    .foregroundStyle(POPColor.ink)
                                    .lineLimit(1)
                                Text(POPFormat.fileSize(attachment.byteSize))
                                    .font(POPFont.caption)
                                    .foregroundStyle(POPColor.inkSecondary)
                            }
                            Spacer(minLength: 0)
                            Button(action: {
                                Haptics.warning()
                                self.attachment = nil
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(POPColor.danger)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel(Text("Remove attachment"))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surface))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(POPColor.hairline, lineWidth: 1))
                    }

                    HStack(spacing: 9) {
                        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                            HStack(spacing: 6) {
                                Image(systemName: "photo").font(.system(size: 12, weight: .semibold))
                                Text("Choose Photo").font(POPFont.captionMedium)
                            }
                            .foregroundStyle(POPColor.graphite)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.surface))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(POPColor.graphite.opacity(0.24), lineWidth: 1.2))
                        }

                        Button(action: {
                            Haptics.tap()
                            showFileImporter = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc").font(.system(size: 12, weight: .semibold))
                                Text("Attach File").font(POPFont.captionMedium)
                            }
                            .foregroundStyle(POPColor.graphite)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.surface))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(POPColor.graphite.opacity(0.24), lineWidth: 1.2))
                        }
                        .buttonStyle(POPPressStyle())
                    }
                }
            }

            if let attachmentError {
                POPBanner(kind: .danger, message: "Attachment failed", detail: attachmentError,
                          onDismiss: { self.attachmentError = nil })
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        isLoadingAttachment = true
        attachmentError = nil
        Task {
            defer {
                isLoadingAttachment = false
                photoItem = nil
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    attachmentError = "That photo could not be read. Nothing else you typed was lost."
                    return
                }
                switch store.importImageData(data, name: "Photo") {
                case .success(let imported):
                    attachment = imported
                    if type == .website { type = .photo }
                case .failure(let error):
                    attachmentError = error.localizedDescription
                }
            } catch {
                attachmentError = "That photo could not be read. Nothing else you typed was lost."
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        attachmentError = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            isLoadingAttachment = true
            defer { isLoadingAttachment = false }
            switch store.importAttachment(from: url) {
            case .success(let imported):
                attachment = imported
                if type == .website && !imported.isImage { type = .document }
            case .failure(let error):
                attachmentError = error.localizedDescription
            }
        case .failure(let error):
            attachmentError = error.localizedDescription
        }
    }

    // MARK: First link

    private func firstLinkSection(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(
                title: "Link It Straight Away",
                subtitle: "Optional. You can also link it later from the evidence card.",
                icon: "link"
            )

            POPFieldShell(label: "Related Option") {
                Menu {
                    Button("No option") { linkOptionID = nil }
                    ForEach(decision.sortedOptions) { option in
                        Button(action: { linkOptionID = option.id }) {
                            if linkOptionID == option.id {
                                Label(option.displayName, systemImage: "checkmark")
                            } else {
                                Text(option.displayName)
                            }
                        }
                    }
                } label: {
                    menuLabel(text: decision.option(id: linkOptionID)?.displayName ?? "No option")
                }
            }

            if !decision.criteria.isEmpty {
                POPFieldShell(label: "Related Criterion") {
                    Menu {
                        Button("No criterion") { linkCriterionID = nil }
                        ForEach(decision.sortedCriteria) { criterion in
                            Button(action: { linkCriterionID = criterion.id }) {
                                if linkCriterionID == criterion.id {
                                    Label(criterion.displayName, systemImage: "checkmark")
                                } else {
                                    Text(criterion.displayName)
                                }
                            }
                        }
                    } label: {
                        menuLabel(text: decision.criterion(id: linkCriterionID)?.displayName ?? "No criterion")
                    }
                }
            }

            if linkOptionID != nil || linkCriterionID != nil {
                POPFieldShell(label: "Relation") {
                    POPInlineSegments(
                        options: EvidenceRelation.allCases,
                        selection: $linkRelation,
                        titleFor: { $0.shortTitle },
                        tintFor: { $0.color }
                    )
                }
                POPInlineNote(text: linkRelation.title)
            }
        }
        .popCard()
    }

    private func menuLabel(text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(POPFont.body)
                .foregroundStyle(POPColor.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(POPColor.inkTertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous).fill(POPColor.surface))
        .overlay(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
            .strokeBorder(POPColor.hairline, lineWidth: 1))
    }

    // MARK: Persistence

    private func hydrate() {
        guard !loaded else { return }
        loaded = true
        if let existing {
            title = existing.title
            type = existing.type
            source = existing.source
            dateCollected = existing.dateCollected
            summary = existing.summary
            confidence = existing.confidence
            verification = existing.verification
            sourceChecked = existing.sourceChecked
            decisionID = existing.decisionID
            attachment = existing.attachment
        } else {
            decisionID = presetDecisionID ?? availableDecisions.first?.id
            linkOptionID = presetOptionID
            linkCriterionID = presetCriterionID
        }
    }

    private func save() {
        guard isValid else {
            showValidation = true
            Haptics.error()
            return
        }
        var item = existing ?? Evidence()
        item.decisionID = decisionID
        item.title = title.popTrimmed
        item.type = type
        item.source = source.popTrimmed
        item.dateCollected = dateCollected
        item.summary = summary.popTrimmed
        item.confidence = confidence
        item.verification = verification
        item.sourceChecked = source.popIsBlank ? false : sourceChecked
        item.attachment = attachment

        if existing == nil {
            if linkOptionID != nil || linkCriterionID != nil {
                var link = EvidenceLink()
                link.optionID = linkOptionID
                link.criterionID = linkCriterionID
                link.relation = linkRelation
                item.links = [link]
            }
            store.send(.addEvidence(item))
        } else {
            store.send(.updateEvidence(item))
        }
        dismiss()
    }
}
