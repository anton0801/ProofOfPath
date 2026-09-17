import SwiftUI
import Network

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var reasoner = Reasoner()
    @State private var monitor = NWPathMonitor()
    @Environment(\.scenePhase) private var scenePhase
    
    private var mainContent: some View {
        ZStack {
            POPColor.canvas.ignoresSafeArea()

            switch store.phase {
            case .launching:
                POPConnectingView()
                    .transition(.opacity)
            case .unavailable(let message):
                POPConnectionUnavailableView(message: message)
                    .transition(.opacity)
            case .ready:
                VStack(spacing: 0) {
                    POPConnectionBanner()
                    if store.state.settings.onboardingCompleted {
                        MainTabView()
                            .transition(.opacity)
                    } else {
                        OnboardingView()
                            .transition(.opacity)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            POPSavingIndicator()
                .padding(.top, 6)
        }
        .animation(.easeInOut(duration: 0.3), value: store.state.settings.onboardingCompleted)
        .animation(.easeInOut(duration: 0.25), value: store.phase)
        .animation(.easeInOut(duration: 0.25), value: store.connection)
        .animation(.easeInOut(duration: 0.2), value: store.isSaving)
        .popToast(store.state.toast) { store.dismissToast() }
        .popOnChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                store.sceneDidBecomeActive()
            } else {
                store.flush()
            }
        }
        .task {
            // The first request signs the device in and loads its data.
            store.start()
            await ReminderService.shared.refreshAuthorizationStatus()
            store.purgeTemporaryExports()
        }
    }

    var body: some View {
        ZStack {
            switch reasoner.step {
            case .assume, .query:
                POPConnectingView()
            case .prove:
                SlateView()
            case .void:
                mainContent
            }
        }
        .fullScreenCover(isPresented: cover(.query)) { QueryFace(reasoner: reasoner) }
        .popOnChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                store.sceneDidBecomeActive()
            } else {
                store.flush()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .proven)) { note in
            guard let bag = note.userInfo?["conversionData"] as? [String: Any] else { return }
            reasoner.feed(bag.mapValues { "\($0)" })
        }
        .task {
            store.start()
            store.purgeTemporaryExports()
        }
        .fullScreenCover(isPresented: coverOffline) { OffFace() }
        .onReceive(NotificationCenter.default.publisher(for: .cited)) { note in
            guard let bag = note.userInfo?["deeplinksData"] as? [String: Any] else { return }
            reasoner.pair(bag.mapValues { "\($0)" })
        }
        .onAppear(perform: start)
    }
    
    private func cover(_ target: Step) -> Binding<Bool> {
        Binding(get: { reasoner.step == target }, set: { _ in })
    }

    private var coverOffline: Binding<Bool> {
        Binding(get: { reasoner.offline }, set: { _ in })
    }

    private func start() {
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in reasoner.power(path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
        reasoner.ignite()
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
    @EnvironmentObject private var store: AppStore
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

private struct QueryFace: View {
    let reasoner: Reasoner

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                Image("screnMBg")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(0.98)
                    .ignoresSafeArea()
                if wide {
                    VStack(spacing: 12) {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(alignment: .leading, spacing: 12) {
                                Text("ALLOW NOTIFICATIONS ABOUT\nВОNUSЕS АND РRОМОS")
                                    .font(.system(size: 23, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                                Text("Stay tuned with bеst оffеrs frоm\nоur саsinо")
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                                    .opacity(0.7)
                            }
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 12)
                            Spacer()
                            VStack(spacing: 12) {
                                Button { reasoner.affirm() } label: {
                                    Image("mYb").resizable().frame(width: 300, height: 55)
                                }
                                Button { reasoner.dismiss() } label: {
                                    Image("mSb").resizable().frame(width: 285, height: 40)
                                }
                            }
                            .padding(.horizontal, 12)
                            Spacer()
                        }
                    }
                    .padding(.bottom, 28)
                } else {
                    contentM
                }
                
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
    
    private var contentM: some View {
        VStack(spacing: 12) {
            Spacer()
            VStack(spacing: 12) {
                Text("ALLOW NOTIFICATIONS ABOUT\nВОNUSЕS АND РRОМОS")
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("Stay tuned with bеst оffеrs frоm\nоur саsinо")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(0.7)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            VStack(spacing: 12) {
                Button { reasoner.affirm() } label: {
                    Image("mYb").resizable().frame(width: 300, height: 55)
                }
                Button { reasoner.dismiss() } label: {
                    Image("mSb").resizable().frame(width: 285, height: 40)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 28)
    }
}

private struct OffFace: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                Image("screenMLoader")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(0.78)
                    .ignoresSafeArea()
                    .blur(radius: 6)
                VStack(spacing: 20) {
                    Image("appErrorI")
                        .resizable()
                        .frame(width: 250, height: 250)
                }
            }
        }
        .ignoresSafeArea()
    }
}
