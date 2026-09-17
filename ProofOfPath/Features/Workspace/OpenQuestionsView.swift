//
//  OpenQuestionsView.swift
//  ProofOfPath
//
//  Everything still missing, collected automatically from real records.
//

import SwiftUI

struct OpenQuestionsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let decisionID: UUID

    @State private var acceptingQuestion: OpenQuestion?
    @State private var showFollowUpSheet = false
    @State private var followUpPrefill: OpenQuestion?
    @State private var route: AppRoute?
    @State private var showAccepted = false

    private var decision: Decision? { store.state.decision(id: decisionID) }

    private var unresolved: [OpenQuestion] {
        guard let decision else { return [] }
        return store.openQuestions(for: decision)
    }

    private var groups: [OpenQuestionGroup] {
        OpenQuestionsEngine.grouped(unresolved)
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
                CoinStrikeFeatureBanner(asset: "CoinStrikeQuestions")
                summary(decision)

                if unresolved.isEmpty {
                    POPEmptyState(
                        icon: "checkmark.circle",
                        title: "Nothing is missing",
                        message: "Every criterion is evaluated, every claim resolved and no hard constraint is broken."
                    )
                    .popCard(padding: 6)
                } else {
                    ForEach(groups) { group in
                        groupCard(group, decision: decision)
                    }
                }

                if !decision.followUpTasks.isEmpty {
                    followUpCard(decision)
                }

                if !decision.acceptedUnknowns.isEmpty {
                    acceptedCard(decision)
                }

                POPSecondaryButton(title: "Create Follow-Up Task", icon: "flag") {
                    followUpPrefill = nil
                    showFollowUpSheet = true
                }
                .popRequiresConnection()

                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, POPMetrics.gutter)
            .padding(.top, 10)
        }
        .background(POPColor.canvas.ignoresSafeArea())
        .navigationTitle("Open Questions")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $acceptingQuestion) { question in
            AcceptUnknownSheet(decisionID: decisionID, question: question)
        }
        .sheet(isPresented: $showFollowUpSheet) {
            FollowUpEditorSheet(decisionID: decisionID, prefill: followUpPrefill)
        }
        .popNavigationDestination(item: $route) { destination in
            switch destination {
            case .decisionSection(let id, let section):
                DecisionWorkspaceView(decisionID: id, initialSection: section)
            case .evidenceDetail(let id):
                EvidenceDetailView(evidenceID: id)
            case .optionDetail(let decisionID, let optionID):
                OptionDetailView(decisionID: decisionID, optionID: optionID)
            default:
                EmptyView()
            }
        }
    }

    // MARK: Summary

    private func summary(_ decision: Decision) -> some View {
        let blocking = unresolved.filter(\.isBlocking).count
        return VStack(alignment: .leading, spacing: 12) {
            POPSectionHeader(
                title: "Missing Information",
                subtitle: "Collected automatically from your criteria, options, claims, evidence and risks.",
                icon: "questionmark.circle"
            )
            HStack(spacing: 10) {
                POPStatTile(value: "\(unresolved.count)", label: "Open questions", icon: "questionmark.circle",
                            tint: unresolved.isEmpty ? POPColor.success : POPColor.brandOrange)
                POPStatTile(value: "\(blocking)", label: "Blocking", icon: "lock.slash",
                            tint: blocking > 0 ? POPColor.danger : POPColor.graphite)
                POPStatTile(value: "\(decision.acceptedUnknowns.count)", label: "Accepted gaps", icon: "hand.raised")
            }
            if blocking > 0 {
                POPBanner(
                    kind: .danger,
                    message: "\(blocking) hard-constraint \(blocking == 1 ? "violation" : "violations") cannot be accepted as unknown.",
                    detail: "Change the constraint, fix the option, or reject the option."
                )
            }
        }
        .popCard()
    }

    // MARK: Group

    private func groupCard(_ group: OpenQuestionGroup, decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: group.kind.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(group.kind.color)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(group.kind.color.opacity(0.12)))
                Text(group.kind.title)
                    .font(POPFont.sectionTitle)
                    .foregroundStyle(POPColor.ink)
                Spacer()
                Text("\(group.questions.count)")
                    .font(POPFont.captionMedium)
                    .foregroundStyle(POPColor.inkSecondary)
            }

            ForEach(group.questions.prefix(showAllFor(group) ? group.questions.count : 5)) { question in
                questionRow(question, decision: decision)
            }

            if group.questions.count > 5 && !showAllFor(group) {
                POPTextButton(title: "Show all \(group.questions.count)", icon: "chevron.down") {
                    expanded.insert(group.kind)
                }
            }
        }
        .popCard()
    }

    @State private var expanded: Set<OpenQuestionKind> = []

    private func showAllFor(_ group: OpenQuestionGroup) -> Bool {
        expanded.contains(group.kind)
    }

    private func questionRow(_ question: OpenQuestion, decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(question.title)
                    .font(POPFont.calloutMedium)
                    .foregroundStyle(POPColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(question.detail)
                    .font(POPFont.caption)
                    .foregroundStyle(POPColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                POPPillButton(title: "Resolve Now", icon: "arrow.right", filled: true) {
                    resolve(question)
                }
                if !question.isBlocking {
                    POPPillButton(title: "Accept Unknown", icon: "hand.raised") {
                        acceptingQuestion = question
                    }
                    .popRequiresConnection()
                }
                POPPillButton(title: "Follow-Up", icon: "flag") {
                    followUpPrefill = question
                    showFollowUpSheet = true
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(question.isBlocking ? POPColor.dangerSoft : POPColor.surfaceMuted))
    }

    private func resolve(_ question: OpenQuestion) {
        if let optionID = question.optionID, question.kind == .unevaluatedCriterion || question.kind == .optionWithoutCost {
            route = .optionDetail(decisionID: decisionID, optionID: optionID)
        } else if let evidenceID = question.evidenceID {
            route = .evidenceDetail(evidenceID)
        } else {
            route = .decisionSection(decisionID, question.destination)
        }
    }

    // MARK: Follow-ups

    private func followUpCard(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(title: "Follow-Up Tasks", icon: "flag")
            ForEach(decision.followUpTasks.sorted { lhs, rhs in
                if lhs.isDone != rhs.isDone { return !lhs.isDone }
                return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
            }) { task in
                HStack(alignment: .top, spacing: 10) {
                    Button(action: {
                        Haptics.selection()
                        store.send(.setFollowUpDone(decisionID: decisionID, taskID: task.id, isDone: !task.isDone))
                    }) {
                        Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(task.isDone ? POPColor.success : POPColor.hairline)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(task.isDone ? "Mark as not done" : "Mark as done"))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(POPFont.calloutMedium)
                            .foregroundStyle(task.isDone ? POPColor.inkTertiary : POPColor.ink)
                            .strikethrough(task.isDone, color: POPColor.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let due = task.dueDate {
                            Text("Due \(POPFormat.date(due)) · \(POPFormat.relativeDeadline(due))")
                                .font(POPFont.caption)
                                .foregroundStyle(!task.isDone && POPFormat.daysUntil(due) < 0 ? POPColor.danger : POPColor.inkSecondary)
                        }
                        if !task.notes.popIsBlank {
                            Text(task.notes)
                                .font(POPFont.caption)
                                .foregroundStyle(POPColor.inkTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    Button(action: {
                        Haptics.warning()
                        store.send(.deleteFollowUp(decisionID: decisionID, taskID: task.id))
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(POPColor.inkTertiary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("Delete task"))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.surfaceMuted))
            }
        }
        .popCard()
    }

    // MARK: Accepted unknowns

    private func acceptedCard(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            POPSectionHeader(
                title: "Accepted Unknowns",
                subtitle: "Gaps you chose to proceed with, and why.",
                icon: "hand.raised"
            )
            ForEach(decision.acceptedUnknowns) { unknown in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: unknown.kind.icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(POPColor.inkSecondary)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(unknown.label)
                                .font(POPFont.calloutMedium)
                                .foregroundStyle(POPColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(unknown.reason)
                                .font(POPFont.caption)
                                .foregroundStyle(POPColor.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Accepted \(POPFormat.date(unknown.acceptedAt))")
                                .font(.system(size: 10.5))
                                .foregroundStyle(POPColor.inkTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    POPTextButton(title: "Put back in Open Questions", icon: "arrow.uturn.backward") {
                        store.send(.removeAcceptedUnknown(decisionID: decisionID, unknownID: unknown.id))
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.neutralSoft))
            }
        }
        .popCard()
    }
}

// MARK: - Accept unknown

struct AcceptUnknownSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var submission = POPSubmission()

    let decisionID: UUID
    let question: OpenQuestion

    @State private var reason = ""
    @State private var showValidation = false

    private var reasonError: String? {
        guard showValidation, reason.popIsBlank else { return nil }
        return "An explanation is required before you can proceed without this."
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(question.title)
                            .font(POPFont.title)
                            .foregroundStyle(POPColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(question.detail)
                            .font(POPFont.callout)
                            .foregroundStyle(POPColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .popCard()

                    POPTextEditor(
                        label: "Why are you comfortable proceeding?",
                        text: $reason,
                        placeholder: "e.g. The price difference is small enough that this detail cannot change my choice.",
                        isRequired: true,
                        hint: "This is stored with the decision and shown again in the outcome review.",
                        errorText: reasonError,
                        characterLimit: 500,
                        minHeight: 110
                    )

                    POPPrimaryButton(title: "Mark as Accepted Unknown", icon: "hand.raised",
                                     isEnabled: store.canEdit, isLoading: submission.isRunning) {
                        guard !reason.popIsBlank else {
                            showValidation = true
                            Haptics.error()
                            return
                        }
                        submission.run(store, .acceptUnknown(
                            decisionID: decisionID,
                            question: AcceptedUnknownDraft(
                                questionKey: question.key,
                                kind: question.kind,
                                label: question.title,
                                reason: reason
                            )
                        )) { dismiss() }
                    }

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 8)
            }
            .background(POPColor.canvas.ignoresSafeArea())
            .navigationTitle("Accept Unknown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(POPColor.inkSecondary)
                }
            }
        }
    }
}

// MARK: - Follow-up editor

struct FollowUpEditorSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    /// Fixed for the life of the sheet, so saving again after a lost response
    /// updates the same record instead of creating a second one.
    @State private var newRecordID = UUID()
    @StateObject private var submission = POPSubmission()

    let decisionID: UUID
    var prefill: OpenQuestion?

    @State private var title = ""
    @State private var notes = ""
    @State private var dueDate: Date?
    @State private var showValidation = false
    @State private var loaded = false

    private var titleError: String? {
        guard showValidation, title.popIsBlank else { return nil }
        return "Describe what needs to be done."
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: POPMetrics.sectionGap) {
                    POPTextField(
                        label: "Task",
                        text: $title,
                        placeholder: "e.g. Call the shop about warranty terms",
                        isRequired: true,
                        errorText: titleError,
                        characterLimit: 120
                    )
                    POPTextEditor(
                        label: "Notes",
                        text: $notes,
                        placeholder: "Anything you need at hand when you do it.",
                        characterLimit: 400,
                        minHeight: 84
                    )
                    POPDateField(
                        label: "Due Date",
                        date: $dueDate,
                        hint: "Optional. A reminder is scheduled if reminders are on."
                    )
                    POPPrimaryButton(title: "Create Task", icon: "plus", isEnabled: store.canEdit, isLoading: submission.isRunning) {
                        guard !title.popIsBlank else {
                            showValidation = true
                            Haptics.error()
                            return
                        }
                        var task = FollowUpTask(id: newRecordID, title: title.popTrimmed)
                        task.notes = notes.popTrimmed
                        task.dueDate = dueDate
                        task.relatedQuestionKey = prefill?.key
                        submission.run(store, .addFollowUp(decisionID: decisionID, task: task)) { dismiss() }
                    }
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, POPMetrics.gutter)
                .padding(.top, 8)
            }
            .background(POPColor.canvas.ignoresSafeArea())
            .navigationTitle("Follow-Up Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(POPColor.inkSecondary)
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let prefill {
                title = prefill.title.popTruncated(110)
                notes = prefill.detail
            }
        }
    }
}
