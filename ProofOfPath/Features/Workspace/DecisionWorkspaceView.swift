//
//  DecisionWorkspaceView.swift
//  ProofOfPath
//
//  The project shell: Brief · Criteria · Options · Evidence · Compare · Risks · Decision
//

import SwiftUI

struct DecisionWorkspaceView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID
    var initialSection: WorkspaceSection = .brief

    @State private var section: WorkspaceSection = .brief
    @State private var didSetInitial = false
    @State private var pendingDelete: Decision?

    private var decision: Decision? { store.state.decision(id: decisionID) }

    var body: some View {
        Group {
            if let decision {
                content(decision)
            } else {
                POPEmptyState(
                    icon: "questionmark.folder",
                    title: "Decision not found",
                    message: "This decision was deleted. Go back to the list to pick another one.",
                    actionTitle: "Back",
                    action: { dismiss() }
                )
                .background(POPColor.canvas.ignoresSafeArea())
            }
        }
        .onAppear {
            if !didSetInitial {
                section = initialSection
                didSetInitial = true
            }
        }
    }

    private func content(_ decision: Decision) -> some View {
        VStack(spacing: 0) {
            WorkspaceSectionBar(selection: $section, decision: decision, store: store)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                    if let notice = store.state.constraintRecheckNotice {
                        POPBanner(
                            kind: .warning,
                            message: notice,
                            detail: "Options that break a hard constraint cannot become the leader.",
                            actionTitle: "Show options",
                            action: { section = .options },
                            onDismiss: { store.dismissConstraintNotice() }
                        )
                    }

                    if decision.status == .paused {
                        POPBanner(
                            kind: .neutral,
                            message: "This decision is paused.",
                            detail: "You can still edit everything. Resume it to see it in your active list.",
                            actionTitle: "Resume",
                            action: { store.send(.setDecisionStatus(decisionID: decision.id, status: .active)) }
                        )
                    }

                    if decision.status == .archived {
                        POPBanner(
                            kind: .neutral,
                            message: "This decision is archived.",
                            detail: "Restore it to bring it back into your active lists.",
                            actionTitle: "Restore",
                            action: { store.send(.restoreDecision(decision.id)) }
                        )
                    }

                    switch section {
                    case .brief:    BriefSection(decisionID: decisionID)
                    case .criteria: CriteriaSection(decisionID: decisionID)
                    case .options:  OptionsSection(decisionID: decisionID)
                    case .evidence: WorkspaceEvidenceSection(decisionID: decisionID)
                    case .compare:  CompareSection(decisionID: decisionID)
                    case .risks:    RisksSection(decisionID: decisionID)
                    case .decision: DecisionSection(decisionID: decisionID)
                    }

                    Color.clear.frame(height: 16)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 12)
            }
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationTitle(decision.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink(value: AppRoute.openQuestions(decisionID)) {
                        Label("Open Questions", systemImage: "questionmark.circle")
                    }
                    NavigationLink(value: AppRoute.history(decisionID)) {
                        Label("History and Versions", systemImage: "clock.arrow.circlepath")
                    }
                    NavigationLink(value: AppRoute.costView(decisionID)) {
                        Label("Total Cost View", systemImage: "banknote")
                    }
                    Divider()
                    if decision.status == .active {
                        Button {
                            store.send(.setDecisionStatus(decisionID: decisionID, status: .paused))
                        } label: {
                            Label("Pause Decision", systemImage: "pause.circle")
                        }
                    }
                    if decision.status == .paused || decision.status == .draft {
                        Button {
                            store.send(.setDecisionStatus(decisionID: decisionID, status: .active))
                        } label: {
                            Label("Resume Decision", systemImage: "play.circle")
                        }
                    }
                    if decision.status == .archived {
                        Button {
                            store.send(.restoreDecision(decisionID))
                        } label: {
                            Label("Restore from Archive", systemImage: "arrow.uturn.backward")
                        }
                    } else {
                        Button {
                            store.send(.archiveDecision(decisionID))
                        } label: {
                            Label("Archive Decision", systemImage: "archivebox")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        pendingDelete = decision
                    } label: {
                        Label("Delete Decision", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(POPColor.graphite)
                }
                .accessibilityLabel(Text("Decision actions"))
            }
        }
        .deleteDecisionAlert(decision: $pendingDelete, evidenceCount: { target in
            store.state.evidence(forDecision: target.id).count
        }) { target in
            store.send(.deleteDecision(target.id))
            dismiss()
        }
    }
}

// MARK: - Section bar

struct WorkspaceSectionBar: View {
    @Binding var selection: WorkspaceSection
    let decision: Decision
    let store: AppStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(WorkspaceSection.allCases) { item in
                        POPChip(
                            title: item.title,
                            count: badgeCount(for: item),
                            icon: item.icon,
                            isSelected: selection == item
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) { selection = item }
                        }
                        .id(item)
                    }
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.vertical, 9)
            }
            .onChange(of: selection) { _, newValue in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(selection, anchor: .center)
            }
        }
        .background(
            POPColor.surface
                .overlay(alignment: .bottom) { Rectangle().fill(POPColor.hairline).frame(height: 1) }
        )
    }

    private func badgeCount(for item: WorkspaceSection) -> Int? {
        switch item {
        case .criteria: return decision.criteria.isEmpty ? nil : decision.criteria.count
        case .options: return decision.options.isEmpty ? nil : decision.options.count
        case .evidence:
            let count = store.state.evidence(forDecision: decision.id).count
            return count == 0 ? nil : count
        case .risks: return decision.risks.isEmpty ? nil : decision.risks.count
        default: return nil
        }
    }
}

// MARK: - Reusable section title

struct WorkspaceSectionIntro: View {
    let title: String
    let subtitle: String
    var icon: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(POPColor.brandOrange)
                }
                Text(title)
                    .font(POPFont.display(23))
                    .foregroundStyle(POPColor.ink)
            }
            Text(subtitle)
                .font(POPFont.callout)
                .foregroundStyle(POPColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
