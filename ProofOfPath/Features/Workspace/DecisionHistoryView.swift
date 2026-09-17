//
//  DecisionHistoryView.swift
//  ProofOfPath
//
//  Chronology and versions. Snapshots are read-only and never replaced silently.
//

import SwiftUI

struct DecisionHistoryView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID

    @State private var filter: ActivityFilter = .all

    private var decision: Decision? { store.state.decision(id: decisionID) }

    private func events(_ decision: Decision) -> [ActivityEvent] {
        let sorted = decision.sortedActivity
        guard filter != .all else { return sorted }
        return sorted.filter { $0.kind.group == filter }
    }

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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                if !decision.snapshots.isEmpty {
                    versionsCard(decision)
                }

                VStack(alignment: .leading, spacing: 12) {
                    POPSectionHeader(title: "Activity", subtitle: "Every change, newest first.", icon: "clock.arrow.circlepath")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ActivityFilter.allCases) { candidate in
                                let count = candidate == .all
                                    ? decision.activity.count
                                    : decision.activity.filter { $0.kind.group == candidate }.count
                                POPChip(title: candidate.title, count: count, isSelected: filter == candidate) {
                                    filter = candidate
                                }
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                    .popScrollClipDisabled()

                    let list = events(decision)
                    if list.isEmpty {
                        POPEmptyState(icon: "clock", title: "Nothing here",
                                      message: "No events match this filter.", compact: true)
                            .popCard(padding: 4)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { index, event in
                                ActivityRow(event: event, isLast: index == list.count - 1)
                            }
                        }
                        .popCard()
                    }
                }

                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 10)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationTitle("History and Versions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func versionsCard(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(
                title: "Versions",
                subtitle: "Each finalization saves an immutable snapshot. Opening one never changes it.",
                icon: "square.stack.3d.down.right"
            )
            ForEach(decision.snapshots.sorted { $0.version > $1.version }) { snapshot in
                NavigationLink(value: AppRoute.snapshot(decisionID: decisionID, snapshotID: snapshot.id)) {
                    HStack(spacing: 11) {
                        VStack(spacing: 0) {
                            Text("v\(snapshot.version)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(POPColor.graphite)
                        }
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(POPColor.brandYellow))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.selectedOptionName.popIsBlank ? "No option recorded" : snapshot.selectedOptionName)
                                .font(POPFont.calloutMedium)
                                .foregroundStyle(POPColor.ink)
                                .lineLimit(1)
                            Text("\(POPFormat.dateTime(snapshot.createdAt)) · \(snapshot.criteria.count) criteria, \(snapshot.options.count) options")
                                .font(POPFont.caption)
                                .foregroundStyle(POPColor.inkSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(POPColor.inkTertiary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.surfaceMuted))
                }
                .buttonStyle(POPPressStyle())
            }
        }
        .popCard()
    }
}

// MARK: - Snapshot viewer

struct SnapshotView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID
    let snapshotID: UUID

    private var decision: Decision? { store.state.decision(id: decisionID) }
    private var snapshot: DecisionSnapshot? {
        decision?.snapshots.first { $0.id == snapshotID }
    }

    var body: some View {
        Group {
            if let snapshot, let decision {
                content(snapshot: snapshot, decision: decision)
            } else {
                POPEmptyState(icon: "questionmark.folder", title: "Snapshot not found",
                              message: "This version is no longer available.",
                              actionTitle: "Back", action: { dismiss() })
                    .background(POPColor.canvas.ignoresSafeArea())
            }
        }
    }

    private func content(snapshot: DecisionSnapshot, decision: Decision) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                POPBanner(
                    kind: .neutral,
                    message: "This is a read-only snapshot.",
                    detail: "It records exactly what the decision looked like at version \(snapshot.version). Nothing here can be edited."
                )

                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 11) {
                        Text("v\(snapshot.version)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(POPColor.graphite)
                            .frame(width: 44, height: 44)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(POPColor.brandYellow))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.selectedOptionName.popIsBlank ? "No option recorded" : snapshot.selectedOptionName)
                                .font(POPFont.title)
                                .foregroundStyle(POPColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Saved \(POPFormat.dateTime(snapshot.createdAt))")
                                .font(POPFont.caption)
                                .foregroundStyle(POPColor.inkSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    if let leaderScore = snapshot.leaderScore {
                        POPDivider()
                        POPKeyValueRow(label: "Score at the time", value: POPFormat.score(leaderScore), icon: "number")
                    }
                    if let final = snapshot.finalDecision {
                        POPDivider()
                        POPKeyValueRow(label: "Confidence", value: "\(final.confidence) of 5", icon: "gauge.medium")
                        POPKeyValueRow(label: "Why This Option?", value: final.whyThisOption, isMultiline: true)
                    }
                }
                .popCard()

                if !snapshot.criteria.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        POPSectionHeader(title: "Criteria and Weights", icon: "list.bullet.indent")
                        ForEach(snapshot.criteria.sorted { $0.sortIndex < $1.sortIndex }) { criterion in
                            HStack(spacing: 9) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(criterion.displayName)
                                        .font(POPFont.calloutMedium)
                                        .foregroundStyle(POPColor.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("\(criterion.importance.title) · \(criterion.kind.shortTitle)")
                                        .font(POPFont.caption)
                                        .foregroundStyle(POPColor.inkSecondary)
                                }
                                Spacer(minLength: 0)
                                Text(POPFormat.percent(criterion.weight))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(POPColor.ink)
                                    .monospacedDigit()
                            }
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(POPColor.surfaceMuted))
                        }
                    }
                    .popCard()
                }

                if !snapshot.options.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        POPSectionHeader(title: "Options at the time", icon: "square.stack.3d.up")
                        ForEach(snapshot.options.sorted { $0.sortIndex < $1.sortIndex }) { option in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(option.displayName)
                                        .font(POPFont.calloutMedium)
                                        .foregroundStyle(POPColor.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    POPBadge(text: option.status.title, color: option.status.color,
                                             soft: option.status.softColor, compact: true)
                                }
                                if let cost = option.estimatedCost {
                                    Text(POPFormat.money(cost, currencyCode: decision.currencyCode))
                                        .font(POPFont.caption)
                                        .foregroundStyle(POPColor.inkSecondary)
                                }
                                let rated = option.evaluations.filter { $0.hasJudgement }.count
                                Text("\(rated) of \(snapshot.criteria.count) criteria evaluated")
                                    .font(POPFont.caption)
                                    .foregroundStyle(POPColor.inkTertiary)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.surfaceMuted))
                        }
                    }
                    .popCard()
                }

                if !snapshot.evidence.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        POPSectionHeader(title: "Evidence at the time", icon: "paperclip")
                        ForEach(snapshot.evidence) { item in
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: item.type.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(POPColor.brandOrange)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.displayTitle)
                                        .font(POPFont.callout)
                                        .foregroundStyle(POPColor.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("\(item.type.title) · \(item.verification.title)")
                                        .font(POPFont.caption)
                                        .foregroundStyle(POPColor.inkSecondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .popCard()
                }

                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 10)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationTitle("Version \(snapshot.version)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
