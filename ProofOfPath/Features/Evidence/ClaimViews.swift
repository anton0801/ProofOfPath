//
//  ClaimViews.swift
//  ProofOfPath
//
//  Claim Check — the app never changes a claim's status by itself.
//

import SwiftUI

// MARK: - Editor

struct ClaimEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID
    let existing: Claim?
    var presetOptionID: UUID?

    @State private var text = ""
    @State private var claimedBy = ""
    @State private var optionID: UUID?
    @State private var date = Date()
    @State private var whyItMatters = ""
    @State private var verificationDeadline: Date?
    @State private var status: ClaimStatus = .unverified
    @State private var missingProof = ""
    @State private var showValidation = false
    @State private var loaded = false

    private var decision: Decision? { store.state.decision(id: decisionID) }

    private var textError: String? {
        guard showValidation, text.popIsBlank else { return nil }
        return "Write down the claim itself."
    }

    private var isValid: Bool { !text.popIsBlank }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                    POPBanner(
                        kind: .neutral,
                        message: "A claim is something stated, not something proven.",
                        detail: "Seller promises, advertising copy, or your own assumptions all belong here."
                    )

                    POPTextEditor(
                        label: "Claim",
                        text: $text,
                        placeholder: "e.g. “The warranty covers accidental damage for 3 years.”",
                        isRequired: true,
                        errorText: textError,
                        characterLimit: 400,
                        minHeight: 92
                    )

                    POPTextField(
                        label: "Claimed by",
                        text: $claimedBy,
                        placeholder: "Salesperson, website, a friend, or yourself",
                        characterLimit: 80
                    )

                    if let decision, !decision.options.isEmpty {
                        POPFieldShell(label: "Related Option") {
                            Menu {
                                Button("Applies to the whole decision") { optionID = nil }
                                ForEach(decision.sortedOptions) { option in
                                    Button(action: { optionID = option.id }) {
                                        if optionID == option.id {
                                            Label(option.displayName, systemImage: "checkmark")
                                        } else {
                                            Text(option.displayName)
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(decision.option(id: optionID)?.displayName ?? "Applies to the whole decision")
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
                        }
                    }

                    POPDateField(
                        label: "Date",
                        date: Binding(get: { date }, set: { date = $0 ?? Date() }),
                        hint: "When was it claimed?"
                    )

                    POPTextEditor(
                        label: "Why It Matters",
                        text: $whyItMatters,
                        placeholder: "What changes if this turns out to be false?",
                        characterLimit: 400,
                        minHeight: 80
                    )

                    POPDateField(
                        label: "Verification Deadline",
                        date: $verificationDeadline,
                        hint: "Optional. A reminder is scheduled if reminders are on."
                    )

                    POPTextEditor(
                        label: "Missing Proof",
                        text: $missingProof,
                        placeholder: "What exactly would settle this?",
                        hint: "Naming the missing proof makes it far easier to find.",
                        characterLimit: 400,
                        minHeight: 80
                    )

                    if existing != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            POPSectionHeader(title: "Status", icon: "flag")
                            POPSegmentedPicker(
                                label: "Change Status",
                                options: ClaimStatus.allCases,
                                selection: $status,
                                titleFor: { $0.title },
                                iconFor: { $0.icon },
                                columns: 1
                            )
                            POPInlineNote(text: "The app never changes this automatically — attaching a file is not the same as proving something.")
                        }
                    }

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 8)
            }
            .background(POPColor.canvas.ignoresSafeArea())
            .navigationTitle(existing == nil ? "Add Claim" : "Edit Claim")
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
    }

    private func hydrate() {
        guard !loaded else { return }
        loaded = true
        if let existing {
            text = existing.text
            claimedBy = existing.claimedBy
            optionID = existing.optionID
            date = existing.date
            whyItMatters = existing.whyItMatters
            verificationDeadline = existing.verificationDeadline
            status = existing.status
            missingProof = existing.missingProof
        } else {
            optionID = presetOptionID
        }
    }

    private func save() {
        guard isValid else {
            showValidation = true
            Haptics.error()
            return
        }
        var claim = existing ?? Claim()
        claim.text = text.popTrimmed
        claim.claimedBy = claimedBy.popTrimmed
        claim.optionID = optionID
        claim.date = date
        claim.whyItMatters = whyItMatters.popTrimmed
        claim.verificationDeadline = verificationDeadline
        claim.missingProof = missingProof.popTrimmed
        if existing != nil { claim.status = status }

        if existing == nil {
            store.send(.addClaim(decisionID: decisionID, claim: claim))
        } else {
            store.send(.updateClaim(decisionID: decisionID, claim: claim))
        }
        dismiss()
    }
}

