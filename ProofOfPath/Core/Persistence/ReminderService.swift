//
//  ReminderService.swift
//  ProofOfPath
//
//  Real local notifications for decision deadlines, outcome reviews,
//  claim verification deadlines and follow-up tasks.
//

import Foundation
import UserNotifications

@MainActor
final class ReminderService {

    static let shared = ReminderService()

    private let center = UNUserNotificationCenter.current()

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Returns true when notifications may be scheduled.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            await refreshAuthorizationStatus()
            return false
        }
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    /// Rebuilds the whole schedule from the current data.
    func reschedule(decisions: [Decision], settings: AppSettings) async {
        cancelAll()
        guard settings.remindersEnabled else { return }
        await refreshAuthorizationStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        let leadDays = max(0, settings.reminderLeadDays)
        var scheduled = 0
        let limit = 60   // iOS allows 64 pending requests per app.

        for decision in decisions where decision.status != .archived {

            // 1. Decision deadline
            if let deadline = decision.deadline,
               decision.status == .active || decision.status == .draft,
               scheduled < limit {
                if let fireDate = Calendar.current.date(byAdding: .day, value: -leadDays, to: deadline),
                   fireDate > Date() {
                    schedule(
                        id: "deadline-\(decision.id.uuidString)",
                        title: "Deadline approaching",
                        body: "“\(decision.displayTitle)” is due \(POPFormat.date(deadline)).",
                        date: fireDate
                    )
                    scheduled += 1
                }
            }

            // 2. Outcome review
            if decision.status == .finalized,
               let final = decision.finalDecision, final.isDraft == false,
               decision.outcomeReview?.isComplete != true,
               final.outcomeReviewDate > Date(),
               scheduled < limit {
                schedule(
                    id: "review-\(decision.id.uuidString)",
                    title: "Outcome review due",
                    body: "Time to compare what you expected with what actually happened for “\(decision.displayTitle)”.",
                    date: final.outcomeReviewDate
                )
                scheduled += 1
            }

            // 3. Claim verification deadlines
            for claim in decision.claims where claim.status.isOpen {
                guard let deadline = claim.verificationDeadline, deadline > Date(), scheduled < limit else { continue }
                schedule(
                    id: "claim-\(claim.id.uuidString)",
                    title: "Claim still unverified",
                    body: "“\(claim.displayText.popTruncated(60))” — verification was due today.",
                    date: deadline
                )
                scheduled += 1
            }

            // 4. Follow-up tasks
            for task in decision.followUpTasks where !task.isDone {
                guard let due = task.dueDate, due > Date(), scheduled < limit else { continue }
                schedule(
                    id: "task-\(task.id.uuidString)",
                    title: "Follow-up due",
                    body: task.title.popTruncated(80),
                    date: due
                )
                scheduled += 1
            }

            // 5. Risk review dates
            for risk in decision.risks where risk.state == .open {
                guard let reviewDate = risk.reviewDate, reviewDate > Date(), scheduled < limit else { continue }
                schedule(
                    id: "risk-\(risk.id.uuidString)",
                    title: "Risk review due",
                    body: "\(risk.displayTitle) — \(risk.category.title)",
                    date: reviewDate
                )
                scheduled += 1
            }
        }
    }

    private func schedule(id: String, title: String, body: String, date: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Fire at 09:00 on the target day, or immediately at the given time if that
        // has already passed today.
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = 9
        components.minute = 0

        guard let fireDate = Calendar.current.date(from: components), fireDate > Date() else { return }

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
            repeats: false
        )
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func pendingCount() async -> Int {
        await center.pendingNotificationRequests().count
    }
}
