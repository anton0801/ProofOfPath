//
//  DecisionsListView.swift
//  ProofOfPath
//

import SwiftUI

enum DecisionFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case active
    case draft
    case paused
    case finalized

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .active: return "Active"
        case .draft: return "Drafts"
        case .paused: return "Paused"
        case .finalized: return "Finalized"
        }
    }

    func matches(_ decision: Decision) -> Bool {
        switch self {
        case .all: return true
        case .active: return decision.status == .active
        case .draft: return decision.status == .draft
        case .paused: return decision.status == .paused
        case .finalized: return decision.status == .finalized
        }
    }
}

enum DecisionSort: String, CaseIterable, Identifiable, Hashable {
    case recentlyUpdated
    case deadline
    case title
    case progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyUpdated: return "Recently updated"
        case .deadline: return "Nearest deadline"
        case .title: return "Title A–Z"
        case .progress: return "Least complete first"
        }
    }
}

struct DecisionsListView: View {
    @Environment(AppStore.self) private var store

    @State private var search = ""
    @State private var filter: DecisionFilter = .all
    @State private var sort: DecisionSort = .recentlyUpdated
    @State private var categoryFilter: DecisionCategory?
    @State private var showCreate = false
    @State private var route: AppRoute?
    @State private var createdDecisionID: UUID?