// MARK: - Detail

struct ClaimDetailSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID
    let claimID: UUID

    @State private var showEditor = false
    @State private var showEvidencePicker = false
    @State private var pickingSupporting = true
    @State private var pendingDelete = false
    @State private var showRequestSheet = false
    @State private var requestDeadline: Date?

    private var decision: Decision? { store.state.decision(id: decisionID) }
    private var claim: Claim? { decision?.claim(id: claimID) }

    private func evidence(_ ids: [UUID]) -> [Evidence] {
        ids.compactMap { store.state.evidenceItem(id: $0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let claim, let decision {
                    content(claim: claim, decision: decision)
                } else {
                    POPEmptyState(icon: "questionmark.folder", title: "Claim not found",
                                  message: "This claim was deleted.",
                                  actionTitle: "Close", action: { dismiss() })
                        .background(POPColor.canvas.ignoresSafeArea())
                }
            }
        }
    }

    private func content(claim: Claim, decision: Decision) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                headerCard(claim: claim, decision: decision)
                statusCard(claim)
                evidenceCard(
                    title: "Supporting Evidence",
                    icon: "checkmark.circle.fill",
                    tint: POPColor.success,
                    items: evidence(claim.supportingEvidenceIDs),
                    emptyMessage: "Nothing supports this claim yet.",
                    addTitle: "Add Supporting Evidence",
                    onAdd: {
                        pickingSupporting = true
                        showEvidencePicker = true
                    },
                    onRemove: { item in
                        store.send(.unlinkClaimEvidence(decisionID: decisionID, claimID: claimID, evidenceID: item.id))
                    }
                )
                evidenceCard(
                    title: "Contradicting Evidence",
                    icon: "xmark.circle.fill",
                    tint: POPColor.danger,
                    items: evidence(claim.contradictingEvidenceIDs),
                    emptyMessage: "Nothing contradicts this claim yet.",
                    addTitle: "Add Contradicting Evidence",
                    onAdd: {
                        pickingSupporting = false
                        showEvidencePicker = true
                    },
                    onRemove: { item in
                        store.send(.unlinkClaimEvidence(decisionID: decisionID, claimID: claimID, evidenceID: item.id))
                    }
                )
                missingProofCard(claim)
                actionsCard(claim)
                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 8)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationTitle("Claim Check")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                    .foregroundStyle(POPColor.inkSecondary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEditor = true } label: { Label("Edit Claim", systemImage: "pencil") }
                    Button(role: .destructive) { pendingDelete = true } label: {
                        Label("Delete Claim", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(POPColor.graphite)
                }
                .accessibilityLabel(Text("Claim actions"))
            }
        }
        .sheet(isPresented: $showEditor) {
            ClaimEditorSheet(decisionID: decisionID, existing: claim)
        }
        .sheet(isPresented: $showEvidencePicker) {
            ClaimEvidencePicker(
                decisionID: decisionID,
                claimID: claimID,
                supporting: pickingSupporting
            )
        }
        .sheet(isPresented: $showRequestSheet) {
            RequestVerificationSheet(decisionID: decisionID, claimID: claimID, initialDeadline: claim.verificationDeadline)
        }
        .alert("Delete this claim?", isPresented: $pendingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.send(.deleteClaim(decisionID: decisionID, claimID: claimID))
                dismiss()
            }
        } message: {
            Text("The evidence itself stays in your inbox — only the claim record is removed.")
        }
    }

    // MARK: Cards

    private func headerCard(claim: Claim, decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(claim.displayText)
                .font(POPFont.title)
                .foregroundStyle(POPColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                POPBadge(text: claim.status.title, icon: claim.status.icon,
                         color: claim.status.color, soft: claim.status.softColor)
                if let option = decision.option(id: claim.optionID) {
                    POPBadge(text: option.displayName.popTruncated(24), icon: "square.stack")
                } else {
                    POPBadge(text: "Whole decision", icon: "doc.text")
                }
                Spacer(minLength: 0)
            }

            POPDivider()
            POPKeyValueRow(label: "Claimed by", value: claim.claimedBy.popIsBlank ? "Not recorded" : claim.claimedBy, icon: "person")
            POPKeyValueRow(label: "Date", value: POPFormat.date(claim.date), icon: "calendar")
            if let deadline = claim.verificationDeadline {
                POPKeyValueRow(
                    label: "Verification Deadline",
                    value: "\(POPFormat.date(deadline)) · \(POPFormat.relativeDeadline(deadline))",
                    valueColor: POPFormat.daysUntil(deadline) < 0 && claim.status.isOpen ? POPColor.danger : POPColor.ink,
                    icon: "clock.badge.exclamationmark"
                )
            }
            if !claim.whyItMatters.popIsBlank {
                POPDivider()
                POPKeyValueRow(label: "Why It Matters", value: claim.whyItMatters, icon: "questionmark.circle", isMultiline: true)
            }
        }
        .popCard()
    }

    private func statusCard(_ claim: Claim) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(
                title: "Change Status",
                subtitle: "You decide when a claim is settled — attaching evidence is not the same as proving it.",
                icon: "flag"
            )
            VStack(spacing: 7) {
                ForEach(ClaimStatus.allCases) { candidate in
                    Button(action: {
                        Haptics.selection()
                        store.send(.setClaimStatus(decisionID: decisionID, claimID: claimID, status: candidate))
                    }) {
                        HStack(spacing: 9) {
                            Image(systemName: candidate.icon)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(candidate.color)
                            Text(candidate.title)
                                .font(POPFont.calloutMedium)
                                .foregroundStyle(POPColor.ink)
                            Spacer(minLength: 0)
                            if claim.status == candidate {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(candidate.color)
                            }
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(claim.status == candidate ? candidate.softColor : POPColor.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(claim.status == candidate ? candidate.color.opacity(0.45) : POPColor.hairline,
                                          lineWidth: claim.status == candidate ? 1.4 : 1))
                    }
                    .buttonStyle(POPPressStyle())
                }
            }
        }
        .popCard()
    }

    private func evidenceCard(
        title: String,
        icon: String,
        tint: Color,
        items: [Evidence],
        emptyMessage: String,
        addTitle: String,
        onAdd: @escaping () -> Void,
        onRemove: @escaping (Evidence) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(POPFont.sectionTitle)
                    .foregroundStyle(POPColor.ink)
                Spacer()
                Text("\(items.count)")
                    .font(POPFont.captionMedium)
                    .foregroundStyle(POPColor.inkSecondary)
            }

            if items.isEmpty {
                POPInlineNote(text: emptyMessage)
            } else {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: item.type.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayTitle)
                                .font(POPFont.calloutMedium)
                                .foregroundStyle(POPColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 6) {
                                POPBadge(text: item.verification.title, color: item.verification.color,
                                         soft: item.verification.softColor, compact: true)
                                ConfidenceMarker(level: item.confidence, showLabel: false)
                            }
                        }
                        Spacer(minLength: 0)
                        Button(action: {
                            Haptics.tap()
                            onRemove(item)
                        }) {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(POPColor.inkTertiary)
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(Text("Unlink evidence"))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.surfaceMuted))
                }
            }

            POPSecondaryButton(title: addTitle, icon: "plus", tint: tint, action: onAdd)
        }
        .popCard()
    }

    private func missingProofCard(_ claim: Claim) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            POPSectionHeader(title: "Missing Proof", icon: "questionmark.folder")
            if claim.missingProof.popIsBlank {
                POPInlineNote(text: "Nothing written. Naming exactly what would settle this makes it much easier to find.")
            } else {
                Text(claim.missingProof)
                    .font(POPFont.body)
                    .foregroundStyle(POPColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .popCard()
    }

    private func actionsCard(_ claim: Claim) -> some View {
        VStack(spacing: 10) {
            if claim.status.isOpen {
                POPSecondaryButton(
                    title: claim.verificationRequested ? "Update Verification Follow-Up" : "Request Verification",
                    icon: "flag"
                ) {
                    showRequestSheet = true
                }
            }
            if claim.verificationRequested {
                POPInlineNote(text: "A follow-up task was created for this claim. Find it in Open Questions.", icon: "checkmark.circle")
            }
        }
    }
}

