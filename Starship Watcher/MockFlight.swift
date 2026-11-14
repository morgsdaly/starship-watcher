import Foundation

/// Where a mock flight starts on the timeline.
enum MockFlightMode: String, CaseIterable, Identifiable {
    case tenMinutesOut
    case liftoff

    var id: Self { self }

    var title: String {
        switch self {
        case .tenMinutesOut: "T-10m"
        case .liftoff: "Liftoff"
        }
    }

    /// Time until T0. Liftoff keeps a few seconds of Go, so the status change and alert still fire.
    fileprivate var lead: TimeInterval {
        switch self {
        // Long enough to watch the count, short enough to reach the flight in one sitting.
        case .tenMinutesOut: 10 * 60
        case .liftoff: 10
        }
    }
}

/// Test flight that replaces the next flight, running on the device clock in real time.
/// Only its T0 is stored, in the app group so the widget sees it too.
enum MockFlight {
    fileprivate static let id = "mock-flight"
    private static let launchDateKey = "mockFlightLaunchDate"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedAppGroup.identifier) ?? .standard
    }

    static func start(_ mode: MockFlightMode) {
        defaults.set(Date.now.addingTimeInterval(mode.lead), forKey: launchDateKey)
    }

    static func stop() {
        defaults.removeObject(forKey: launchDateKey)
    }

    static func current(now: Date = .now) -> StarshipFlight? {
        guard let launchDate = defaults.object(forKey: launchDateKey) as? Date else { return nil }
        return StarshipFlight(
            id: id,
            name: "Starship | Mock Flight",
            missionName: "Mock Flight",
            summary: "Test flight for the countdown, stages and Live Activity. Not a real launch.",
            vehicle: "Starship",
            status: status(launchDate: launchDate, now: now),
            launchDate: launchDate,
            windowStart: nil,
            windowEnd: nil,
            launchSite: "Starbase, Texas",
            padName: "Pad 2",
            probability: nil,
            imageURL: nil,
            webcastLive: true,
            sourceURL: nil,
            hasExactTime: true
        )
    }

    /// Follows Launch Library's status names through the flight.
    private static func status(launchDate: Date, now: Date) -> LaunchStatus {
        let splashdown = FlightEvent.standardTemplate(relativeTo: launchDate).last?.targetDate ?? launchDate
        if now >= splashdown { return LaunchStatus(name: "Launch Successful") }
        return LaunchStatus(name: now >= launchDate ? "Launch in Flight" : "Go for Launch")
    }
}

extension StarshipFlight {
    var isMock: Bool {
        id == MockFlight.id
    }
}
