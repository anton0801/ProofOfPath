//
//  WorkspaceEvidenceSection.swift
//  ProofOfPath
//
//  Evidence and Claim Check inside a decision.
//

import SwiftUI

struct WorkspaceEvidenceSection: View {
    @EnvironmentObject private var store: AppStore
    let decisionID: UUID

    @State private var tab: EvidenceTab = .evidence
    @State private var showEvidenceEditor = false
    @State private var showClaimEditor = false
    @State private var openClaim: Claim?
    @State private var route: AppRoute?

    enum EvidenceTab: String, CaseIterable, Identifiable, Hashable {
        case evidence
        case claims

        var id: String { rawValue }
        var title: String { self == .evidence ? "Evidence" : "Claim Check" }
        var icon: String { self == .evidence ? "paperclip" : "quote.bubble" }
    }

    private var decision: Decision? { store.state.decision(id: decisionID) }
    private var items: [Evidence] { store.state.evidence(forDecision: decisionID) }

    var body: some View {
        if let decision {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                WorkspaceSectionIntro(
                    title: "Evidence",
                    subtitle: "Material you collected, and the claims you still need to check.",
                    icon: "paperclip"
                )

                HStack(spacing: 8) {
                    ForEach(EvidenceTab.allCases) { item in
                        POPChip(
                            title: item.title,
                            count: item == .evidence ? items.count : decision.claims.count,
                            icon: item.icon,
                            isSelected: tab == item
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) { tab = item }
                        }
                    }
                    Spacer()
                }

                if tab == .evidence {
                    evidenceTab(decision)
                } else {
                    claimsTab(decision)
                }
            }
            .sheet(isPresented: $showEvidenceEditor) {
                EvidenceEditorSheet(existing: nil, presetDecisionID: decisionID)
            }
            .sheet(isPresented: $showClaimEditor) {
                ClaimEditorSheet(decisionID: decisionID, existing: nil)
            }
            .sheet(item: $openClaim) { claim in
                ClaimDetailSheet(decisionID: decisionID, claimID: claim.id)
            }
            .popNavigationDestination(item: $route) { destination in
                if case .evidenceDetail(let id) = destination {
                    EvidenceDetailView(evidenceID: id)
                }
            }
        }
    }

    // MARK: Evidence

    private func evidenceTab(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if items.isEmpty {
                POPEmptyState(
                    icon: "tray",
                    title: "No evidence yet",
                    message: "Every rating without evidence is an opinion. Attach links, photos, documents, quotes or your own notes.",
                    actionTitle: "Add Evidence",
                    action: { showEvidenceEditor = true }
                )
                .popCard(padding: 6)
            } else {
                coverageCard(decision)

                ForEach(items) { item in
                    Button(action: {
                        Haptics.tap()
                        route = .evidenceDetail(item.id)
                    }) {
                        EvidenceRow(evidence: item, decision: decision, showsLinks: true)
                    }
                    .buttonStyle(POPPressStyle())
                }

                POPPrimaryButton(title: "Add Evidence", icon: "plus") {
                    showEvidenceEditor = true
                }
                .popRequiresConnection()
            }
        }
    }

    private func coverageCard(_ decision: Decision) -> some View {
        let scoreboard = store.scoreboard(for: decision)
        let coverage = scoreboard.scores.isEmpty
            ? 0
            : scoreboard.scores.map(\.evidenceCoverage).reduce(0, +) / Double(scoreboard.scores.count)
        let unlinked = items.filter { $0.links.isEmpty }.count

        return VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Evidence Coverage", subtitle: "Share of ratings backed by at least one supporting item.", icon: "chart.bar")
            HStack(spacing: 12) {
                Text("\(Int((coverage * 100).rounded()))%")
                    .font(POPFont.numericLarge)
                    .foregroundStyle(coverage >= 0.5 ? POPColor.success : POPColor.brandOrange)
                POPMeter(value: coverage, tint: coverage >= 0.5 ? POPColor.success : POPColor.brandOrange)
            }
            if unlinked > 0 {
                POPInlineNote(
                    text: "\(unlinked) \(unlinked == 1 ? "item is" : "items are") not linked to any option or criterion, so \(unlinked == 1 ? "it does" : "they do") not affect coverage.",
                    icon: "link.badge.plus",
                    tint: POPColor.brandOrange
                )
            }
        }
        .popCard()
    }

    // MARK: Claims

    private func claimsTab(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if decision.claims.isEmpty {
                POPEmptyState(
                    icon: "quote.bubble",
                    title: "No claims recorded",
                    message: "Write down what a seller promised, what an advert states, or what you are assuming. Then check it against evidence.",
                    actionTitle: "Add Claim",
                    action: { showClaimEditor = true }
                )
                .popCard(padding: 6)
            } else {
                claimStats(decision)

                ForEach(decision.claims.sorted { lhs, rhs in
                    if lhs.status.isOpen != rhs.status.isOpen { return lhs.status.isOpen }
                    return lhs.createdAt > rhs.createdAt
                }) { claim in
                    ClaimRow(claim: claim, decision: decision) { openClaim = claim }
                }

                POPPrimaryButton(title: "Add Claim", icon: "plus") {
                    showClaimEditor = true
                }
                .popRequiresConnection()
            }
        }
    }

    private func claimStats(_ decision: Decision) -> some View {
        HStack(spacing: 10) {
            POPStatTile(value: "\(decision.claims.filter { $0.status == .verified }.count)",
                        label: "Verified", icon: "checkmark.seal.fill", tint: POPColor.success)
            POPStatTile(value: "\(decision.openClaims.count)",
                        label: "Still open", icon: "questionmark.diamond",
                        tint: decision.openClaims.isEmpty ? POPColor.graphite : POPColor.brandOrange)
            POPStatTile(value: "\(decision.claims.filter { $0.status == .contradicted }.count)",
                        label: "Contradicted", icon: "xmark.seal", tint: POPColor.danger)
        }
    }
}

