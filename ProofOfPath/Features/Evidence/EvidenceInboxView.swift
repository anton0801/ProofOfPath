//
//  EvidenceInboxView.swift
//  ProofOfPath
//
//  The global inbox shows material from every decision.
//

import SwiftUI

enum EvidenceSort: String, CaseIterable, Identifiable, Hashable {
    case newest
    case oldest
    case confidence
    case title

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "Newest first"
        case .oldest: return "Oldest first"
        case .confidence: return "Lowest confidence first"
        case .title: return "Title A–Z"
        }
    }
}

struct EvidenceInboxView: View {
    @Environment(AppStore.self) private var store

    @State private var search = ""
    @State private var verificationFilter: VerificationStatus?
    @State private var typeFilter: EvidenceType?
    @State private var decisionFilter: UUID?
    @State private var sort: EvidenceSort = .newest
    @State private var showEditor = false
    @State private var route: AppRoute?

    private var allEvidence: [Evidence] { store.state.evidence }

    private var filtered: [Evidence] {
        var result = allEvidence

        if !search.popIsBlank {
            let needle = search.popNormalizedForCompare
            result = result.filter {
                $0.title.popNormalizedForCompare.contains(needle)
                    || $0.summary.popNormalizedForCompare.contains(needle)
                    || $0.source.popNormalizedForCompare.contains(needle)
            }
        }
        if let verificationFilter { result = result.filter { $0.verification == verificationFilter } }
        if let typeFilter { result = result.filter { $0.type == typeFilter } }
        if let decisionFilter { result = result.filter { $0.decisionID == decisionFilter } }

        switch sort {
        case .newest: result.sort { $0.dateCollected > $1.dateCollected }
        case .oldest: result.sort { $0.dateCollected < $1.dateCollected }
        case .confidence:
            let order: [ConfidenceLevel: Int] = [.low: 0, .medium: 1, .high: 2]
            result.sort { (order[$0.confidence] ?? 0) < (order[$1.confidence] ?? 0) }
        case .title:
            result.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        }
        return result
    }

