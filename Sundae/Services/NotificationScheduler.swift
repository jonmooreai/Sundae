import Foundation
import UserNotifications

/// Local scheduling for the two Sunday reminders. Everything else in the notification
/// table arrives through APNs from the server once it exists.
///
/// Nothing here ever mentions what is in the feed. Sunday is the only prompt.
enum NotificationScheduler {
    private static let sundayID = "sunday.reminder"
    private static let lastCallID = "sunday.lastcall"

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Weekly Sunday 9:00 am reminder, and Sunday 8:00 pm last call. Local time; the trigger
    /// follows the device's zone automatically.
    static func scheduleSundayReminders(reminder: Bool, lastCall: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [sundayID, lastCallID])

        if reminder {
            let content = UNMutableNotificationContent()
            content.title = "Sunday is here"
            content.body = "Post your week."
            content.sound = .default
            var components = DateComponents()
            components.weekday = 1
            components.hour = 9
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            center.add(UNNotificationRequest(identifier: sundayID, content: content, trigger: trigger))
        }
        if lastCall {
            let content = UNMutableNotificationContent()
            content.title = "Last call"
            content.body = "Your week closes at midnight."
            content.sound = .default
            var components = DateComponents()
            components.weekday = 1
            components.hour = 20
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            center.add(UNNotificationRequest(identifier: lastCallID, content: content, trigger: trigger))
        }
    }

    /// Once the dump is posted the last call for this Sunday is pointless. Remove the delivered
    /// copy and skip this week's; it is re-armed by `scheduleSundayReminders` on next launch.
    static func cancelLastCallForThisWeek() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [lastCallID])
        center.removeDeliveredNotifications(withIdentifiers: [lastCallID])
    }
}
