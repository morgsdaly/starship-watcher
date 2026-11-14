import Foundation

/// Where a flight is against its planned timeline. Worked out from the clock and Launch Library
/// status, never telemetry, so screens label it an estimate.
struct MissionProgress: Equatable {
    /// "Hot staging", "On hold", "Launch Failure". Nil past NET with liftoff unconfirmed:
    /// every clock already reads "Awaiting liftoff", so a title would only repeat it.
    let title: String?
    let isAlert: Bool
    /// 0...1 per phase. Phases are equal steps, not time: preflight alone spans a day.
    let fills: [FlightPhase: Double]
    /// Next event, or one per vehicle once booster and ship separate.
    let upcoming: [FlightEvent]
}

extension StarshipFlight {
    func progress(now: Date) -> MissionProgress {
        let events = timeline
        // A placeholder date passing proves nothing, so soft dates mark no progress.
        let current = hasFirmDate ? currentEventIndex(in: events, now: now) : nil
        let reached = events.prefix((current ?? -1) + 1)
        // Between events a phase keeps filling towards its next one, but only while the clock is
        // really running: not in a hold, and not past NET with liftoff unconfirmed.
        let isRunning = current != nil && !status.isHold && !status.isFinal
            && (hasLiftedOff(now: now) || (launchDate ?? .distantPast) > now)
        let fills = Dictionary(uniqueKeysWithValues: FlightPhase.allCases.map { phase in
            let inPhase = events.filter { $0.phase == phase }
            let done = reached.count { $0.phase == phase }
            var steps = Double(done)
            if isRunning, done > 0, done < inPhase.count,
               let from = inPhase[done - 1].targetDate, let to = inPhase[done].targetDate, to > from {
                steps += min(max(now.timeIntervalSince(from) / to.timeIntervalSince(from), 0), 1)
            }
            return (phase, steps / Double(inPhase.count))
        })

        func stopped(_ title: String?, isAlert: Bool = false) -> MissionProgress {
            MissionProgress(title: title, isAlert: isAlert, fills: fills, upcoming: [])
        }

        if status.isAlert { return stopped(status.displayName, isAlert: true) }
        if status.isSuccess {
            let complete = Dictionary(uniqueKeysWithValues: FlightPhase.allCases.map { ($0, 1.0) })
            return MissionProgress(title: "Mission complete", isAlert: false, fills: complete, upcoming: [])
        }
        guard hasFirmDate, let launchDate else { return stopped("Awaiting date") }
        if status.isHold { return stopped("On hold") }
        if launchDate <= now, !hasLiftedOff(now: now) { return stopped(nil) }

        let remaining = events.dropFirst(reached.count)
        let upcoming: [FlightEvent]
        if let next = remaining.first, next.phase == .booster || next.phase == .ship {
            upcoming = [FlightPhase.booster, .ship].compactMap { phase in remaining.first { $0.phase == phase } }
        } else {
            upcoming = remaining.first.map { [$0] } ?? []
        }
        return MissionProgress(title: reached.last?.title ?? "Pre-count", isAlert: false, fills: fills, upcoming: upcoming)
    }
}
