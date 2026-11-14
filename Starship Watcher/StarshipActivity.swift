import Foundation

#if canImport(ActivityKit)
@preconcurrency import ActivityKit

enum CountdownStartError: Error, CustomLocalizedStringResourceConvertible {
    case activitiesDisabled
    case launchTBD
    case tooEarly

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .activitiesDisabled: "Live Activities are turned off for Starship Watcher in iOS Settings."
        case .launchTBD: "The launch time is TBD."
        case .tooEarly: "The countdown can start from T-4h."
        }
    }
}

struct StarshipActivityController {
    /// Earliest manual start. iOS ends a Live Activity 8 hours after it starts, so a start at T-4h
    /// still leaves room for the flight (about an hour) and a few hours of holds.
    static let maxLead: TimeInterval = 4 * 60 * 60

    /// Activities still running (ended ones linger in `activities` until dismissed).
    static var liveActivities: [Activity<StarshipFlightAttributes>] {
        Activity<StarshipFlightAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    static var hasLiveActivity: Bool {
        !liveActivities.isEmpty
    }

    /// Scheduled with iOS to start by themselves at the lead time, app open or not.
    static var pendingActivities: [Activity<StarshipFlightAttributes>] {
        Activity<StarshipFlightAttributes>.activities.filter { $0.activityState == .pending }
    }

    /// Running now, or booked to start: either way the countdown will reach the Lock Screen.
    static func hasActivity(for flight: StarshipFlight) -> Bool {
        (liveActivities + pendingActivities).contains { $0.attributes.flightID == flight.id }
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "liveActivityEnabled") as? Bool ?? true
    }

    /// How long before liftoff the activity starts by itself. Five hours of slack under the 8 hour cap.
    static let lead: TimeInterval = 3 * 60 * 60

    /// How long a finished activity stays on the Lock Screen showing its result.
    private static let resultLinger: TimeInterval = 30 * 60
    private static let scrubLinger: TimeInterval = 60 * 60

    static func windowStart(for launchDate: Date) -> Date {
        launchDate.addingTimeInterval(-lead)
    }

    /// Updates a running activity, or starts one once the lead window opens.
    /// `canStart` is false in the background, where ActivityKit won't request new activities.
    func sync(flight: StarshipFlight?, canStart: Bool) async {
        guard let flight else {
            await endAll()
            return
        }

        if let existing = Self.liveActivities.first(where: { $0.attributes.flightID == flight.id }) {
            await endAll(except: existing.id)
            if let launchDate = flight.launchDate, launchDate.timeIntervalSinceNow > Self.maxLead {
                // Stood down for the day. Say so and leave it up for a while, rather than vanishing.
                let target = flight.hasFirmDate ? "New target \(launchDate.launchText(usesUTC: false))" : flight.netText
                await finish(existing, for: flight, headline: "Scrubbed", stage: target, linger: Self.scrubLinger)
            } else if flight.status.isFinal {
                let headline = flight.status.isSuccess ? "Mission complete" : flight.status.shortName
                await finish(existing, for: flight, headline: headline, stage: nil, linger: Self.resultLinger)
            } else {
                // Otherwise keep it through holds and TBD so the status change stays visible.
                await update(existing, for: flight)
            }
            return
        }

        // A booking is only good while the flight still has the time it was made for.
        let target = Self.isEnabled && Self.canStart(flight) ? flight.launchDate : nil
        if let pending = Self.pendingActivities.first(where: { $0.attributes.flightID == flight.id }),
           let target, pending.content.state.targetDate == target, Date.now < Self.windowStart(for: target) {
            await endAll(except: pending.id)
            return
        }

        await endAll()
        guard canStart, let launchDate = target else { return }
        // A mock starts right away, whatever its lead.
        if flight.isMock || Date.now >= Self.windowStart(for: launchDate) {
            try? request(for: flight)
        } else {
            try? schedule(flight, launchDate: launchDate)
        }
    }

    /// Books the activity with iOS, which starts it at the lead time even if the app is never
    /// opened again. Before this the start depended on someone tapping a reminder at T-3h.
    private func schedule(_ flight: StarshipFlight, launchDate: Date) throws {
        let start = Self.windowStart(for: launchDate)
        _ = try Activity.request(
            attributes: attributes(for: flight),
            content: content(contentState(for: flight, now: start)),
            pushType: nil,
            style: .standard,
            alertConfiguration: AlertConfiguration(
                title: "\(flight.shortName) countdown",
                body: "Liftoff in \(Int(Self.lead / 3600)) hours. The countdown is on your Lock Screen.",
                sound: .default
            ),
            start: start
        )
    }

