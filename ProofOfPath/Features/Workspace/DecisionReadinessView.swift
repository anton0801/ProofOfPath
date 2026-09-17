//
//  DecisionReadinessView.swift
//  ProofOfPath
//

import SwiftUI

struct DecisionReadinessView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID

    @State private var route: AppRoute?

    private var decision: Decision? { store.state.decision(id: decisionID) }

    var body: some View {
        Group {
            if let decision {
                content(decision)
            } else {
                POPEmptyState(icon: "questionmark.folder", title: "Decision not found",
                              message: "This decision was deleted.", actionTitle: "Back", action: { dismiss() })
                    .background(POPColor.canvas.ignoresSafeArea())
            }
        }
    }

    private func content(_ decision: Decision) -> some View {
        let report = store.readiness(for: decision, selectedOptionID: decision.finalDecision?.selectedOptionID)

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                stateCard(report)

                VStack(alignment: .leading, spacing: 10) {
                    POPSectionHeader(title: "Checks", subtitle: "Each one is calculated from what you actually recorded.", icon: "checklist")
                    ForEach(report.sorted) { check in
                        checkRow(check)
                    }
                }

                if !report.blockers.isEmpty {
                    POPBanner(
                        kind: .danger,
                        message: "Finalization is blocked.",
                        detail: "Blocking issues must be fixed — they cannot be accepted as known gaps."
                    )
                } else if report.requiresGapAcknowledgement {
                    POPBanner(
                        kind: .warning,
                        message: "You can proceed with known gaps.",
                        detail: "Finalize will ask you to acknowledge each warning in writing."
                    )
                }

                NavigationLink(value: AppRoute.finalize(decisionID)) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal").font(.system(size: 15, weight: .semibold))
                        Text("Go to Finalize Decision").font(POPFont.cardTitle)
                    }
                    .foregroundStyle(report.canFinalize ? POPColor.graphite : POPColor.inkTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: POPMetrics.controlRadius, style: .continuous)
                        .fill(report.canFinalize ? POPColor.brandYellow : POPColor.surfaceMuted))
                }

                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 10)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationTitle("Decision Readiness")
        .navigationBarTitleDisplayMode(.inline)
        .popNavigationDestination(item: $route) { destination in
            if case .decisionSection(let id, let section) = destination {
                DecisionWorkspaceView(decisionID: id, initialSection: section)
            }
        }
    }

    private func stateCard(_ report: ReadinessReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: report.state.icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(report.state.color)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(report.state.softColor))
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.state.title)
                        .font(POPFont.display(25))
                        .foregroundStyle(POPColor.ink)
                    Text(stateExplanation(report))
                        .font(POPFont.callout)
                        .foregroundStyle(POPColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                POPStatTile(value: "\(report.passed.count)", label: "Passed",
                            icon: "checkmark.circle.fill", tint: POPColor.success)
                POPStatTile(value: "\(report.warnings.count)", label: "Warnings",
                            icon: "exclamationmark.triangle.fill",
                            tint: report.warnings.isEmpty ? POPColor.graphite : POPColor.brandOrange)
                POPStatTile(value: "\(report.blockers.count)", label: "Blockers",
                            icon: "lock.fill",
                            tint: report.blockers.isEmpty ? POPColor.graphite : POPColor.danger)
            }
        }
        .popCard()
    }

    private func stateExplanation(_ report: ReadinessReport) -> String {
        switch report.state {
        case .ready: return "Everything checks out. You can finalize whenever you are ready."
        case .needsAttention: return "Nothing is blocking you, but there are gaps worth looking at first."
        case .blocked: return "One or more checks must be fixed before this decision can be finalized."
        }
    }

    private func checkRow(_ check: ReadinessCheck) -> some View {
        Button(action: {
            guard let destination = check.destination else { return }
            Haptics.tap()
            route = .decisionSection(decisionID, destination)
        }) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: check.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(check.color)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(check.softColor))
                VStack(alignment: .leading, spacing: 3) {
                    Text(check.title)
                        .font(POPFont.calloutMedium)
                        .foregroundStyle(POPColor.ink)
                        .multilineTextAlignment(.leading)
                    Text(check.message)
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if check.destination != nil && check.severity != .passed {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(POPColor.inkTertiary)
                        .padding(.top, 8)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(check.severity == .blocked ? POPColor.danger.opacity(0.4) : POPColor.hairline,
                              lineWidth: check.severity == .blocked ? 1.4 : 1))
        }
        .buttonStyle(POPPressStyle())
        .disabled(check.destination == nil)
    }
}
