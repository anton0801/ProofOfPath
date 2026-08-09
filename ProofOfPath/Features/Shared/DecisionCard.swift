//
//  DecisionCard.swift
//  ProofOfPath
//
//  The card used on Home and in the Decisions list.
//  Every figure on it is derived from the user's own records.
//

import SwiftUI

struct DecisionCard: View {
    @Environment(AppStore.self) private var store

    let decision: Decision
    var showsNextAction: Bool = true
    var onOpen: (WorkspaceSection) -> Void

    private var progress: DecisionProgress {
        store.progress(for: decision)
    }

    /// Visual "deadline approaching" window is fixed at a week — it is a reading
    /// aid, not the notification schedule.
    private var deadlineFlag: ProgressEngine.DeadlineFlag {
        ProgressEngine.deadlineFlag(for: decision, leadDays: 7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // The card body opens the brief; the footer is its own control so the
            // two taps can never fight over the same gesture.
            Button(action: {
                Haptics.tap()
                onOpen(.brief)
            }) {
                VStack(alignment: .leading, spacing: 11) {
                    header
                    metrics
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(POPPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text("Opens the decision brief"))

            if showsNextAction { footer }
        }
        .padding(POPMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: POPMetrics.cardRadius, style: .continuous).fill(POPColor.surface))
        .overlay(
            RoundedRectangle(cornerRadius: POPMetrics.cardRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
    }

    private var borderColor: Color {
        switch deadlineFlag {
        case .overdue: return POPColor.danger.opacity(0.45)
        case .approaching: return POPColor.brandOrange.opacity(0.4)
        case .none: return POPColor.hairline
        }
    }

    private var borderWidth: CGFloat {
        deadlineFlag.isNotable ? 1.5 : 1
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    POPBadge(
                        text: decision.categoryTitle,
                        icon: decision.category.icon,
                        color: POPColor.inkSecondary,
                        soft: POPColor.neutralSoft,
                        compact: true
                    )
                    POPBadge(
                        text: decision.status.title,
                        icon: decision.status.icon,
                        color: decision.status.color,
                        soft: decision.status.softColor,
                        compact: true
                    )
                }
                Text(decision.displayTitle)
                    .font(POPFont.cardTitle)
                    .foregroundStyle(POPColor.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            POPProgressRing(
                value: progress.fraction,
                size: 44,
                tint: progress.fraction >= 1 ? POPColor.success : POPColor.brandOrange
            )
        }
    }

    // MARK: Metrics

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                metric(icon: "square.stack.3d.up",
                       value: "\(decision.options.count)",
                       label: decision.options.count == 1 ? "option" : "options")
                metric(icon: "list.bullet.indent",
                       value: "\(decision.criteria.count)",
                       label: decision.criteria.count == 1 ? "criterion" : "criteria")
                if progress.unverifiedClaimCount > 0 {
                    metric(icon: "questionmark.diamond",
                           value: "\(progress.unverifiedClaimCount)",
                           label: "unverified",
                           tint: POPColor.brandOrange)
                }
                Spacer(minLength: 0)
            }

            if let deadline = decision.deadline {
                HStack(spacing: 5) {
                    Image(systemName: deadlineIcon)
                        .font(.system(size: 10.5, weight: .bold))
                    Text(deadlineText(deadline))
                        .font(POPFont.caption)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(deadlineColor)
            }

            if !decision.isWeightBalanced && !decision.criteria.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "scalemass")
                        .font(.system(size: 10.5, weight: .bold))
                    Text(decision.totalWeight > 100
                         ? "Weights exceed 100% (\(POPFormat.percent(decision.totalWeight)))"
                         : "\(POPFormat.percent(decision.weightRemaining)) of weight unassigned")
                        .font(POPFont.caption)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(POPColor.brandOrange)
            }
        }
    }

    private func metric(icon: String, value: String, label: String, tint: Color = POPColor.inkSecondary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10.5, weight: .semibold))
            Text(value).font(.system(size: 13, weight: .bold, design: .rounded))
            Text(label).font(POPFont.caption)
        }
        .foregroundStyle(tint)
    }

    private var deadlineIcon: String {
        switch deadlineFlag {
        case .overdue: return "exclamationmark.triangle.fill"
        case .approaching: return "clock.badge.exclamationmark"
        case .none: return "calendar"
        }
    }

    private var deadlineColor: Color {
        switch deadlineFlag {
        case .overdue: return POPColor.danger
        case .approaching: return POPColor.brandOrange
        case .none: return POPColor.inkSecondary
        }
    }

    private func deadlineText(_ deadline: Date) -> String {
        switch deadlineFlag {
        case .overdue, .approaching:
            return "\(POPFormat.relativeDeadline(deadline)) · \(POPFormat.date(deadline))"
        case .none:
            return "Deadline \(POPFormat.date(deadline))"
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        if decision.status == .finalized {
            Button(action: {
                Haptics.tap()
                onOpen(.decision)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(POPColor.success)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(decision.selectedOption?.displayName ?? "Option no longer available")
                            .font(POPFont.calloutMedium)
                            .foregroundStyle(POPColor.ink)
                            .lineLimit(1)
                        Text(reviewFooterText)
                            .font(POPFont.caption)
                            .foregroundStyle(decision.isReviewDue ? POPColor.brandOrange : POPColor.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(POPColor.inkTertiary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.successSoft))
                .contentShape(Rectangle())
            }
            .buttonStyle(POPPressStyle())
        } else if let next = progress.nextStep {
            Button(action: {
                Haptics.tap()
                onOpen(next.destination)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(POPColor.brandOrange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Next action")
                            .font(POPFont.micro)
                            .foregroundStyle(POPColor.inkTertiary)
                        Text(next.actionLabel)
                            .font(POPFont.calloutMedium)
                            .foregroundStyle(POPColor.ink)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(POPColor.inkTertiary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.surfaceSunk))
                .contentShape(Rectangle())
            }
            .buttonStyle(POPPressStyle())
            .accessibilityHint(Text("Opens \(next.destination.title)"))
        } else {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(POPColor.success)
                Text("Everything is filled in — ready to finalize.")
                    .font(POPFont.calloutMedium)
                    .foregroundStyle(POPColor.ink)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(POPColor.successSoft))
        }
    }

    private var reviewFooterText: String {
        if decision.outcomeReview?.isComplete == true {
            return "Outcome reviewed"
        }
        if let reviewDate = decision.finalDecision?.outcomeReviewDate {
            return decision.isReviewDue
                ? "Outcome review due · \(POPFormat.relativeDeadline(reviewDate))"
                : "Review scheduled \(POPFormat.date(reviewDate))"
        }
        return "Finalized"
    }
}

// MARK: - Compact row (used in lists and pickers)

struct DecisionCompactRow: View {
    let decision: Decision
    var trailingText: String?
    var onTap: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            onTap()
        }) {
            HStack(spacing: 11) {
                Image(systemName: decision.category.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(POPColor.brandOrange)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(POPColor.warningSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text(decision.displayTitle)
                        .font(POPFont.bodyMedium)
                        .foregroundStyle(POPColor.ink)
                        .lineLimit(1)
                    Text(trailingText ?? "\(decision.categoryTitle) · \(decision.status.title)")
                        .font(POPFont.caption)
                        .foregroundStyle(POPColor.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(POPColor.inkTertiary)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(POPColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(POPColor.hairline, lineWidth: 1))
        }
        .buttonStyle(POPPressStyle())
    }
}
