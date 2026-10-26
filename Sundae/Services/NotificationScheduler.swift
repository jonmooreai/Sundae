import Foundation
import UserNotifications

/// Local scheduling for the two Sunday reminders. Everything else in the notification
/// table arrives through APNs from the server once it exists.
///
/// Nothing here ever mentions what is in the feed. Sunday is the only prompt.
enum NotificationScheduler {
    private static let sundayID = "sunday.reminder"
    private static let lastCallID = "sunday.lastcall"

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Shows iOS's notification prompt if this phone has never answered it, and waits for the
    /// answer. Asked only where the reason is on screen: onboarding, or a switch in Settings.
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Weekly Sunday 9:00 am reminder, and Sunday 8:00 pm last call. Local time; the trigger
    /// follows the device's zone automatically. `postedUntil` is the end of a week already posted:
    /// no last call comes before it, so posting in the morning never earns one that evening.
    static func scheduleSundayReminders(reminder: Bool, lastCall: Bool, postedUntil: Date? = nil) {
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
            var trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            if let postedUntil, postedUntil > Date(),
               let next = Calendar.current.nextDate(after: postedUntil, matching: components, matchingPolicy: .nextTime) {
                // Just the Sunday after; the weekly one comes back the next time Sundae opens.
                let once = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: next)
                trigger = UNCalendarNotificationTrigger(dateMatching: once, repeats: false)
            }
            center.add(UNNotificationRequest(identifier: lastCallID, content: content, trigger: trigger))
        }
    }

    /// Signed out: this phone stops reminding anyone until someone signs in again.
    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [sundayID, lastCallID])
        center.removeDeliveredNotifications(withIdentifiers: [sundayID, lastCallID])
    }

    /// Once the dump is posted the last call for this Sunday is pointless. Remove the delivered
    /// copy and skip this week's; it is re-armed by `scheduleSundayReminders` on next launch.
    static func cancelLastCallForThisWeek() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [lastCallID])
        center.removeDeliveredNotifications(withIdentifiers: [lastCallID])
    }
}
