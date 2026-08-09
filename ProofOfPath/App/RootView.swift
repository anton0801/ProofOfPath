//
//  RootView.swift
//  ProofOfPath
//

import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            POPColor.canvas.ignoresSafeArea()

            if store.state.settings.onboardingCompleted {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.state.settings.onboardingCompleted)
        .popToast(store.state.toast) { store.dismissToast() }
        .task {
            await ReminderService.shared.refreshAuthorizationStatus()
            store.pruneOrphanAttachments()
            // A shared backup or summary left in the temp folder is a full copy
            // of the user's data — clear anything from a previous session.
            store.purgeTemporaryExports()
        }
    }
}

// MARK: - Main tabs

enum MainTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case decisions
    case evidence
    case insights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .decisions: return "Decisions"
        case .evidence: return "Evidence"
        case .insights: return "Insights"
        }
    }

    var icon: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .decisions: return "checklist"
        case .evidence: return "paperclip"
        case .insights: return "chart.line.uptrend.xyaxis"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .decisions: return "checklist.checked"
        case .evidence: return "paperclip.circle.fill"
        case .insights: return "chart.line.uptrend.xyaxis"
        }
    }
}

struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: MainTab = .home
    @State private var homePath = NavigationPath()
    @State private var decisionsPath = NavigationPath()
    @State private var evidencePath = NavigationPath()
    @State private var insightsPath = NavigationPath()

    var body: some View {
        ZStack(alignment: .bottom) {
            // The inset lives on the stack, not on individual screens, so every
            // pushed screen keeps clear of the custom tab bar too.
            Group {
                switch selection {
                case .home:
                    NavigationStack(path: $homePath) {
                        HomeView()
                            .withAppDestinations()
                    }
                    .popTabBarInset()
                case .decisions:
                    NavigationStack(path: $decisionsPath) {
                        DecisionsListView()
                            .withAppDestinations()
                    }
                    .popTabBarInset()
                case .evidence:
                    NavigationStack(path: $evidencePath) {
                        EvidenceInboxView()
                            .withAppDestinations()
                    }
                    .popTabBarInset()
                case .insights:
                    NavigationStack(path: $insightsPath) {
                        InsightsView()
                            .withAppDestinations()
                    }
                    .popTabBarInset()
                }
            }

            POPTabBar(selection: $selection) { tab in
                // Tapping the active tab pops its stack to the root.
                switch tab {
                case .home: homePath = NavigationPath()
                case .decisions: decisionsPath = NavigationPath()
                case .evidence: evidencePath = NavigationPath()
                case .insights: insightsPath = NavigationPath()
                }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

// MARK: - Tab bar

struct POPTabBar: View {
    @Binding var selection: MainTab
    var onReselect: (MainTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                let isSelected = tab == selection
                Button(action: {
                    Haptics.selection()
                    if isSelected {
                        onReselect(tab)
                    } else {
                        selection = tab
                    }
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                            .frame(height: 22)
                        Text(tab.title)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                    }
                    .foregroundStyle(isSelected ? POPColor.graphite : POPColor.inkTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 9)
                    .padding(.bottom, 5)
                    .contentShape(Rectangle())
                    .overlay(alignment: .top) {
                        if isSelected {
                            Capsule()
                                .fill(POPColor.brandYellow)
                                .frame(width: 26, height: 3)
                                .offset(y: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tab.title))
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.bottom, 2)
        .background(
            POPColor.surface
                .overlay(alignment: .top) {
                    Rectangle().fill(POPColor.hairline).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - Navigation destinations

enum AppRoute: Hashable {
    case decision(UUID)
    case decisionSection(UUID, WorkspaceSection)
    case optionDetail(decisionID: UUID, optionID: UUID)
    case evidenceDetail(UUID)
    case openQuestions(UUID)
    case comparisonMatrix(UUID)
    case scenarioLab(UUID)
    case costView(UUID)
    case readiness(UUID)
    case finalize(UUID)
    case summary(UUID)
    case outcomeReview(UUID)
    case history(UUID)
    case snapshot(decisionID: UUID, snapshotID: UUID)
    case settings
    case archived
    case templates
    case criteriaWorkshop(UUID)
}

struct AppDestinationsModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .decision(let id):
                DecisionWorkspaceView(decisionID: id, initialSection: .brief)
            case .decisionSection(let id, let section):
                DecisionWorkspaceView(decisionID: id, initialSection: section)
            case .optionDetail(let decisionID, let optionID):
                OptionDetailView(decisionID: decisionID, optionID: optionID)
            case .evidenceDetail(let id):
                EvidenceDetailView(evidenceID: id)
            case .openQuestions(let id):
                OpenQuestionsView(decisionID: id)
            case .comparisonMatrix(let id):
                ComparisonMatrixView(decisionID: id)
            case .scenarioLab(let id):
                ScenarioLabView(decisionID: id)
            case .costView(let id):
                CostView(decisionID: id)
            case .readiness(let id):
                DecisionReadinessView(decisionID: id)
            case .finalize(let id):
                FinalizeDecisionView(decisionID: id)
            case .summary(let id):
                DecisionSummaryView(decisionID: id)
            case .outcomeReview(let id):
                OutcomeReviewView(decisionID: id)
            case .history(let id):
                DecisionHistoryView(decisionID: id)
            case .snapshot(let decisionID, let snapshotID):
                SnapshotView(decisionID: decisionID, snapshotID: snapshotID)
            case .settings:
                SettingsView()
            case .archived:
                ArchivedDecisionsView()
            case .templates:
                TemplatesView()
            case .criteriaWorkshop(let id):
                DecisionWorkspaceView(decisionID: id, initialSection: .criteria)
            }
        }
    }
}

extension View {
    func withAppDestinations() -> some View {
        modifier(AppDestinationsModifier())
    }

    /// Leaves room for the custom tab bar at the bottom of every scroll view.
    func popTabBarInset() -> some View {
        safeAreaInset(edge: .bottom) { Color.clear.frame(height: 64) }
    }
}