// MARK: - Claim row

struct ClaimRow: View {
    let claim: Claim
    let decision: Decision
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: claim.status.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(claim.status.color)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(claim.status.softColor))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(claim.displayText)
                            .font(POPFont.calloutMedium)
                            .foregroundStyle(POPColor.ink)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        if !claim.claimedBy.popIsBlank {
                            Text("Claimed by \(claim.claimedBy)")
                                .font(POPFont.caption)
                                .foregroundStyle(POPColor.inkSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(POPColor.inkTertiary)
                }

                HStack(spacing: 6) {
                    POPBadge(text: claim.status.title, color: claim.status.color, soft: claim.status.softColor, compact: true)
                    if let option = decision.option(id: claim.optionID) {
                        POPBadge(text: option.displayName.popTruncated(20), icon: "square.stack", compact: true)
                    }
                    if !claim.supportingEvidenceIDs.isEmpty {
                        POPBadge(text: "\(claim.supportingEvidenceIDs.count) supporting", icon: "checkmark.circle.fill",
                                 color: POPColor.success, soft: POPColor.successSoft, compact: true)
                    }
                    if !claim.contradictingEvidenceIDs.isEmpty {
                        POPBadge(text: "\(claim.contradictingEvidenceIDs.count) contradicting", icon: "xmark.circle.fill",
                                 color: POPColor.danger, soft: POPColor.dangerSoft, compact: true)
                    }
                    Spacer(minLength: 0)
                }

                if let deadline = claim.verificationDeadline, claim.status.isOpen {
                    HStack(spacing: 5) {
                        Image(systemName: "clock.badge.exclamationmark").font(.system(size: 10, weight: .bold))
                        Text("Verify by \(POPFormat.date(deadline)) · \(POPFormat.relativeDeadline(deadline))")
                            .font(POPFont.caption)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(POPFormat.daysUntil(deadline) < 0 ? POPColor.danger : POPColor.brandOrange)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(claim.status == .contradicted ? POPColor.danger.opacity(0.4) : POPColor.hairline,
                              lineWidth: claim.status == .contradicted ? 1.4 : 1))
        }
        .buttonStyle(POPPressStyle())
    }
}
