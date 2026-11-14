import Foundation

/// A term's plain-English meaning.
struct Explainer {
    let title: String
    let message: String
}

/// What the main clock shows.
enum FlightClock: Equatable {
    /// Soft date: never ticks.
    case net(String)
    case countdown(Date)
    /// Past NET unconfirmed: a hold or a late launch, not T+.
    case awaitingLiftoff
    case elapsed(Date)
}

extension StarshipFlight {
    func clock(now: Date) -> FlightClock {
        guard hasFirmDate, let launchDate else { return .net(netText) }
        if launchDate > now { return .countdown(launchDate) }
        return hasLiftedOff(now: now) ? .elapsed(launchDate) : .awaitingLiftoff
    }

    /// "Starship | Flight 15" -> "Flight 15". The vehicle is implied everywhere in this app.
    var shortName: String {
        guard let range = name.range(of: " | ") else { return name }
        return String(name[range.upperBound...])
    }

    /// T-3h to T+2h around a firm NET: when Launch polls and a stream may be called live.
    func isInActiveWindow(now: Date = .now) -> Bool {
        guard hasFirmDate, let launchDate else { return false }
        return now >= launchDate.addingTimeInterval(-3 * 60 * 60) && now <= launchDate.addingTimeInterval(2 * 60 * 60)
    }

    /// How often to ask Launch Library while the app is open. Nil outside the active window.
    /// The free tier allows ~15 requests/hour, so the budget goes where a minute matters:
    /// every 60s from T-2m until liftoff is confirmed (or T+6m), sparse in the hour either side.
    func pollInterval(now: Date = .now) -> TimeInterval? {
        guard isInActiveWindow(now: now), let launchDate else { return nil }
        if status.isFinal { return 15 * 60 }
        if status.confirmsLiftoff { return 5 * 60 }
        let sinceNET = now.timeIntervalSince(launchDate)
        if sinceNET >= -Self.burstLead, sinceNET <= 6 * 60 { return 60 }
        return abs(sinceNET) <= 60 * 60 ? 12 * 60 : 6 * 60
    }

    /// Seconds to wait before the next poll: the interval, cut short so the burst starts on time.
    func nextPollDelay(now: Date = .now) -> TimeInterval? {
        guard let interval = pollInterval(now: now), let launchDate else { return nil }
        let untilBurst = launchDate.addingTimeInterval(-Self.burstLead).timeIntervalSince(now)
        return untilBurst > 0 ? min(interval, untilBurst) : interval
    }

    private static let burstLead: TimeInterval = 2 * 60

    /// The viewer can call liftoff from a minute before NET until the status catches up.
    func canMarkLiftoff(now: Date = .now) -> Bool {
        guard hasFirmDate, !isMock, !status.confirmsLiftoff, let launchDate else { return false }
        return now >= launchDate.addingTimeInterval(-60) && isInActiveWindow(now: now)
    }

    /// From T-10m to the last planned event the screen stays on: nobody wants to unlock at Max Q.
    func keepsScreenAwake(now: Date = .now) -> Bool {
        guard hasFirmDate, !status.isFinal, !status.isHoldOrTBD, let launchDate else { return false }
        let end = hasLiftedOff(now: now)
            ? (timeline.compactMap(\.targetDate).max() ?? launchDate).addingTimeInterval(2 * 60)
            : launchDate.addingTimeInterval(15 * 60)
        return now >= launchDate.addingTimeInterval(-10 * 60) && now <= end
    }

    /// "Window closes 9:30 PM", or a live "Window closes in 42:10" once NET has passed without
    /// liftoff. Nil for an instantaneous window, a soft date, or after liftoff.
    func windowText(now: Date, usesUTC: Bool) -> String? {
        guard hasFirmDate, !status.confirmsLiftoff, let launchDate, let windowEnd,
              windowEnd.timeIntervalSince(launchDate) >= 60 else { return nil }
        if now >= launchDate {
            guard let remaining = Countdown.remaining(to: windowEnd, now: now) else { return "Window closed" }
            return "Window closes in \(remaining)"
        }
        let style = Date.FormatStyle(timeZone: usesUTC ? .gmt : .current).hour().minute()
        return "Window closes \(windowEnd.formatted(style))" + (usesUTC ? " UTC" : "")
    }

    /// Other streams once the launch is close: independent commentary alongside the official feed.
    func otherStreams(now: Date = .now) -> [FlightStream] {
        guard isInActiveWindow(now: now), let streams else { return [] }
        return streams.filter { $0.url != webcastURL }
    }

    func isLive(now: Date = .now) -> Bool {
        webcastLive && isInActiveWindow(now: now)
    }

