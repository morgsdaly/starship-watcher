import Foundation
import UserNotifications
#if canImport(ActivityKit)
import ActivityKit
#endif

struct NotificationScheduler {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Replaces all pending reminders. At most three per launch: the day before, the Live Activity
    /// pin prompt (if enabled), and webcast time. The Live Activity covers everything in between.
    func sync(flight: StarshipFlight?) async {
        // Only this scheduler uses local notifications. Clearing first also drops reminders for a flight
        // that slipped, lost its firm date or stopped being next, and everything when switched off.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        // A placeholder date would promise a launch nobody has scheduled. Checked before asking
        // permission, so the system prompt first appears when there is a launch to be reminded of.
        guard Self.isEnabled, let flight, flight.hasFirmDate, await requestAuthorization() else { return }

        schedule(title: "Starship launch tomorrow", body: flight.shortName, date: flight.launchDate?.addingTimeInterval(-24 * 60 * 60), identifier: "\(flight.id)-24h")
        if let liveLead = liveActivityLead, !hasLiveActivity(for: flight) {
            // Opening the app from this starts the Live Activity if iOS didn't let it start in the background.
            let hours = Int(liveLead / 3600)
            schedule(title: "Starship launch in \(hours) hour\(hours == 1 ? "" : "s")", body: "Tap to pin the \(flight.shortName) countdown to your Lock Screen.", date: flight.launchDate?.addingTimeInterval(-liveLead), identifier: "\(flight.id)-live")
        }
        // Not `windowStart`: for Starship it usually equals NET, so the reminder landed at liftoff.
        schedule(title: "Starship webcast starting soon", body: "\(flight.shortName) launches in about 30 minutes.", date: flight.launchDate?.addingTimeInterval(-30 * 60), identifier: "\(flight.id)-stream")
    }

    /// Tells the user what a background refresh found: a new date, a hold, Go, liftoff, the result.
    /// Never prompts, and stays quiet while the Live Activity is up, which alerts for itself.
    func notifyChange(from old: StarshipFlight?, to new: StarshipFlight?) async {
        guard Self.isEnabled, let old, let new, old.id == new.id, !hasLiveActivity(for: new),
              let body = Self.changeText(from: old, to: new) else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Starship \(new.shortName)"
        content.body = body
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "\(new.id)-change-\(Date.now.timeIntervalSince1970)", content: content, trigger: nil))
    }

    /// Slips smaller than this aren't news: Launch Library nudges NET often on launch day.
    private static let slipThreshold: TimeInterval = 15 * 60

    private static func changeText(from old: StarshipFlight, to new: StarshipFlight) -> String? {
        if new.status.isFinal, !old.status.isFinal { return new.status.displayName }
        if new.status.confirmsLiftoff, !old.status.confirmsLiftoff { return "Liftoff!" }
        if new.status.confirmsLiftoff { return nil }
        if old.hasFirmDate, !new.hasFirmDate { return "Launch delayed. \(new.netText)." }
        if new.hasFirmDate, let date = new.launchDate {
            let text = date.launchText(usesUTC: false)
            guard old.hasFirmDate, let oldDate = old.launchDate else { return "Launch time set: \(text)." }
            if abs(date.timeIntervalSince(oldDate)) >= slipThreshold { return "New target: \(text)." }
        }
        if new.status.isHold, !old.status.isHold { return "The countdown is on hold." }
        if new.status.isGo, !old.status.isGo { return "Go for launch." }
        return nil
    }

    private func schedule(title: String, body: String, date: Date?, identifier: String) {
        guard let date, date > .now.addingTimeInterval(30) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private var liveActivityLead: TimeInterval? {
        #if canImport(ActivityKit)
        StarshipActivityController.isEnabled ? StarshipActivityController.lead : nil
        #else
        nil
        #endif
    }

    private func hasLiveActivity(for flight: StarshipFlight) -> Bool {
        #if canImport(ActivityKit)
        StarshipActivityController.liveActivities.contains { $0.attributes.flightID == flight.id }
        #else
        false
        #endif
    }
}
