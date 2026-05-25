import Foundation
import UserNotifications

/// Observable state for routing a notification tap to a specific technique
/// in BreathHomeView. Set by NotificationDelegate and consumed by the view.
@MainActor
@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()
    private init() {}
    var pendingTechnique: String?
}

/// Schedules and cancels daily reminder notifications via UNUserNotificationCenter.
/// Authorization is requested on the first schedule call; a denial is surfaced
/// through authorizationStatus() so the UI can show the Settings redirect.
final class ReminderScheduler {
    static let shared = ReminderScheduler()
    private init() {}
    private let center = UNUserNotificationCenter.current()

    /// Replace the current reminder schedule with new times.
    /// No-ops silently if the user has denied notification permission.
    @MainActor
    func schedule(times: [DateComponents]) async {
        let granted = await requestAuthorization()
        guard granted else { return }
        await clear()
        let pool = availableTechniqueNames()
        for (index, time) in times.enumerated() {
            let name = pool.isEmpty ? "Box Breath" : pool[index % pool.count]
            let content = UNMutableNotificationContent()
            content.title = "Niyora"
            content.body = "Time to check in — \(name) is ready."
            content.sound = .default
            content.userInfo = ["technique": name]
            let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
            let req = UNNotificationRequest(
                identifier: "niyora.reminder.\(index)",
                content: content,
                trigger: trigger
            )
            try? await center.add(req)
        }
    }

    /// Cancel all pending Niyora reminder notifications.
    func clear() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .filter { $0.identifier.hasPrefix("niyora.reminder.") }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Current pending Niyora reminder requests.
    func pending() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix("niyora.reminder.") }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    private func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    @MainActor
    private func availableTechniqueNames() -> [String] {
        let count = LocalSessionStore.completedCount()
        let tier = Tier.current(completedSessions: count)
        let names = unlockedTechniques(tier: tier).map(\.name)
        return names.isEmpty ? allTechniques.prefix(1).map(\.name) : names
    }
}

/// UNUserNotificationCenterDelegate. Registered in NiyoraCompanionApp.init()
/// so notification taps received on cold launch are not missed.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    private override init() { super.init() }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let name = response.notification.request.content.userInfo["technique"] as? String
        Task { @MainActor in
            NotificationRouter.shared.pendingTechnique = name
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
