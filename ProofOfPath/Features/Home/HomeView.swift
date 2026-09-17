//
//  HomeView.swift
//  ProofOfPath
//
//  Decision Command Center — real state, not decorative statistics.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showCreate = false
    @State private var selectedBucket: HomeBucket = .active
    @State private var route: AppRoute?
    @State private var createdDecisionID: UUID?

    var body: some View {
        let bucketMap = store.state.allBuckets()
        let currentDecisions = bucketMap[selectedBucket] ?? []

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                header(reviewDueCount: bucketMap[.reviewDue]?.count ?? 0)

                if store.state.decisions.isEmpty {
                    emptyState
                } else {
                    if let notice = store.state.constraintRecheckNotice {
                        POPBanner(
                            kind: .warning,
                            message: notice,
                            detail: "Open the decision to see which options are affected.",
                            onDismiss: { store.dismissConstraintNotice() }
                        )
                    }

                    bucketStrip(bucketMap)
                    decisionList(currentDecisions)
                }
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 6)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Text("ProofPath")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(POPColor.ink)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(value: AppRoute.settings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(POPColor.graphite)
                }
                .accessibilityLabel(Text("Settings"))
            }
        }
        .sheet(isPresented: $showCreate, onDismiss: {
            // "Create Workspace" should land the user in the workspace, not back
            // on the list. Navigating after the sheet closes keeps the animation
            // clean.
            if let created = createdDecisionID {
                createdDecisionID = nil
                route = .decisionSection(created, .brief)
            }
        }) {
            CreateDecisionFlow(onCreated: { createdDecisionID = $0 })
        }
        .popNavigationDestination(item: $route) { destination in
            destinationView(destination)
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: AppRoute) -> some View {
        switch destination {
        case .decisionSection(let id, let section):
            DecisionWorkspaceView(decisionID: id, initialSection: section)
        case .decision(let id):
            DecisionWorkspaceView(decisionID: id, initialSection: .brief)
        default:
            EmptyView()
        }
    }

    // MARK: Header

    private func header(reviewDueCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            POPScreenHeader(
                title: "Decision\nCommand Center",
                subtitle: store.state.decisions.isEmpty
                    ? nil
                    : summaryLine(reviewDueCount: reviewDueCount)
            )

            if !store.state.decisions.isEmpty {
                POPPrimaryButton(title: "Create Decision", icon: "plus") {
                    showCreate = true
                }
                .popRequiresConnection()
                .accessibilityIdentifier("home.createDecision")
            }
        }
    }

    private func summaryLine(reviewDueCount: Int) -> String {
        let active = store.state.activeDecisions.count
        var parts = ["\(active) in progress"]
        if reviewDueCount > 0 { parts.append("\(reviewDueCount) awaiting review") }
        return parts.joined(separator: " · ")
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 18) {
            EmptyBoardArtwork()
                .frame(height: 150)

            VStack(spacing: 8) {
                Text("Turn a Difficult Choice into a Clear Process")
                    .font(POPFont.display(24))
                    .foregroundStyle(POPColor.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Define what matters, compare real evidence, and record why you made the final choice.")
                    .font(POPFont.body)
                    .foregroundStyle(POPColor.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6)

            VStack(spacing: 10) {
                POPPrimaryButton(title: "Create Your First Decision", icon: "plus") {
                    showCreate = true
                }
                .popRequiresConnection()
                .accessibilityIdentifier("home.createFirstDecision")
                NavigationLink(value: AppRoute.templates) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2").font(.system(size: 13, weight: .semibold))
                        Text("Browse starting structures").font(POPFont.calloutMedium)
                    }
                    .foregroundStyle(POPColor.brandOrange)
                    .frame(height: 34)
                }
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: Bucket strip

    private func bucketStrip(_ bucketMap: [HomeBucket: [Decision]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HomeBucket.allCases) { bucket in
                    POPChip(
                        title: bucket.title,
                        count: bucketMap[bucket]?.count ?? 0,
                        icon: bucket.icon,
                        isSelected: selectedBucket == bucket
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedBucket = bucket }
                    }
                }
            }
            .padding(.horizontal, 1)
        }
        .popScrollClipDisabled()
    }

    // MARK: Decision list

    private func decisionList(_ currentDecisions: [Decision]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: selectedBucket.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(selectedBucket.color)
                Text(selectedBucket.title)
                    .font(POPFont.sectionTitle)
                    .foregroundStyle(POPColor.ink)
                Spacer()
                Text("\(currentDecisions.count)")
                    .font(POPFont.captionMedium)
                    .foregroundStyle(POPColor.inkSecondary)
            }

            if currentDecisions.isEmpty {
                POPEmptyState(
                    icon: selectedBucket.icon,
                    title: "Nothing here",
                    message: selectedBucket.emptyMessage,
                    compact: true
                )
                .popCard(padding: 4, background: POPColor.surface)
            } else {
                ForEach(currentDecisions) { decision in
                    DecisionCard(decision: decision) { section in
                        route = .decisionSection(decision.id, section)
                    }
                }
            }
        }
    }
}

// MARK: - Empty board artwork

struct EmptyBoardArtwork: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(POPColor.surfaceSunk)

            // Empty pinned cards with a dotted thread — the board before evidence.
            ZStack {
                card(width: 84, height: 54, rotation: -6)
                    .offset(x: -74, y: -22)
                card(width: 74, height: 48, rotation: 6)
                    .offset(x: 66, y: -30)
                card(width: 92, height: 50, rotation: -2)
                    .offset(x: 4, y: 38)

                Image(systemName: "questionmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(POPColor.brandOrange.opacity(0.7))
                    .offset(x: 4, y: 38)
            }
        }
    }

    private func card(width: CGFloat, height: CGFloat, rotation: Double) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(POPColor.surface)
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(POPColor.graphite.opacity(0.14), style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
            )
            .overlay(alignment: .top) {
                Circle()
                    .fill(POPColor.brandYellow)
                    .frame(width: 8, height: 8)
                    .offset(y: -3)
            }
            .rotationEffect(.degrees(rotation))
    }
}