    /// Firm, not over, and not long gone: opening the app after a flight must not pin a new countdown.
    private static func canStart(_ flight: StarshipFlight) -> Bool {
        guard flight.hasFirmDate, !flight.status.isFinal, let launchDate = flight.launchDate else { return false }
        return launchDate.timeIntervalSinceNow > -2 * 60 * 60
    }

    /// Manual start from the widget button, control or Shortcuts. Ignores the in-app toggle and lead setting.
    func startNow(flight: StarshipFlight) async throws {
        if let existing = Self.liveActivities.first(where: { $0.attributes.flightID == flight.id }) {
            await update(existing, for: flight)
            return
        }
        // endAll below also cancels a booking, which this start replaces.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw CountdownStartError.activitiesDisabled }
        guard Self.canStart(flight), let launchDate = flight.launchDate else { throw CountdownStartError.launchTBD }
        guard launchDate.timeIntervalSinceNow <= Self.maxLead else { throw CountdownStartError.tooEarly }

        await endAll()
        try request(for: flight)
    }

    private func request(for flight: StarshipFlight) throws {
        _ = try Activity.request(attributes: attributes(for: flight), content: content(contentState(for: flight)), pushType: nil)
    }

    private func attributes(for flight: StarshipFlight) -> StarshipFlightAttributes {
        StarshipFlightAttributes(
            flightID: flight.id,
            flightName: flight.name,
            vehicle: flight.vehicle,
            launchSite: flight.launchSite
        )
    }

