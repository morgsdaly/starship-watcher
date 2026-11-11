import Foundation

/// The viewer's own liftoff call, made while watching the stream. Launch Library's status can lag
/// the pad by minutes; this starts the mission clock at the moment they tapped. Stored in the app
/// group so the widget and Live Activity follow it too.
enum ManualLiftoff {
    private static let flightKey = "manualLiftoffFlightID"
    private static let dateKey = "manualLiftoffDate"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedAppGroup.identifier) ?? .standard
    }

    static func mark(flightID: String, at date: Date = .now) {
        defaults.set(flightID, forKey: flightKey)
        defaults.set(date, forKey: dateKey)
    }

    static func clear() {
        defaults.removeObject(forKey: flightKey)
        defaults.removeObject(forKey: dateKey)
    }

    static func date(for flightID: String) -> Date? {
        guard defaults.string(forKey: flightKey) == flightID else { return nil }
        return defaults.object(forKey: dateKey) as? Date
    }
}

extension StarshipFlight {
    /// True on a flight returned by `applyingManualLiftoff()`.
    var hasManualLiftoff: Bool {
        launchDate != nil && launchDate == ManualLiftoff.date(for: id)
    }

    /// The mark, while it is still believable: Launch Library hasn't confirmed liftoff itself, and
    /// hasn't moved the flight more than two hours from it (a mistaken tap before a scrub).
    private var manualLiftoffDate: Date? {
        guard !status.confirmsLiftoff, let launchDate, let mark = ManualLiftoff.date(for: id),
              abs(launchDate.timeIntervalSince(mark)) < 2 * 60 * 60 else { return nil }
        return mark
    }

    /// In flight from the marked moment. Once Launch Library confirms, its own time takes over.
    func applyingManualLiftoff() -> StarshipFlight {
        guard let mark = manualLiftoffDate else { return self }
        var flight = self
        flight.launchDate = mark
        flight.status = LaunchStatus(name: "Launch in Flight")
        return flight
    }
}
