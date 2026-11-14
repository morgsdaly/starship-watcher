import Foundation

#if canImport(ActivityKit)
@preconcurrency import ActivityKit

/// The one definition of the Live Activity's data, compiled into both the app and the widget
/// extension. Two copies that drift apart fail to decode silently.
nonisolated struct StarshipFlightAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        let phase: String
        let status: String
        let targetDate: Date?
        let detail: String
        /// Current mission event ("Hot staging"). Optional so states from older builds still decode.
        var stage: String? = nil
        /// Liftoff confirmed by status or the viewer's mark. The T+ clock never runs without it.
        var liftoffConfirmed: Bool? = nil
        /// Replaces the clock once the activity is over: "Scrubbed", "Mission complete".
        var headline: String? = nil
        /// Planned events still ahead, soonest first. Without push the activity can't be told when
        /// each one passes, so it carries the plan and lets system-drawn timers count to them.
        var upcoming: [Milestone]? = nil
        /// When each phase of the rail starts and ends, for system-drawn progress.
        var phaseWindows: [PhaseWindow]? = nil
    }

    struct Milestone: Codable, Hashable, Sendable {
        let title: String
        let date: Date
        /// `FlightPhase` raw value.
        let phase: String
    }

    struct PhaseWindow: Codable, Hashable, Sendable {
        /// `FlightPhase` raw value.
        let phase: String
        let start: Date
        let end: Date
    }

    let flightID: String
    let flightName: String
    let vehicle: String
    let launchSite: String
}

/// Read by the widget's views. Main actor, because the app target isolates `LaunchStatus` there.
@MainActor
extension StarshipFlightAttributes.ContentState {
    var hasLiftedOff: Bool {
        liftoffConfirmed ?? LaunchStatus(name: status).confirmsLiftoff
    }

    /// What to count down to next: one event before liftoff, the next two during ascent, then
    /// one per vehicle once booster and ship fly apart. Two rows in flight, so that when one
    /// reaches zero between redraws the other is still counting.
    func nextEvents(now: Date) -> [StarshipFlightAttributes.Milestone] {
        guard headline == nil, let upcoming else { return [] }
        // A second's margin: a redraw landing on an event's own time must move past it,
        // not show it frozen at 0:00.
        let future = upcoming.filter { $0.date > now.addingTimeInterval(1) }
        guard hasLiftedOff else {
            // Liftoff itself is the main clock.
            return Array(future.filter { $0.phase == FlightPhase.preflight.rawValue }.prefix(1))
        }
        guard let first = future.first else { return [] }
        let split = [FlightPhase.booster.rawValue, FlightPhase.ship.rawValue]
        guard split.contains(first.phase) else { return Array(future.prefix(2)) }
        return split.compactMap { phase in future.first { $0.phase == phase } }
    }

    /// From a minute before NET the viewer can call liftoff themselves, ahead of Launch Library.
    func canMarkLiftoff(now: Date) -> Bool {
        guard headline == nil, !hasLiftedOff, let targetDate, !LaunchStatus(name: status).isTBD else { return false }
        return now >= targetDate.addingTimeInterval(-60) && now <= targetDate.addingTimeInterval(2 * 60 * 60)
    }
}
#endif