    private var decisionsWithEvidence: [Decision] {
        let ids = Set(allEvidence.compactMap(\.decisionID))
        return store.state.decisions.filter { ids.contains($0.id) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                POPScreenHeader(
                    title: "Evidence Inbox",
                    subtitle: allEvidence.isEmpty ? nil : summaryLine
                )

                if store.state.decisions.isEmpty {
                    POPEmptyState(
                        icon: "paperclip",
                        title: "No decisions yet",
                        message: "Evidence belongs to a decision. Create one first, then start collecting material."
                    )
                } else if allEvidence.isEmpty {
                    POPEmptyState(
                        icon: "tray",
                        title: "Your inbox is empty",
                        message: "Add links, photos, documents, quotes and notes here. Nothing is fetched automatically — you decide what counts as evidence.",
                        actionTitle: "Add Evidence",
                        action: { showEditor = true }
                    )
                } else {
                    stats
                    POPSearchField(text: $search, placeholder: "Search titles, summaries and sources")
                    filterStrip

                    if filtered.isEmpty {
                        POPEmptyState(
                            icon: "magnifyingglass",
                            title: "No matches",
                            message: "Try a different search term or clear the filters.",
                            actionTitle: "Clear filters",
                            action: clearFilters,
                            compact: true
                        )
                        .popCard(padding: 4)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filtered) { item in
                                Button(action: {
                                    Haptics.tap()
                                    route = .evidenceDetail(item.id)
                                }) {
                                    EvidenceRow(
                                        evidence: item,
                                        decision: store.state.decision(id: item.decisionID),
                                        showsDecision: decisionFilter == nil
                                    )
                                }
                                .buttonStyle(POPPressStyle())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 6)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort by", selection: $sort) {
                        ForEach(EvidenceSort.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(POPColor.graphite)
                }
                .accessibilityLabel(Text("Sort"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    Haptics.tap()
                    showEditor = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(POPColor.graphite)
                }
                .disabled(store.state.decisions.isEmpty)
                .accessibilityLabel(Text("Add evidence"))
            }
        }
        .sheet(isPresented: $showEditor) {
            EvidenceEditorSheet(existing: nil, presetDecisionID: decisionFilter)
        }
        .navigationDestination(item: $route) { destination in
            if case .evidenceDetail(let id) = destination {
                EvidenceDetailView(evidenceID: id)
            }
        }
    }

    private var summaryLine: String {
        let unreviewed = allEvidence.filter { $0.verification == .unreviewed }.count
        var parts = ["\(allEvidence.count) items"]
        if unreviewed > 0 { parts.append("\(unreviewed) unreviewed") }
        return parts.joined(separator: " · ")
    }

    private func clearFilters() {
        search = ""
        verificationFilter = nil
        typeFilter = nil
        decisionFilter = nil
    }

    private var stats: some View {
        HStack(spacing: 10) {
            POPStatTile(
                value: "\(allEvidence.filter { $0.verification == .verified }.count)",
                label: "Verified", icon: "checkmark.seal.fill", tint: POPColor.success
            )
            POPStatTile(
                value: "\(allEvidence.filter { $0.verification == .needsVerification || $0.verification == .unreviewed }.count)",
                label: "To check", icon: "questionmark.circle", tint: POPColor.brandOrange
            )
            POPStatTile(
                value: "\(allEvidence.filter { $0.verification == .contradicted || $0.verification == .outdated }.count)",
                label: "Weak", icon: "exclamationmark.triangle", tint: POPColor.danger
            )
        }
    }

    private var filterStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    POPChip(title: "All", count: allEvidence.count, isSelected: verificationFilter == nil) {
                        verificationFilter = nil
                    }
                    ForEach(VerificationStatus.allCases) { status in
                        let count = allEvidence.filter { $0.verification == status }.count
                        if count > 0 {
                            POPChip(title: status.title, count: count, icon: status.icon,
                                    isSelected: verificationFilter == status) {
                                verificationFilter = verificationFilter == status ? nil : status
                            }
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollClipDisabled()

            if decisionsWithEvidence.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        POPChip(title: "All decisions", isSelected: decisionFilter == nil) {
                            decisionFilter = nil
                        }
                        ForEach(decisionsWithEvidence) { decision in
                            POPChip(
                                title: decision.displayTitle.popTruncated(22),
                                count: allEvidence.filter { $0.decisionID == decision.id }.count,
                                icon: decision.category.icon,
                                isSelected: decisionFilter == decision.id
                            ) {
                                decisionFilter = decisionFilter == decision.id ? nil : decision.id
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .scrollClipDisabled()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    POPChip(title: "All types", isSelected: typeFilter == nil) { typeFilter = nil }
                    ForEach(EvidenceType.allCases) { type in
                        let count = allEvidence.filter { $0.type == type }.count
                        if count > 0 {
                            POPChip(title: type.title, count: count, icon: type.icon, isSelected: typeFilter == type) {
                                typeFilter = typeFilter == type ? nil : type
                            }
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollClipDisabled()
        }
    }
}

// MARK: - Evidence row

struct EvidenceRow: View {
    let evidence: Evidence
    var decision: Decision?
    var showsDecision: Bool = false
    var showsLinks: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: evidence.type.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(POPColor.brandOrange)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(POPColor.warningSoft))

                VStack(alignment: .leading, spacing: 3) {
                    Text(evidence.displayTitle)
                        .font(POPFont.calloutMedium)
                        .foregroundStyle(POPColor.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text(evidence.type.title)
                            .font(POPFont.caption)
                            .foregroundStyle(POPColor.inkSecondary)
                        Text("·").foregroundStyle(POPColor.inkTertiary)
                        Text(POPFormat.date(evidence.dateCollected))
                            .font(POPFont.caption)
                            .foregroundStyle(POPColor.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
                ConfidenceMarker(level: evidence.confidence, showLabel: false)
            }

            if !evidence.summary.popIsBlank {
                Text(evidence.summary)
                    .font(POPFont.caption)
                    .foregroundStyle(POPColor.inkSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                POPBadge(text: evidence.verification.title, icon: evidence.verification.icon,
                         color: evidence.verification.color, soft: evidence.verification.softColor, compact: true)
                if evidence.attachment != nil {
                    POPBadge(text: "Attachment", icon: "paperclip", compact: true)
                }
                if evidence.hasExternalSource && !evidence.sourceChecked {
                    POPBadge(text: "Source Not Checked", icon: "link", compact: true)
                }
                if !evidence.links.isEmpty {
                    POPBadge(text: "\(evidence.links.count) \(evidence.links.count == 1 ? "link" : "links")",
                             icon: "arrow.triangle.branch", compact: true)
                }
                Spacer(minLength: 0)
            }

            if showsDecision, let decision {
                HStack(spacing: 5) {
                    Image(systemName: decision.category.icon).font(.system(size: 10, weight: .semibold))
                    Text(decision.displayTitle)
                        .font(POPFont.caption)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(POPColor.inkTertiary)
            }

            if showsLinks, let decision, !evidence.links.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(evidence.links) { link in
                        HStack(spacing: 5) {
                            Image(systemName: link.relation.icon)
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(link.relation.color)
                            Text(linkDescription(link, in: decision))
                                .font(.system(size: 11))
                                .foregroundStyle(POPColor.inkSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(evidence.verification == .contradicted ? POPColor.danger.opacity(0.4) : POPColor.hairline,
                          lineWidth: evidence.verification == .contradicted ? 1.4 : 1))
    }

    private func linkDescription(_ link: EvidenceLink, in decision: Decision) -> String {
        let option = decision.option(id: link.optionID)?.displayName
        let criterion = decision.criterion(id: link.criterionID)?.displayName
        let target = [option, criterion].compactMap { $0 }.joined(separator: " · ")
        return target.isEmpty ? link.relation.shortTitle : "\(link.relation.shortTitle): \(target)"
    }
}