    /// Stream link once the launch is close. Launch Library can list one days ahead.
    func liveStreamURL(now: Date = .now) -> URL? {
        isInActiveWindow(now: now) ? webcastURL : nil
    }

    /// Only soft dates read "NET".
    var clockExplainer: Explainer? {
        guard !hasFirmDate, launchDate != nil else { return nil }
        return Explainer(title: "No Earlier Than", message: "The earliest this flight could launch. The date often moves later.")
    }

    /// "NET Nov 13", or only as much as Launch Library knows: "NET Jun 2027", "NET Q2 2027", "NET 2028".
    /// Placeholder dates are midnight UTC, so local time could show the wrong day.
    var netText: String {
        guard let launchDate else { return "Date TBD" }
        let utc = Date.FormatStyle(timeZone: .gmt)
        let year = launchDate.formatted(utc.year())
        switch netPrecision {
        case "Q1", "Q2", "Q3", "Q4", "H1", "H2":
            return "NET \(netPrecision ?? "") \(year)"
        case "Y":
            return "NET \(year)"
        case "FY":
            return "NET FY\(year)"
        case "DEC":
            return "NET \(year.dropLast())0s"
        default:
            var style = utc.month(.abbreviated)
            if netPrecision != "M" {
                style = style.day()
            }
            if !Calendar.current.isDate(launchDate, equalTo: .now, toGranularity: .year) {
                style = style.year()
            }
            return "NET \(launchDate.formatted(style))"
        }
    }

    /// "Today", "Tomorrow", "In 3 days", by the viewer's own calendar: launch day at the pad is
    /// often a different date at home. Nil beyond a week, once passed, or for a soft date.
    func relativeDay(now: Date = .now) -> String? {
        guard hasFirmDate, let launchDate, launchDate > now else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(launchDate) { return "Today" }
        if calendar.isDateInTomorrow(launchDate) { return "Tomorrow" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: launchDate)).day ?? 0
        return (2...6).contains(days) ? "In \(days) days" : nil
    }

    /// For Siri: one or two sentences that stand on their own.
    func spokenSummary(now: Date = .now) -> String {
        guard hasFirmDate, let launchDate else {
            return launchDate == nil
                ? "\(shortName) has no launch date yet."
                : "\(shortName) has no firm launch time yet. The target is \(netText.replacing("NET ", with: "no earlier than "))."
        }
        if status.isFinal { return "\(shortName) has flown. \(status.displayName)." }
        if status.confirmsLiftoff { return "\(shortName) is in flight." }
        if launchDate <= now { return "\(shortName) is past its target time and waiting for liftoff. Status: \(status.displayName)." }
        let day = relativeDay(now: now).map { "\($0.lowercased()), " } ?? ""
        return "\(shortName) is targeting \(day)\(launchDate.launchText(usesUTC: false)), from \(placeText.replacing(" · ", with: ", ")). Status: \(status.displayName)."
    }

    /// Firm flights get date and time, the rest a NET date.
    func dateText(usesUTC: Bool, year: Bool = false) -> String {
        guard hasFirmDate, let launchDate else { return netText }
        return launchDate.launchText(usesUTC: usesUTC, year: year)
    }

    /// "Starbase · Pad 2"
    var placeText: String {
        let site = launchSite.components(separatedBy: ",").first ?? launchSite
        return "\(site) · \(padName)"
    }

    var shareText: String {
        var lines = [name]
        if let launchDate {
            lines.append(hasFirmDate ? "Targeting \(launchDate.formatted(date: .abbreviated, time: .shortened))" : netText)
        }
        lines.append("\(padName), \(launchSite)")
        lines.append("via Starship Watcher")
        return lines.joined(separator: "\n")
    }
}

extension Date {
    func launchText(usesUTC: Bool, year: Bool = false) -> String {
        // The weekday matters far from the pad: launch day in Texas is often tomorrow elsewhere.
        var style = Date.FormatStyle(timeZone: usesUTC ? .gmt : .current)
            .weekday(.abbreviated).month(.abbreviated).day().hour().minute()
        if year { style = style.year() }
        return formatted(style) + (usesUTC ? " UTC" : "")
    }
}

extension FlightVehicle {
    /// "First flight", "Flight 2 · Landing failed". Nil when there's nothing to say.
    var statusText: String? {
        let flight = flightNumber.map { $0 == 1 ? "First flight" : "Flight \($0)" }
        let landing = landingSucceeded.map { $0 ? "Landing success" : "Landing failed" }
        let parts = [flight, landing].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension FlightEvent {
    /// "T-0:39:00", "T+0:02:24".
    var offsetText: String {
        let total = Int(abs(offset))
        let sign = offset < 0 ? "T-" : "T+"
        return String(format: "%@%d:%02d:%02d", sign, total / 3600, total / 60 % 60, total % 60)
    }
}
