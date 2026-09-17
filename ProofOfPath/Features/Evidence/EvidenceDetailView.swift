//
//  EvidenceDetailView.swift
//  ProofOfPath
//

import SwiftUI
import QuickLook

struct EvidenceDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var submission = POPSubmission()
    @Environment(\.openURL) private var openURL

    let evidenceID: UUID

    @State private var showEditor = false
    @State private var showLinkPicker = false
    @State private var pendingDelete = false
    @State private var previewURL: URL?
    @State private var showOpenSourceConfirm = false

    private var evidence: Evidence? { store.state.evidenceItem(id: evidenceID) }
    private var decision: Decision? { store.state.decision(id: evidence?.decisionID) }

    var body: some View {
        Group {
            if let evidence {
                content(evidence)
            } else {
                POPEmptyState(
                    icon: "questionmark.folder",
                    title: "Evidence not found",
                    message: "This item was deleted.",
                    actionTitle: "Back",
                    action: { dismiss() }
                )
                .background(POPColor.canvas.ignoresSafeArea())
            }
        }
    }

    private func content(_ evidence: Evidence) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                header(evidence)
                if evidence.attachment != nil { attachmentCard(evidence) }
                detailsCard(evidence)
                verificationCard(evidence)
                linksCard(evidence)
                usageCard(evidence)
                dangerZone
                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 10)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationTitle("Evidence Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    Haptics.tap()
                    showEditor = true
                }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(POPColor.graphite)
                }
                .accessibilityLabel(Text("Edit evidence"))
            }
        }
        .sheet(isPresented: $showEditor) {
            EvidenceEditorSheet(existing: evidence)
        }
        .sheet(isPresented: $showLinkPicker) {
            if let decisionID = evidence.decisionID {
                EvidenceLinksEditor(evidenceID: evidenceID, decisionID: decisionID)
            }
        }
        .quickLookPreview($previewURL)
        .alert("Delete this evidence?", isPresented: $pendingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                submission.run(store, .deleteEvidence(evidenceID)) { dismiss() }
            }
        } message: {
            Text(deleteMessage(evidence))
        }
        .alert("Open this source?", isPresented: $showOpenSourceConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Open") { openSource(evidence) }
        } message: {
            Text("This opens \(evidence.source) outside the app. ProofPath does not check or verify links.")
        }
    }

    private func deleteMessage(_ evidence: Evidence) -> String {
        var parts: [String] = []
        if !evidence.links.isEmpty {
            parts.append("\(evidence.links.count) rating \(evidence.links.count == 1 ? "link" : "links")")
        }
        let claimUses = decision?.claims.filter {
            $0.supportingEvidenceIDs.contains(evidenceID) || $0.contradictingEvidenceIDs.contains(evidenceID)
        }.count ?? 0
        if claimUses > 0 { parts.append("\(claimUses) claim \(claimUses == 1 ? "reference" : "references")") }
        if evidence.attachment != nil { parts.append("its attachment") }

        if parts.isEmpty { return "This item is not linked to anything yet." }
        return "Deleting removes \(parts.joined(separator: ", ")). Ratings that relied on it fall back to Preliminary."
    }

    // MARK: Header

    private func header(_ evidence: Evidence) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: evidence.type.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(POPColor.brandOrange)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(POPColor.warningSoft))
                VStack(alignment: .leading, spacing: 4) {
                    Text(evidence.displayTitle)
                        .font(POPFont.title)
                        .foregroundStyle(POPColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(evidence.type.title) · collected \(POPFormat.date(evidence.dateCollected))")
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 7) {
                POPBadge(text: evidence.verification.title, icon: evidence.verification.icon,
                         color: evidence.verification.color, soft: evidence.verification.softColor)
                ConfidenceMarker(level: evidence.confidence)
                Spacer(minLength: 0)
            }

            if let decision {
                POPDivider()
                NavigationLink(value: AppRoute.decision(decision.id)) {
                    HStack(spacing: 8) {
                        Image(systemName: decision.category.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(POPColor.inkSecondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Belongs to")
                                .font(POPFont.micro)
                                .foregroundStyle(POPColor.inkTertiary)
                            Text(decision.displayTitle)
                                .font(POPFont.calloutMedium)
                                .foregroundStyle(POPColor.ink)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(POPColor.inkTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(POPPressStyle())
            }
        }
        .popCard()
    }

    // MARK: Attachment

    private func attachmentCard(_ evidence: Evidence) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Attachment", icon: "paperclip")

            if let attachment = evidence.attachment {
                let fileExists = store.attachmentExists(attachment.fileName)
                let isDownloading = !fileExists && store.isDownloadingAttachment(attachment.fileName)

                if attachment.isImage, let image = store.image(named: attachment.fileName) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(POPColor.hairline, lineWidth: 1))
                }

                HStack(spacing: 11) {
                    Image(systemName: attachment.isImage ? "photo" : "doc.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(fileExists ? POPColor.brandOrange : POPColor.danger)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(fileExists ? POPColor.warningSoft : POPColor.dangerSoft))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.originalName)
                            .font(POPFont.calloutMedium)
                            .foregroundStyle(POPColor.ink)
                            .lineLimit(1)
                        Text(fileExists ? POPFormat.fileSize(attachment.byteSize) : isDownloading ? "Downloading…" : "File not available")
                            .font(POPFont.caption)
                            .foregroundStyle(fileExists ? POPColor.inkSecondary : POPColor.danger)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 9) {
                    POPPillButton(title: "Preview", icon: "eye", filled: true, isEnabled: fileExists) {
                        previewURL = store.attachmentURL(attachment.fileName)
                    }
                    POPPillButton(title: "Replace", icon: "arrow.triangle.2.circlepath") {
                        showEditor = true
                    }
                    .popRequiresConnection()
                    Spacer(minLength: 0)
                }

                if !fileExists && !isDownloading {
                    POPInlineNote(
                        text: store.connection == .online
                            ? "The file could not be loaded from your account. Replace it or remove the attachment."
                            : "The file has not been downloaded to this device yet. Connect to the internet to view it.",
                        icon: "exclamationmark.triangle.fill",
                        tint: POPColor.danger
                    )
                }
            }
        }
        .popCard()
    }

    // MARK: Details

    private func detailsCard(_ evidence: Evidence) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Source and Summary", icon: "text.quote")

            if evidence.hasExternalSource {
                VStack(alignment: .leading, spacing: 7) {
                    POPKeyValueRow(label: "Source", value: evidence.source, icon: "link", isMultiline: true)
                    HStack(spacing: 9) {
                        if isOpenableURL(evidence.source) {
                            POPPillButton(title: "Open Source", icon: "arrow.up.right.square") {
                                showOpenSourceConfirm = true
                            }
                        }
                        POPBadge(
                            text: evidence.sourceChecked ? "You checked this source" : "Source Not Checked",
                            icon: evidence.sourceChecked ? "checkmark.shield.fill" : "shield.slash",
                            color: evidence.sourceChecked ? POPColor.success : POPColor.inkSecondary,
                            soft: evidence.sourceChecked ? POPColor.successSoft : POPColor.neutralSoft,
                            compact: true
                        )
                        Spacer(minLength: 0)
                    }
                }
                POPDivider()
            }

            if !evidence.summary.popIsBlank {
                POPKeyValueRow(label: "Summary", value: evidence.summary, icon: "text.alignleft", isMultiline: true)
            } else {
                POPInlineNote(text: "No summary written. A summary makes this useful without reopening the source.")
            }

            POPDivider()
            POPKeyValueRow(label: "Last updated", value: POPFormat.dateTime(evidence.updatedAt), icon: "clock")
        }
        .popCard()
    }

    private func isOpenableURL(_ text: String) -> Bool {
        let trimmed = text.popTrimmed
        guard trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") else { return false }
        return URL(string: trimmed) != nil
    }

    private func openSource(_ evidence: Evidence) {
        // Re-checked here as well as at render time: only http(s) is ever opened,
        // so a stored string can never launch another app's scheme.
        guard isOpenableURL(evidence.source),
              let url = URL(string: evidence.source.popTrimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return }
        openURL(url)
    }

    // MARK: Verification

    private func verificationCard(_ evidence: Evidence) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(
                title: "Source Reliability",
                subtitle: "Only you can decide this — the app never verifies anything by itself.",
                icon: "checkmark.seal"
            )

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(VerificationStatus.allCases) { status in
                    Button(action: {
                        Haptics.selection()
                        store.send(.setEvidenceVerification(evidenceID: evidenceID, status: status))
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: status.icon).font(.system(size: 11, weight: .bold))
                            Text(status.title)
                                .font(POPFont.captionMedium)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(evidence.verification == status ? status.color : POPColor.inkSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 40)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(evidence.verification == status ? status.softColor : POPColor.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(evidence.verification == status ? status.color.opacity(0.45) : POPColor.hairline,
                                          lineWidth: evidence.verification == status ? 1.4 : 1))
                    }
                    .buttonStyle(POPPressStyle())
                }
            }

            if evidence.verification.isWeak {
                POPInlineNote(
                    text: evidence.verification == .outdated
                        ? "Outdated evidence no longer counts as support for a rating."
                        : "Contradicted evidence no longer counts as support for a rating.",
                    icon: "info.circle",
                    tint: POPColor.brandOrange
                )
            }
        }
        .popCard()
    }

    // MARK: Links

    private func linksCard(_ evidence: Evidence) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(
                title: "Used in Evaluations",
                subtitle: "One item can support one rating and contradict another.",
                icon: "arrow.triangle.branch"
            )

            if evidence.links.isEmpty {
                POPInlineNote(text: "Not linked to any option or criterion yet.")
            } else if let decision {
                ForEach(evidence.links) { link in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: link.relation.icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(link.relation.color)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(linkTargetName(link, decision: decision))
                                .font(POPFont.calloutMedium)
                                .foregroundStyle(POPColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(link.relation.title)
                                .font(POPFont.caption)
                                .foregroundStyle(link.relation.color)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(link.relation.softColor))
                }
            }

            if evidence.decisionID != nil {
                POPSecondaryButton(title: "Manage Links", icon: "link") {
                    showLinkPicker = true
                }
            }
        }
        .popCard()
    }

    private func linkTargetName(_ link: EvidenceLink, decision: Decision) -> String {
        let option = decision.option(id: link.optionID)?.displayName
        let criterion = decision.criterion(id: link.criterionID)?.displayName
        switch (option, criterion) {
        case (let option?, let criterion?): return "\(option) · \(criterion)"
        case (let option?, nil): return option
        case (nil, let criterion?): return criterion
        default: return "Removed target"
        }
    }

    // MARK: Usage in claims

    private func usageCard(_ evidence: Evidence) -> some View {
        let supporting = decision?.claims.filter { $0.supportingEvidenceIDs.contains(evidenceID) } ?? []
        let contradicting = decision?.claims.filter { $0.contradictingEvidenceIDs.contains(evidenceID) } ?? []

        return Group {
            if !supporting.isEmpty || !contradicting.isEmpty {
                VStack(alignment: .leading, spacing: 11) {
                    POPSectionHeader(title: "Used in Claim Checks", icon: "quote.bubble")
                    ForEach(supporting) { claim in
                        claimUsageRow(claim, relation: .supports)
                    }
                    ForEach(contradicting) { claim in
                        claimUsageRow(claim, relation: .contradicts)
                    }
                }
                .popCard()
            }
        }
    }

    private func claimUsageRow(_ claim: Claim, relation: EvidenceRelation) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: relation.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(relation.color)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(claim.displayText)
                    .font(POPFont.calloutMedium)
                    .foregroundStyle(POPColor.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                POPBadge(text: claim.status.title, icon: claim.status.icon,
                         color: claim.status.color, soft: claim.status.softColor, compact: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Danger zone

    private var dangerZone: some View {
        POPDestructiveButton(title: "Delete Evidence") {
            pendingDelete = true
        }
        .popRequiresConnection()
    }
}

// MARK: - Links editor

struct EvidenceLinksEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var submission = POPSubmission()

    let evidenceID: UUID
    let decisionID: UUID

    @State private var newOptionID: UUID?
    @State private var newCriterionID: UUID?
    @State private var newRelation: EvidenceRelation = .supports

    private var evidence: Evidence? { store.state.evidenceItem(id: evidenceID) }
    private var decision: Decision? { store.state.decision(id: decisionID) }

    private var canAdd: Bool { newOptionID != nil || newCriterionID != nil }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                    POPBanner(
                        kind: .neutral,
                        message: "Set the nature of every link explicitly.",
                        detail: "Supports, contradicts or context only — the app never assumes which one you meant."
                    )

                    if let evidence, let decision {
                        if !evidence.links.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                POPSectionHeader(title: "Current Links", icon: "arrow.triangle.branch")
                                ForEach(evidence.links) { link in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 8) {
                                            Text(targetName(link, decision: decision))
                                                .font(POPFont.calloutMedium)
                                                .foregroundStyle(POPColor.ink)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Spacer(minLength: 0)
                                            Button(action: {
                                                Haptics.warning()
                                                store.send(.removeEvidenceLink(evidenceID: evidenceID, linkID: link.id))
                                            }) {
                                                Image(systemName: "trash")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(POPColor.danger)
                                                    .frame(width: 30, height: 30)
                                                    .contentShape(Rectangle())
                                            }
                                            .accessibilityLabel(Text("Remove link"))
                                        }
                                        POPInlineSegments(
                                            options: EvidenceRelation.allCases,
                                            selection: Binding(
                                                get: { link.relation },
                                                set: { newValue in
                                                    var updated = link
                                                    updated.relation = newValue
                                                    store.send(.updateEvidenceLink(evidenceID: evidenceID, link: updated))
                                                }
                                            ),
                                            titleFor: { $0.shortTitle },
                                            tintFor: { $0.color }
                                        )
                                    }
                                    .padding(11)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surface))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(POPColor.hairline, lineWidth: 1))
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 11) {
                            POPSectionHeader(title: "Add a Link", icon: "plus.circle")

                            if decision.options.isEmpty && decision.criteria.isEmpty {
                                POPInlineNote(text: "Add options or criteria to this decision first.")
                            } else {
                                if !decision.options.isEmpty {
                                    POPFieldShell(label: "Option") {
                                        Menu {
                                            Button("No option") { newOptionID = nil }
                                            ForEach(decision.sortedOptions) { option in
                                                Button(action: { newOptionID = option.id }) {
                                                    if newOptionID == option.id {
                                                        Label(option.displayName, systemImage: "checkmark")
                                                    } else {
                                                        Text(option.displayName)
                                                    }
                                                }
                                            }
                                        } label: {
                                            pickerLabel(decision.option(id: newOptionID)?.displayName ?? "No option")
                                        }
                                    }
                                }
                                if !decision.criteria.isEmpty {
                                    POPFieldShell(label: "Criterion") {
                                        Menu {
                                            Button("No criterion") { newCriterionID = nil }
                                            ForEach(decision.sortedCriteria) { criterion in
                                                Button(action: { newCriterionID = criterion.id }) {
                                                    if newCriterionID == criterion.id {
                                                        Label(criterion.displayName, systemImage: "checkmark")
                                                    } else {
                                                        Text(criterion.displayName)
                                                    }
                                                }
                                            }
                                        } label: {
                                            pickerLabel(decision.criterion(id: newCriterionID)?.displayName ?? "No criterion")
                                        }
                                    }
                                }
                                POPFieldShell(label: "Relation", hint: newRelation.title) {
                                    POPInlineSegments(
                                        options: EvidenceRelation.allCases,
                                        selection: $newRelation,
                                        titleFor: { $0.shortTitle },
                                        tintFor: { $0.color }
                                    )
                                }
                                POPPrimaryButton(title: "Add Link", icon: "link", isEnabled: canAdd && store.canEdit,
                                                 isLoading: submission.isRunning) {
                                    var link = EvidenceLink()
                                    link.optionID = newOptionID
                                    link.criterionID = newCriterionID
                                    link.relation = newRelation
                                    submission.run(store, .addEvidenceLink(evidenceID: evidenceID, link: link)) {
                                        newOptionID = nil
                                        newCriterionID = nil
                                    }
                                }
                            }
                        }
                        .popCard()
                    }

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 8)
            }
            .background(POPColor.canvas.ignoresSafeArea())
            .navigationTitle("Manage Links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(POPFont.bodyMedium)
                        .foregroundStyle(POPColor.brandOrange)
                }
            }
        }
    }

    private func pickerLabel(_ text: String) -> some View {
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

    private func targetName(_ link: EvidenceLink, decision: Decision) -> String {
        let option = decision.option(id: link.optionID)?.displayName
        let criterion = decision.criterion(id: link.criterionID)?.displayName
        switch (option, criterion) {
        case (let option?, let criterion?): return "\(option) · \(criterion)"
        case (let option?, nil): return option
        case (nil, let criterion?): return criterion
        default: return "Removed target"
        }
    }
}