    /// Ends running activities and cancels booked ones. Finished ones showing a result are left
    /// to their dismissal time unless `includingEnded` clears the Lock Screen completely.
    func endAll(except keptID: String? = nil, includingEnded: Bool = false) async {
        for activity in Activity<StarshipFlightAttributes>.activities where activity.id != keptID {
            let isLive = [.active, .stale, .pending].contains(activity.activityState)
            guard isLive || includingEnded else { continue }
            await activity.end(ActivityContent(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
        }
    }

    private func update(_ activity: Activity<StarshipFlightAttributes>, for flight: StarshipFlight) async {
        let old = activity.content.state
        let new = contentState(for: flight)
        guard old != new || activity.activityState == .stale else { return }

        if let alert = alert(from: old, to: new, flightName: flight.name) {
            await activity.update(content(new), alertConfiguration: alert)
        } else {
            await activity.update(content(new))
        }
    }

    /// Shows the outcome, alerts once, and leaves it on the Lock Screen for `linger`.
    private func finish(_ activity: Activity<StarshipFlightAttributes>, for flight: StarshipFlight, headline: String, stage: String?, linger: TimeInterval) async {
        let state = contentState(for: flight, headline: headline, stage: stage)
        let final = ActivityContent(state: state, staleDate: nil)
        let body = [headline, stage].compactMap { $0 }.joined(separator: ". ")
        await activity.update(final, alertConfiguration: AlertConfiguration(title: "\(flight.name) update", body: "\(body)", sound: .default))
        await activity.end(final, dismissalPolicy: .after(.now.addingTimeInterval(linger)))
    }

    /// Stale just after the next planned event: iOS redraws the activity then, which moves the
    /// countdowns on to the following event without the app running. Two seconds late, so the
    /// redraw is safely past the event rather than level with it.
    private func content(_ state: StarshipFlightAttributes.ContentState) -> ActivityContent<StarshipFlightAttributes.ContentState> {
        ActivityContent(state: state, staleDate: state.upcoming?.first?.date.addingTimeInterval(2))
    }

    /// Slips smaller than this update the countdown silently. Launch Library nudges NET often on
    /// launch day, and corrects it to the real liftoff time afterwards.
    static let alertSlipThreshold: TimeInterval = 15 * 60
    /// Minimum gap between alerts, except for liftoff and the final result.
    static let alertCooldown: TimeInterval = 15 * 60
    private static let lastAlertKey = "liveActivityLastAlert"

    /// Lights up the Lock Screen only for changes worth a sound: hold/TBD, a real slip, liftoff.
    /// Everything else updates the activity silently. Results and scrubs alert from `finish`.
    private func alert(from old: StarshipFlightAttributes.ContentState, to new: StarshipFlightAttributes.ContentState, flightName: String) -> AlertConfiguration? {
        let oldKind = StatusKind(old.status)
        let newKind = StatusKind(new.status)

        let body: String
        if newKind != oldKind, newKind.isFinal || newKind == .inFlight {
            body = newKind == .inFlight ? "Liftoff!" : "Status: \(new.status)"
        } else if new.targetDate == nil, old.targetDate != nil {
            body = "Launch time is now TBD."
        } else if newKind != oldKind, newKind == .hold || newKind == .tbd {
            body = "Status: \(new.status)"
        } else if newKind == .go, oldKind == .hold || oldKind == .tbd {
            body = "Countdown resumed."
        } else if !newKind.isAfterLiftoff, let oldDate = old.targetDate, let newDate = new.targetDate,
                  abs(oldDate.timeIntervalSince(newDate)) >= Self.alertSlipThreshold {
            body = "New target: \(newDate.formatted(date: .abbreviated, time: .shortened))"
        } else {
            return nil
        }

        let defaults = UserDefaults.standard
        let urgent = newKind != oldKind && (newKind.isFinal || newKind == .inFlight)
        if !urgent, let last = defaults.object(forKey: Self.lastAlertKey) as? Date,
           Date.now.timeIntervalSince(last) < Self.alertCooldown {
            return nil
        }
        defaults.set(Date.now, forKey: Self.lastAlertKey)
        return AlertConfiguration(title: "\(flightName) update", body: "\(body)", sound: .default)
    }

    /// Without ActivityKit push the state only changes at sync points (foreground, BG refresh), so it
    /// carries the plan ahead and the widget counts down to it by itself. Stage changes never alert.
    /// `now` is the moment the state describes: the present, or the start time of a booked activity.
    private func contentState(for flight: StarshipFlight, now: Date = .now, headline: String? = nil, stage: String? = nil) -> StarshipFlightAttributes.ContentState {
        let liftedOff = flight.hasLiftedOff(now: now)
        return StarshipFlightAttributes.ContentState(
            phase: flight.currentEvent(now: now)?.phase.rawValue ?? "Countdown",
            status: flight.status.name,
            // A running activity whose date goes soft shows TBD, never a countdown to a placeholder.
            targetDate: flight.hasFirmDate ? flight.launchDate : nil,
            detail: flight.padName,
            stage: stage ?? flight.progress(now: now).title,
            liftoffConfirmed: liftedOff,
            headline: headline,
            upcoming: headline == nil ? upcoming(for: flight, liftedOff: liftedOff, now: now) : nil,
            phaseWindows: phaseWindows(for: flight)
        )
    }

    /// The next few planned events. Before liftoff only the count itself: flight events have no
    /// times worth showing until the rocket has left. None during a hold, when the plan is void.
    private func upcoming(for flight: StarshipFlight, liftedOff: Bool, now: Date) -> [StarshipFlightAttributes.Milestone] {
        guard flight.hasFirmDate, !flight.status.isHold else { return [] }
        return flight.timeline
            .compactMap { event -> StarshipFlightAttributes.Milestone? in
                guard let date = event.targetDate, date > now, liftedOff || event.offset <= 0 else { return nil }
                return StarshipFlightAttributes.Milestone(title: event.title, date: date, phase: event.phase.rawValue)
            }
            .prefix(8)
            .map { $0 }
    }

    /// Preflight runs from the automatic start to T0, ascent to staging, then both vehicles to
    /// their last planned event.
    private func phaseWindows(for flight: StarshipFlight) -> [StarshipFlightAttributes.PhaseWindow]? {
        guard flight.hasFirmDate, let launchDate = flight.launchDate else { return nil }
        let events = flight.timeline
        let dates = { (phase: FlightPhase) in events.filter { $0.phase == phase }.compactMap(\.targetDate) }
        guard let split = (dates(.booster) + dates(.ship)).min(), split > launchDate,
              let boosterEnd = dates(.booster).max(), let shipEnd = dates(.ship).max() else { return nil }
        let window = { (phase: FlightPhase, start: Date, end: Date) in
            StarshipFlightAttributes.PhaseWindow(phase: phase.rawValue, start: start, end: max(end, start.addingTimeInterval(1)))
        }
        return [
            window(.preflight, Self.windowStart(for: launchDate), launchDate),
            window(.ascent, launchDate, split),
            window(.booster, split, boosterEnd),
            window(.ship, split, shipEnd)
        ]
    }
}

/// Launch Library status names bucketed for alert decisions ("Go for Launch", "On Hold", ...).
private enum StatusKind {
    case go, tbc, tbd, hold, inFlight, success, failure, other

    init(_ status: String) {
        let value = status.lowercased()
        self = if value.contains("success") { .success }
        else if value.contains("fail") { .failure }
        else if value.contains("flight") || value.contains("progress") { .inFlight }
        else if value.contains("hold") { .hold }
        else if value.contains("determined") || value.contains("tbd") { .tbd }
        else if value.contains("confirmed") || value.contains("tbc") { .tbc }
        else if value.contains("go") { .go }
        else { .other }
    }

    var isFinal: Bool { self == .success || self == .failure }
    var isAfterLiftoff: Bool { self == .inFlight || isFinal }
}
#endif