    private var visible: [Decision] {
        var result = store.state.decisions.filter { $0.status != .archived }

        if !search.popIsBlank {
            let needle = search.popNormalizedForCompare
            result = result.filter { decision in
                decision.title.popNormalizedForCompare.contains(needle)
                    || decision.desiredOutcome.popNormalizedForCompare.contains(needle)
                    || decision.categoryTitle.popNormalizedForCompare.contains(needle)
                    || decision.options.contains { $0.name.popNormalizedForCompare.contains(needle) }
            }
        }
        result = result.filter { filter.matches($0) }
        if let categoryFilter {
            result = result.filter { $0.category == categoryFilter }
        }

        switch sort {
        case .recentlyUpdated:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .deadline:
            result.sort { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
        case .title:
            result.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .progress:
            result.sort { store.progress(for: $0).fraction < store.progress(for: $1).fraction }
        }
        return result
    }

    private var usedCategories: [DecisionCategory] {
        let present = Set(store.state.decisions.filter { $0.status != .archived }.map(\.category))
        return DecisionCategory.allCases.filter { present.contains($0) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                POPScreenHeader(
                    title: "Decisions",
                    subtitle: store.state.decisions.isEmpty
                        ? nil
                        : "\(store.state.decisions.filter { $0.status != .archived }.count) in your workspace"
                )

                if store.state.decisions.filter({ $0.status != .archived }).isEmpty {
                    POPEmptyState(
                        icon: "checklist",
                        title: store.state.decisions.isEmpty ? "No decisions yet" : "Everything is archived",
                        message: store.state.decisions.isEmpty
                            ? "Create a decision to start collecting criteria, options and evidence in one place."
                            : "Your decisions are in the archive. Restore one from Settings → Archived Decisions.",
                        actionTitle: store.state.decisions.isEmpty ? "Create Decision" : nil,
                        action: store.state.decisions.isEmpty ? { showCreate = true } : nil
                    )
                } else {
                    POPSearchField(text: $search, placeholder: "Search decisions and options")

                    filterBar

                    if visible.isEmpty {
                        POPEmptyState(
                            icon: "magnifyingglass",
                            title: "No matches",
                            message: "Try a different search term or clear the filters.",
                            actionTitle: "Clear filters",
                            action: {
                                search = ""
                                filter = .all
                                categoryFilter = nil
                            },
                            compact: true
                        )
                        .popCard(padding: 4)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(visible) { decision in
                                DecisionCard(decision: decision) { section in
                                    route = .decisionSection(decision.id, section)
                                }
                                .contextMenu {
                                    decisionContextMenu(decision)
                                }
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
                        ForEach(DecisionSort.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Divider()
                    NavigationLink(value: AppRoute.archived) {
                        Label("Archived Decisions", systemImage: "archivebox")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(POPColor.graphite)
                }
                .accessibilityLabel(Text("Sort and archive"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    Haptics.tap()
                    showCreate = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(POPColor.graphite)
                }
                .accessibilityLabel(Text("Create decision"))
            }
        }
        .sheet(isPresented: $showCreate, onDismiss: {
            if let created = createdDecisionID {
                createdDecisionID = nil
                route = .decisionSection(created, .brief)
            }
        }) {
            CreateDecisionFlow(onCreated: { createdDecisionID = $0 })
        }
        .navigationDestination(item: $route) { destination in
            if case .decisionSection(let id, let section) = destination {
                DecisionWorkspaceView(decisionID: id, initialSection: section)
            }
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DecisionFilter.allCases) { option in
                        let count = store.state.decisions.filter { $0.status != .archived && option.matches($0) }.count
                        POPChip(title: option.title, count: count, isSelected: filter == option) {
                            filter = option
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollClipDisabled()

            if usedCategories.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        POPChip(title: "All categories", isSelected: categoryFilter == nil) {
                            categoryFilter = nil
                        }
                        ForEach(usedCategories) { category in
                            POPChip(
                                title: category.title,
                                icon: category.icon,
                                isSelected: categoryFilter == category
                            ) {
                                categoryFilter = categoryFilter == category ? nil : category
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .scrollClipDisabled()
            }
        }
    }

    @ViewBuilder
    private func decisionContextMenu(_ decision: Decision) -> some View {
        if decision.status == .active {
            Button {
                store.send(.setDecisionStatus(decisionID: decision.id, status: .paused))
            } label: {
                Label("Pause Decision", systemImage: "pause.circle")
            }
        }
        if decision.status == .paused || decision.status == .draft {
            Button {
                store.send(.setDecisionStatus(decisionID: decision.id, status: .active))
            } label: {
                Label("Resume Decision", systemImage: "play.circle")
            }
        }
        Button {
            store.send(.archiveDecision(decision.id))
        } label: {
            Label("Archive Decision", systemImage: "archivebox")
        }
    }
}

// MARK: - Archived

struct ArchivedDecisionsView: View {
    @Environment(AppStore.self) private var store
    @State private var pendingDelete: Decision?
    @State private var route: AppRoute?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                if store.state.archivedDecisions.isEmpty {
                    POPEmptyState(
                        icon: "archivebox",
                        title: "Nothing archived",
                        message: "Archived decisions stay out of your active lists but keep all their data."
                    )
                } else {
                    POPInlineNote(text: "Archived decisions keep every criterion, option, evidence item and scenario. Restoring puts a decision back where it was.")

                    ForEach(store.state.archivedDecisions) { decision in
                        VStack(alignment: .leading, spacing: 10) {
                            DecisionCompactRow(
                                decision: decision,
                                trailingText: "Archived · \(POPFormat.relativeTimestamp(decision.updatedAt))"
                            ) {
                                route = .decision(decision.id)
                            }
                            HStack(spacing: 10) {
                                POPPillButton(title: "Restore", icon: "arrow.uturn.backward", filled: true) {
                                    store.send(.restoreDecision(decision.id))
                                }
                                POPPillButton(title: "Delete", icon: "trash", tint: POPColor.danger) {
                                    pendingDelete = decision
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 8)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationTitle("Archived Decisions")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { destination in
            if case .decision(let id) = destination {
                DecisionWorkspaceView(decisionID: id, initialSection: .brief)
            }
        }
        .deleteDecisionAlert(decision: $pendingDelete, evidenceCount: { decision in
            store.state.evidence(forDecision: decision.id).count
        }) { decision in
            store.send(.deleteDecision(decision.id))
        }
    }
}

// MARK: - Shared delete confirmation

struct DeleteDecisionAlert: ViewModifier {
    @Binding var decision: Decision?
    let evidenceCount: (Decision) -> Int
    let onConfirm: (Decision) -> Void

    func body(content: Content) -> some View {
        content.alert(
            "Delete this decision?",
            isPresented: Binding(get: { decision != nil }, set: { if !$0 { decision = nil } }),
            presenting: decision
        ) { target in
            Button("Cancel", role: .cancel) { decision = nil }
            Button("Delete permanently", role: .destructive) {
                onConfirm(target)
                decision = nil
            }
        } message: { target in
            Text(deleteMessage(for: target))
        }
    }

    private func deleteMessage(for target: Decision) -> String {
        var parts: [String] = []
        parts.append("\(target.options.count) \(target.options.count == 1 ? "option" : "options")")
        parts.append("\(evidenceCount(target)) evidence \(evidenceCount(target) == 1 ? "item" : "items")")
        parts.append("\(target.scenarios.count) \(target.scenarios.count == 1 ? "scenario" : "scenarios")")
        if !target.risks.isEmpty { parts.append("\(target.risks.count) \(target.risks.count == 1 ? "risk" : "risks")") }
        if !target.claims.isEmpty { parts.append("\(target.claims.count) \(target.claims.count == 1 ? "claim" : "claims")") }
        return "“\(target.displayTitle)” will be removed together with \(parts.joined(separator: ", ")). This cannot be undone."
    }
}

extension View {
    func deleteDecisionAlert(
        decision: Binding<Decision?>,
        evidenceCount: @escaping (Decision) -> Int,
        onConfirm: @escaping (Decision) -> Void
    ) -> some View {
        modifier(DeleteDecisionAlert(decision: decision, evidenceCount: evidenceCount, onConfirm: onConfirm))
    }
}