// MARK: - Request verification

struct RequestVerificationSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID
    let claimID: UUID
    var initialDeadline: Date?

    @State private var deadline: Date?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                    POPBanner(
                        kind: .neutral,
                        message: "This creates a follow-up task for you.",
                        detail: "ProofPath does not contact anyone. The task appears in Open Questions, and a reminder is scheduled if reminders are on."
                    )
                    POPDateField(
                        label: "Verify By",
                        date: $deadline,
                        hint: "Optional. Leave empty for a task without a due date."
                    )
                    POPPrimaryButton(title: "Create Follow-Up") {
                        store.send(.requestClaimVerification(decisionID: decisionID, claimID: claimID, deadline: deadline))
                        dismiss()
                    }
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 8)
            }
            .background(POPColor.canvas.ignoresSafeArea())
            .navigationTitle("Request Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(POPColor.inkSecondary)
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            deadline = initialDeadline ?? Calendar.current.date(byAdding: .day, value: 7, to: Date())
        }
    }
}

// MARK: - Claim evidence picker

struct ClaimEvidencePicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID
    let claimID: UUID
    let supporting: Bool

    @State private var search = ""
    @State private var showNewEvidence = false

    private var claim: Claim? { store.state.decision(id: decisionID)?.claim(id: claimID) }

    private var candidates: [Evidence] {
        let all = store.state.evidence(forDecision: decisionID)
        guard !search.popIsBlank else { return all }
        let needle = search.popNormalizedForCompare
        return all.filter {
            $0.title.popNormalizedForCompare.contains(needle)
                || $0.summary.popNormalizedForCompare.contains(needle)
        }
    }

    private func isLinked(_ item: Evidence) -> Bool {
        guard let claim else { return false }
        return supporting
            ? claim.supportingEvidenceIDs.contains(item.id)
            : claim.contradictingEvidenceIDs.contains(item.id)
    }

    private func isLinkedOpposite(_ item: Evidence) -> Bool {
        guard let claim else { return false }
        return supporting
            ? claim.contradictingEvidenceIDs.contains(item.id)
            : claim.supportingEvidenceIDs.contains(item.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    POPBanner(
                        kind: supporting ? .success : .danger,
                        message: supporting ? "Pick evidence that supports the claim." : "Pick evidence that contradicts the claim.",
                        detail: "Linking evidence never changes the claim's status — you set that yourself."
                    )

                    if !store.state.evidence(forDecision: decisionID).isEmpty {
                        POPSearchField(text: $search, placeholder: "Search this decision's evidence")
                    }

                    if candidates.isEmpty {
                        POPEmptyState(
                            icon: "paperclip",
                            title: store.state.evidence(forDecision: decisionID).isEmpty ? "No evidence yet" : "No matches",
                            message: store.state.evidence(forDecision: decisionID).isEmpty
                                ? "Add material to this decision first."
                                : "Try a different search term.",
                            actionTitle: "Add Evidence",
                            action: { showNewEvidence = true },
                            compact: true
                        )
                        .popCard(padding: 4)
                    } else {
                        ForEach(candidates) { item in
                            Button(action: {
                                Haptics.selection()
                                if isLinked(item) {
                                    store.send(.unlinkClaimEvidence(decisionID: decisionID, claimID: claimID, evidenceID: item.id))
                                } else {
                                    store.send(.linkClaimEvidence(decisionID: decisionID, claimID: claimID,
                                                                  evidenceID: item.id, supporting: supporting))
                                }
                            }) {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: isLinked(item) ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(isLinked(item) ? (supporting ? POPColor.success : POPColor.danger) : POPColor.hairline)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.displayTitle)
                                            .font(POPFont.calloutMedium)
                                            .foregroundStyle(POPColor.ink)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text("\(item.type.title) · \(POPFormat.date(item.dateCollected))")
                                            .font(POPFont.caption)
                                            .foregroundStyle(POPColor.inkSecondary)
                                        if isLinkedOpposite(item) {
                                            POPBadge(
                                                text: supporting ? "Currently listed as contradicting" : "Currently listed as supporting",
                                                icon: "arrow.left.arrow.right",
                                                color: POPColor.brandOrange, soft: POPColor.warningSoft, compact: true
                                            )
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    ConfidenceMarker(level: item.confidence, showLabel: false)
                                }
                                .padding(11)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surface))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(POPColor.hairline, lineWidth: 1))
                            }
                            .buttonStyle(POPPressStyle())
                        }

                        POPSecondaryButton(title: "Add New Evidence", icon: "plus") {
                            showNewEvidence = true
                        }
                    }

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 8)
            }
            .background(POPColor.canvas.ignoresSafeArea())
            .navigationTitle(supporting ? "Supporting Evidence" : "Contradicting Evidence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(POPFont.bodyMedium)
                        .foregroundStyle(POPColor.brandOrange)
                }
            }
            .sheet(isPresented: $showNewEvidence) {
                EvidenceEditorSheet(existing: nil, presetDecisionID: decisionID)
            }
        }
    }
}
