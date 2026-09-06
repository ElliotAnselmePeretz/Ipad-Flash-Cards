import Foundation
import UserNotifications
import FlashcardsCore

/// Study reminders.
///
/// Two kinds, deliberately. Plan reminders fire at the times you chose and say what is
/// waiting. Decay reminders fire when a deck has gone quiet long enough that the app
/// expects you to have started losing it — which is the moment a reminder is actually
/// worth something.
@Observable
final class StudyReminders {

    enum Authorization: Equatable {
        case notAsked, allowed, denied
    }

    private(set) var authorization: Authorization = .notAsked

    private let center = UNUserNotificationCenter.current()
    private let planPrefix = "plan-"
    private let decayPrefix = "decay-"

    // MARK: - Permission

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorization = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: .allowed
        case .denied: .denied
        default: .notAsked
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        authorization = granted ? .allowed : .denied
        return granted
    }

    // MARK: - Scheduling

    /// Replaces every scheduled reminder with ones matching the current plan. Called after
    /// any change, so what is scheduled always matches what the app is showing.
    func reschedule(plan: StudyPlan, decksNeedingAttention: [DeckWorkload],
                    settings: StudyPlanSettings) async {
        await cancelAll()
        guard settings.isEnabled, authorization == .allowed else { return }

        for session in plan.sessions {
            var components = DateComponents()
            components.hour = session.hour
            components.minute = session.minute

            let content = UNMutableNotificationContent()
            if let goal = plan.goal {
                content.title = "\(goal.name) — \(goal.countdown())"
            } else {
                content.title = "Time to review"
            }
            content.body = session.cardCount == 1
                ? "1 card, about a minute."
                : "\(session.cardCount) cards, about \(session.estimatedMinutes) minutes."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: planPrefix + session.id.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            )
            try? await center.add(request)
        }

        // One decay reminder, for the worst deck. Several at once would be nagging.
        if let worst = decksNeedingAttention.first {
            let content = UNMutableNotificationContent()
            content.title = "\(worst.name) is fading"
            content.body = "You're down to about \(Int(worst.recallProbability * 100))% on this one."
            content.sound = .default

            var components = DateComponents()
            components.hour = settings.slots.first?.hour ?? 9
            components.minute = settings.slots.first?.minute ?? 0

            let request = UNNotificationRequest(
                identifier: decayPrefix + worst.id.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier)
            .filter { $0.hasPrefix(planPrefix) || $0.hasPrefix(decayPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func pendingCount() async -> Int {
        await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(planPrefix) || $0.identifier.hasPrefix(decayPrefix) }
            .count
    }
}
