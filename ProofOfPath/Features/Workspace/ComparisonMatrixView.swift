//
//  ComparisonMatrixView.swift
//  ProofOfPath
//
//  Rows are criteria, columns are options. Tapping a cell explains itself.
//

import SwiftUI

struct ComparisonMatrixView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID

    @State private var mode: MatrixDisplayMode = .scores
    @State private var selectedCell: MatrixCellSelection?
    @State private var showRejected = false

    private var decision: Decision? { store.state.decision(id: decisionID) }

    private let labelWidth: CGFloat = 132
    private let cellWidth: CGFloat = 104

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
        let scoreboard = store.scoreboard(for: decision)
        let options = showRejected ? decision.sortedOptions : decision.comparableOptions
        let criteria = decision.sortedCriteria

        return VStack(spacing: 0) {
            modeBar

            if criteria.isEmpty || options.isEmpty {
                ScrollView {
                    POPEmptyState(
                        icon: "tablecells",
                        title: criteria.isEmpty ? "No criteria yet" : "No options yet",
                        message: criteria.isEmpty
                            ? "Add criteria in the Criteria Workshop to build the matrix."
                            : "Add at least one option to compare."
                    )
                    .padding(.top, 30)
                }
                .background(POPColor.canvas.ignoresSafeArea())
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                        if !decision.isWeightBalanced {
                            POPBanner(
                                kind: .warning,
                                message: decision.totalWeight > 100
                                    ? "Criteria weights exceed 100%. Reduce one or more values."
                                    : "Assign the remaining weight before comparing options.",
                                detail: "Total is \(POPFormat.percent(decision.totalWeight)). Scores below are provisional."
                            )
                            .padding(.horizontal, POPMetrics.gutter)
                        }

                        matrix(decision: decision, options: options, criteria: criteria, scoreboard: scoreboard)

                        legend
                            .padding(.horizontal, POPMetrics.gutter)

                        Color.clear.frame(height: 16)
                    }
                    .padding(.top, 12)
                }
                .background(POPColor.canvas.ignoresSafeArea())
            }
        }
        .navigationTitle("Comparison Matrix")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Show rejected options", isOn: $showRejected)
                    Divider()
                    NavigationLink(value: AppRoute.scenarioLab(decisionID)) {
                        Label("Scenario Lab", systemImage: "flask")
                    }
                    NavigationLink(value: AppRoute.costView(decisionID)) {
                        Label("Total Cost View", systemImage: "banknote")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(POPColor.graphite)
                }
                .accessibilityLabel(Text("Matrix options"))
            }
        }
        .sheet(item: $selectedCell) { selection in
            EvaluationDetailsSheet(
                decisionID: decisionID,
                optionID: selection.optionID,
                criterionID: selection.criterionID
            )
        }
    }

    // MARK: Mode bar

    private var modeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(MatrixDisplayMode.allCases) { candidate in
                    POPChip(title: candidate.title, isSelected: mode == candidate) {
                        withAnimation(.easeInOut(duration: 0.18)) { mode = candidate }
                    }
                }
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.vertical, 9)
        }
        .background(
            POPColor.surface
                .overlay(alignment: .bottom) { Rectangle().fill(POPColor.hairline).frame(height: 1) }
        )
    }

    // MARK: Matrix

    private func matrix(
        decision: Decision,
        options: [DecisionOption],
        criteria: [Criterion],
        scoreboard: DecisionScoreboard
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                headerRow(decision: decision, options: options, scoreboard: scoreboard)

                ForEach(Array(criteria.enumerated()), id: \.element.id) { index, criterion in
                    criterionRow(
                        criterion: criterion,
                        options: options,
                        scoreboard: scoreboard,
                        decision: decision,
                        isEven: index % 2 == 0
                    )
                }

                totalRow(options: options, scoreboard: scoreboard)
                mustHaveRow(options: options, scoreboard: scoreboard)
                coverageRow(options: options, scoreboard: scoreboard)
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(POPColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(POPColor.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, POPMetrics.gutter)
        }
        .scrollClipDisabled()
    }

    private func headerRow(decision: Decision, options: [DecisionOption], scoreboard: DecisionScoreboard) -> some View {
        HStack(spacing: 0) {
            Text("Criterion")
                .font(POPFont.micro)
                .foregroundStyle(POPColor.inkSecondary)
                .frame(width: labelWidth, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)

            ForEach(options) { option in
                let score = scoreboard.score(for: option.id)
                let isLeader = scoreboard.leaderID == option.id
                VStack(spacing: 3) {
                    Text(option.displayName)
                        .font(POPFont.captionMedium)
                        .foregroundStyle(POPColor.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if isLeader {
                        POPBadge(text: "Leader", icon: "crown.fill",
                                 color: POPColor.graphite, soft: POPColor.brandYellow, compact: true)
                    } else if score?.isDisqualified == true {
                        POPBadge(text: "Disqualified", color: POPColor.danger, soft: POPColor.dangerSoft, compact: true)
                    } else if score?.failsMustHave == true {
                        POPBadge(text: "Fails must-have", color: POPColor.danger, soft: POPColor.dangerSoft, compact: true)
                    } else if option.status == .rejected {
                        POPBadge(text: "Rejected", color: POPColor.inkTertiary, soft: POPColor.neutralSoft, compact: true)
                    }
                }
                .frame(width: cellWidth)
                .padding(.vertical, 9)
                .padding(.horizontal, 5)
                .background(isLeader ? POPColor.brandYellow.opacity(0.18) : Color.clear)
            }
        }
        .background(POPColor.surfaceSunk)
        .overlay(alignment: .bottom) { Rectangle().fill(POPColor.hairline).frame(height: 1) }
    }

    private func criterionRow(
        criterion: Criterion,
        options: [DecisionOption],
        scoreboard: DecisionScoreboard,
        decision: Decision,
        isEven: Bool
    ) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(criterion.displayName)
                        .font(POPFont.captionMedium)
                        .foregroundStyle(POPColor.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if criterion.importance == .mustHave {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(POPColor.brandOrange)
                    }
                }
                Text(POPFormat.percent(criterion.weight))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(POPColor.inkTertiary)
            }
            .frame(width: labelWidth, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)

            ForEach(options) { option in
                Button(action: {
                    Haptics.tap()
                    selectedCell = MatrixCellSelection(optionID: option.id, criterionID: criterion.id)
                }) {
                    cellContent(
                        cell: scoreboard.score(for: option.id)?.cells[criterion.id],
                        criterion: criterion,
                        isLeader: scoreboard.leaderID == option.id
                    )
                }
                .buttonStyle(POPPressStyle())
            }
        }
        .background(isEven ? POPColor.surface : POPColor.surfaceMuted.opacity(0.45))
        .overlay(alignment: .bottom) { Rectangle().fill(POPColor.hairlineSoft).frame(height: 1) }
    }

    @ViewBuilder
    private func cellContent(cell: CellScore?, criterion: Criterion, isLeader: Bool) -> some View {
        VStack(spacing: 4) {
            switch mode {
            case .scores:
                if let normalized = cell?.normalized {
                    Text(POPFormat.score(normalized * 100))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(POPColor.ink)
                        .monospacedDigit()
                    POPMeter(value: normalized, tint: scoreTint(normalized), height: 5)
                        .frame(width: cellWidth - 26)
                } else {
                    emptyCell
                }

            case .rawValues:
                Text(cell?.rawDisplay ?? "—")
                    .font(POPFont.captionMedium)
                    .foregroundStyle((cell?.rawDisplay ?? "—") == "—" ? POPColor.inkTertiary : POPColor.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

            case .confidence:
                if let confidence = cell?.confidence {
                    ConfidenceMarker(level: confidence, showLabel: true)
                } else {
                    emptyCell
                }

            case .evidenceCoverage:
                if let cell {
                    EvidenceCoverageIndicator(supporting: cell.supportingEvidence, contradicting: cell.contradictingEvidence)
                } else {
                    emptyCell
                }
            }

            if let status = cell?.status, status != .notEvaluated, mode != .confidence {
                Image(systemName: status.icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(status.color)
            }
        }
        .frame(width: cellWidth)
        .frame(minHeight: 62)
        .padding(.horizontal, 5)
        .padding(.vertical, 8)
        .background(isLeader ? POPColor.brandYellow.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }

    private var emptyCell: some View {
        Text("—")
            .font(POPFont.captionMedium)
            .foregroundStyle(POPColor.inkTertiary)
    }

    private func scoreTint(_ normalized: Double) -> Color {
        if normalized >= 0.7 { return POPColor.success }
        if normalized >= 0.4 { return POPColor.brandYellow }
        return POPColor.brandOrange
    }

    private func totalRow(options: [DecisionOption], scoreboard: DecisionScoreboard) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Weighted Score")
                    .font(POPFont.captionMedium)
                    .foregroundStyle(POPColor.ink)
                Text("of 100")
                    .font(.system(size: 10))
                    .foregroundStyle(POPColor.inkTertiary)
            }
            .frame(width: labelWidth, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            ForEach(options) { option in
                let score = scoreboard.score(for: option.id)
                VStack(spacing: 2) {
                    Text(score.map { $0.evaluatedWeight > 0 ? POPFormat.score($0.weightedScore) : "—" } ?? "—")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(score?.isEligibleLeader == false ? POPColor.inkTertiary : POPColor.ink)
                        .monospacedDigit()
                    if let score, !score.isComplete, score.evaluatedWeight > 0 {
                        Text("\(score.unevaluatedCriteriaIDs.count) missing")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(POPColor.brandOrange)
                    }
                }
                .frame(width: cellWidth)
                .padding(.vertical, 9)
                .background(scoreboard.leaderID == option.id ? POPColor.brandYellow.opacity(0.18) : Color.clear)
            }
        }
        .background(POPColor.surfaceSunk)
        .overlay(alignment: .top) { Rectangle().fill(POPColor.hairline).frame(height: 1) }
    }

    private func mustHaveRow(options: [DecisionOption], scoreboard: DecisionScoreboard) -> some View {
        HStack(spacing: 0) {
            Text("Must-Have Status")
                .font(POPFont.captionMedium)
                .foregroundStyle(POPColor.ink)
                .frame(width: labelWidth, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)

            ForEach(options) { option in
                let score = scoreboard.score(for: option.id)
                Group {
                    if score?.isDisqualified == true {
                        POPBadge(text: "Disqualified", icon: "lock.slash",
                                 color: POPColor.danger, soft: POPColor.dangerSoft, compact: true)
                    } else if score?.failsMustHave == true {
                        POPBadge(text: "Not met", icon: "xmark.circle.fill",
                                 color: POPColor.danger, soft: POPColor.dangerSoft, compact: true)
                    } else if (score?.uncheckedMustHaves.isEmpty ?? true) == false {
                        POPBadge(text: "Not checked", icon: "questionmark.circle",
                                 color: POPColor.inkSecondary, soft: POPColor.neutralSoft, compact: true)
                    } else if (score?.mustHaveResults.isEmpty ?? true) {
                        Text("—").font(POPFont.caption).foregroundStyle(POPColor.inkTertiary)
                    } else {
                        POPBadge(text: "All met", icon: "checkmark.circle.fill",
                                 color: POPColor.success, soft: POPColor.successSoft, compact: true)
                    }
                }
                .frame(width: cellWidth)
                .padding(.vertical, 9)
                .padding(.horizontal, 4)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(POPColor.hairlineSoft).frame(height: 1) }
    }

    private func coverageRow(options: [DecisionOption], scoreboard: DecisionScoreboard) -> some View {
        HStack(spacing: 0) {
            Text("Evidence Coverage")
                .font(POPFont.captionMedium)
                .foregroundStyle(POPColor.ink)
                .frame(width: labelWidth, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)

            ForEach(options) { option in
                let score = scoreboard.score(for: option.id)
                VStack(spacing: 3) {
                    Text("\(Int(((score?.evidenceCoverage ?? 0) * 100).rounded()))%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle((score?.evidenceCoverage ?? 0) >= 0.5 ? POPColor.success : POPColor.brandOrange)
                        .monospacedDigit()
                    POPMeter(
                        value: score?.evidenceCoverage ?? 0,
                        tint: (score?.evidenceCoverage ?? 0) >= 0.5 ? POPColor.success : POPColor.brandOrange,
                        height: 4
                    )
                    .frame(width: cellWidth - 30)
                }
                .frame(width: cellWidth)
                .padding(.vertical, 9)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(POPColor.hairlineSoft).frame(height: 1) }
    }

    // MARK: Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 9) {
            POPSectionHeader(title: "How to read this", icon: "info.circle")
            VStack(alignment: .leading, spacing: 7) {
                legendRow(icon: "hand.tap", text: "Tap any cell to see the reason for the rating and the linked evidence.")
                legendRow(icon: "scalemass", text: "Scores are renormalised over the criteria that were actually evaluated, so an unfinished option is not unfairly punished — the missing count is shown instead.")
                legendRow(icon: "lock.slash", text: "An option that breaks a hard constraint or fails a must-have cannot be the leader, whatever it scores.")
                legendRow(icon: "checkmark.seal", text: "Evidence coverage is the share of criteria with at least one supporting item for that option.")
            }
        }
        .popCard()
    }

    private func legendRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(POPColor.brandOrange)
                .frame(width: 16)
                .padding(.top, 1.5)
            Text(text)
                .font(POPFont.caption)
                .foregroundStyle(POPColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Cell selection

struct MatrixCellSelection: Identifiable, Hashable {
    let optionID: UUID
    let criterionID: UUID
    var id: String { "\(optionID.uuidString)-\(criterionID.uuidString)" }
}

// MARK: - Evaluation details

struct EvaluationDetailsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID
    let optionID: UUID
    let criterionID: UUID

    @State private var showEvaluationEditor = false

    private var decision: Decision? { store.state.decision(id: decisionID) }
    private var option: DecisionOption? { decision?.option(id: optionID) }
    private var criterion: Criterion? { decision?.criterion(id: criterionID) }
    private var evaluation: Evaluation? { option?.evaluation(for: criterionID) }

    private var linkedEvidence: [Evidence] {
        store.state.evidence(forDecision: decisionID).filter { item in
            item.links.contains { $0.optionID == optionID && $0.criterionID == criterionID }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let decision, let option, let criterion {
                    content(decision: decision, option: option, criterion: criterion)
                } else {
                    POPEmptyState(icon: "questionmark.folder", title: "Not available",
                                  message: "This cell no longer exists.",
                                  actionTitle: "Close", action: { dismiss() })
                        .background(POPColor.canvas.ignoresSafeArea())
                }
            }
        }
    }

    private func content(decision: Decision, option: DecisionOption, criterion: Criterion) -> some View {
        let scoreboard = store.scoreboard(for: decision)
        let cell = scoreboard.score(for: optionID)?.cells[criterionID]
        let score = scoreboard.score(for: optionID)

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(criterion.displayName)
                        .font(POPFont.title)
                        .foregroundStyle(POPColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("for \(option.displayName)")
                        .font(POPFont.callout)
                        .foregroundStyle(POPColor.inkSecondary)
                    HStack(spacing: 6) {
                        if let status = cell?.status {
                            POPBadge(text: status.title, icon: status.icon, color: status.color, soft: status.softColor)
                        }
                        POPBadge(text: POPFormat.percent(criterion.weight),
                                 color: POPColor.brandOrange, soft: POPColor.warningSoft)
                        Spacer(minLength: 0)
                    }
                }
                .popCard()

                VStack(alignment: .leading, spacing: 11) {
                    POPSectionHeader(title: "Evaluation Details", icon: "doc.text.magnifyingglass")
                    POPKeyValueRow(label: "Measured Value", value: cell?.rawDisplay ?? "—", icon: "ruler")
                    POPDivider()
                    if criterion.kind == .yesNo {
                        POPKeyValueRow(
                            label: "Answer",
                            value: evaluation?.boolValue.map { $0 ? "Yes" : "No" } ?? "Not answered",
                            valueColor: evaluation?.boolValue == true ? POPColor.success : (evaluation?.boolValue == false ? POPColor.danger : POPColor.inkTertiary),
                            icon: "checkmark.square"
                        )
                    } else {
                        POPKeyValueRow(
                            label: "Rating",
                            value: evaluation?.rating.map { "\($0) of \(store.state.scaleMax)" } ?? "Not rated",
                            icon: "star.leadinghalf.filled"
                        )
                    }
                    POPDivider()
                    POPKeyValueRow(
                        label: "Confidence",
                        value: cell?.confidence?.title ?? "—",
                        valueColor: cell?.confidence?.color ?? POPColor.inkTertiary,
                        icon: "gauge.medium"
                    )
                    if let cell, let normalized = cell.normalized, let score, score.evaluatedWeight > 0 {
                        POPDivider()
                        let contribution = ScoringEngine.contribution(
                            cell: cell,
                            weight: criterion.weight,
                            evaluatedWeight: score.evaluatedWeight
                        )
                        POPKeyValueRow(
                            label: "Contribution to score",
                            value: contribution.map { "\(POPFormat.score($0)) points" } ?? "—",
                            icon: "plusminus"
                        )
                        POPInlineNote(
                            text: "Normalised value \(POPFormat.decimal(normalized, maxFractionDigits: 2)) × weight \(POPFormat.percent(criterion.weight)) ÷ evaluated weight \(POPFormat.percent(score.evaluatedWeight)) × 100.",
                            icon: "function"
                        )
                    }
                }
                .popCard()

                VStack(alignment: .leading, spacing: 9) {
                    POPSectionHeader(title: "Reason for Rating", icon: "text.quote")
                    if let reason = evaluation?.reason, !reason.popIsBlank {
                        Text(reason)
                            .font(POPFont.body)
                            .foregroundStyle(POPColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        POPInlineNote(text: "No reason written. That is why this rating cannot count as supported.")
                    }
                }
                .popCard()

                VStack(alignment: .leading, spacing: 11) {
                    POPSectionHeader(title: "Linked Evidence", icon: "paperclip")
                    if linkedEvidence.isEmpty {
                        POPInlineNote(text: "Nothing linked to this specific rating.")
                    } else {
                        ForEach(linkedEvidence) { item in
                            let relation = item.links.first { $0.optionID == optionID && $0.criterionID == criterionID }?.relation ?? .context
                            NavigationLink(value: AppRoute.evidenceDetail(item.id)) {
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: relation.icon)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(relation.color)
                                        .padding(.top, 1)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.displayTitle)
                                            .font(POPFont.calloutMedium)
                                            .foregroundStyle(POPColor.ink)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text("\(relation.shortTitle) · \(item.verification.title)")
                                            .font(POPFont.caption)
                                            .foregroundStyle(POPColor.inkSecondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10.5, weight: .bold))
                                        .foregroundStyle(POPColor.inkTertiary)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(relation.softColor))
                            }
                            .buttonStyle(POPPressStyle())
                        }
                    }
                }
                .popCard()

                if criterion.importance == .mustHave {
                    let result = ScoringEngine.mustHaveResult(criterion: criterion, option: option, scaleMax: store.state.scaleMax)
                    POPBanner(
                        kind: result.outcome == .failed ? .danger : (result.outcome == .met ? .success : .warning),
                        message: "Must-Have: \(result.outcome.title)",
                        detail: result.explanation
                    )
                }

                POPPrimaryButton(title: "Edit Evaluation", icon: "square.and.pencil") {
                    showEvaluationEditor = true
                }

                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 8)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationTitle("Evaluation Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                    .foregroundStyle(POPColor.inkSecondary)
            }
        }
        .sheet(isPresented: $showEvaluationEditor) {
            CriterionEvaluationSheet(decisionID: decisionID, optionID: optionID, criterionID: criterionID)
        }
    }
}
