import Foundation
import UserNotifications

/// A single repeating local reminder. Permission is requested only when the
/// student turns the reminder on.
enum TMUAReminderScheduler {
    static let identifier = "tmua.daily-study-reminder"

    static func requestAndSchedule(minutes: Int, completion: @escaping @MainActor (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted { schedule(minutes: minutes) }
            Task { @MainActor in completion(granted) }
        }
    }

    static func schedule(minutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Time for TMUA practice"
        content.body = "Your plan for today is ready in Revisr."
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
