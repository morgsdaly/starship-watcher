import ActivityKit
import WidgetKit
import SwiftUI

// `StarshipFlightAttributes` lives in the app folder and is compiled into both targets.

struct WidgetExtensionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StarshipFlightAttributes.self) { context in
            ActivityContentView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(Color.white)
                .widgetURL(context.attributes.url)
        } dynamicIsland: { context in
            let status = LaunchStatus(name: context.state.status)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 10) {
                        StarshipMark(color: status.markColor)
                            .frame(height: 30)
                        Text(context.attributes.shortName)
                            .caps(.caption, tracking: 1.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StatusBadge(status: status)
                        .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        ActivityClock(state: context.state, font: .title)
                        ActivityStage(state: context.state)
                        ActivityRail(state: context.state, showsLabels: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                CompactStatus(status: status)
            } compactTrailing: {
                CompactCountdown(state: context.state)
            } minimal: {
                StarshipMark(color: status.markColor)
                    .frame(height: 22)
            }
            .widgetURL(context.attributes.url)
            .keylineTint(Color.white.opacity(0.55))
        }
        // Apple Watch Smart Stack and CarPlay.
        .supplementalActivityFamilies([.small])
    }
}

/// The Lock Screen banner, or the compact layout the Watch and CarPlay ask for.
private struct ActivityContentView: View {
    let attributes: StarshipFlightAttributes
    let state: StarshipFlightAttributes.ContentState

    @Environment(\.activityFamily) private var activityFamily

    var body: some View {
        if activityFamily == .small {
            SmallActivity(attributes: attributes, state: state)
        } else {
            LockScreenActivity(attributes: attributes, state: state)
        }
    }
}

private struct SmallActivity: View {
    let attributes: StarshipFlightAttributes
    let state: StarshipFlightAttributes.ContentState

    var body: some View {
        let status = LaunchStatus(name: state.status)
        HStack(alignment: .center, spacing: 10) {
            StarshipMark(color: status.markColor, glows: false)
                .frame(height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(attributes.shortName) · \(status.shortName)")
                    .caps(.caption2, color: Theme.secondary, tracking: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                ActivityClock(state: state, font: .title3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

struct LockScreenActivity: View {
    let attributes: StarshipFlightAttributes
    let state: StarshipFlightAttributes.ContentState

    var body: some View {
        let status = LaunchStatus(name: state.status)
        HStack(alignment: .center, spacing: 18) {
            StarshipMark(color: status.markColor)
                .frame(height: 104)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text(attributes.shortName)
                        .caps(.footnote, tracking: 2)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    StatusBadge(status: status)
                }
                ActivityClock(state: state, font: .largeTitle)
                ActivityStage(state: state)
                ActivityRail(state: state)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { HorizonBackdrop(rise: 0.12) }
    }
}

/// The ship while things are on track; the status word when they aren't, so a hold still shows.
private struct CompactStatus: View {
    let status: LaunchStatus

    var body: some View {
        if status.isHoldOrTBD || status.isAlert {
            Text(status.shortName)
                .caps(.caption2, color: status.color, tracking: 1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else {
            StarshipMark(color: status.markColor)
                .frame(height: 22)
                .padding(.leading, 2)
        }
    }
}

/// Live Activities are rendered as snapshots, so `TimelineView` never ticks there.
/// `Text(timerInterval:)` / `.timer` are drawn by the system and update every second on their own.
private struct ActivityClock: View {
    let state: StarshipFlightAttributes.ContentState
    let font: Font

    var body: some View {
        let now = Date.now
        Group {
            if let headline = state.headline {
                // Over: the result, not a clock that runs on.
                Text(headline)
            } else if let targetDate = state.targetDate {
                if targetDate > now {
                    Text("T-\(Text(timerInterval: now...targetDate, countsDown: true))")
                } else if state.hasLiftedOff {
                    Text("T+\(Text(targetDate, style: .timer))")
                } else {
                    // Redrawn when the activity goes stale at the target date. NET passing isn't
                    // liftoff: the mission clock waits for the status or the viewer's mark.
                    Text("Awaiting liftoff")
                }
            } else {
                Text("Date TBD")
            }
        }
        .font(font.weight(.light).monospacedDigit())
        .textCase(.uppercase)
        .foregroundStyle(LaunchStatus(name: state.status).markColor)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

private struct CompactCountdown: View {
    let state: StarshipFlightAttributes.ContentState

    var body: some View {
        let now = Date.now
        let status = LaunchStatus(name: state.status)
        Group {
            if state.headline != nil || status.isFinal {
                Text("—")
            } else if let targetDate = state.targetDate, targetDate > now {
                Text(timerInterval: now...targetDate, countsDown: true)
            } else if let targetDate = state.targetDate, state.hasLiftedOff {
                Text(targetDate, style: .timer)
            } else if state.targetDate != nil {
                Text("T-0")
            } else {
                Text("—")
            }
        }
        .font(.caption.weight(.light).monospacedDigit())
        .foregroundStyle(.white)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 52, alignment: .trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

/// Under the clock: countdowns to the next planned events, drawn by the system so they keep
/// running between updates. Falls back to the last known stage when there is nothing to count to.
private struct ActivityStage: View {
    let state: StarshipFlightAttributes.ContentState

    var body: some View {
        let now = Date.now
        let next = state.nextEvents(now: now)
        if state.canMarkLiftoff(now: now) {
            HStack(alignment: .center) {
                StageText(state: state)
                Spacer(minLength: 8)
                Button(intent: MarkLiftoffIntent()) {
                    Text("Liftoff")
                        .caps(.caption2, tracking: 1.5)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .overlay { Capsule().strokeBorder(.white, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark liftoff")
            }
        } else if next.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                StageText(state: state)
                Spacer(minLength: 8)
                DetailText(state: state)
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(next, id: \.self) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(event.title)
                            .caps(.caption2, color: Theme.secondary, tracking: 1.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                        Text(timerInterval: now...event.date, countsDown: true)
                            .font(.caption.weight(.light).monospacedDigit())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 64, alignment: .trailing)
                    }
                }
            }
        }
    }
}

/// The rail. With the plan on board each segment is a system-drawn progress bar over its own
/// time window, so it fills through the flight without updates. The flight segments only run
/// once liftoff is confirmed; a result or an older state falls back to fixed fills.
private struct ActivityRail: View {
    let state: StarshipFlightAttributes.ContentState
    var showsLabels = true

    var body: some View {
        let status = LaunchStatus(name: state.status)
        if let windows = state.phaseWindows, state.headline == nil, !status.isAlert, !status.isSuccess {
            let now = Date.now
            HStack(alignment: .top, spacing: 6) {
                ForEach(FlightPhase.allCases, id: \.self) { phase in
                    let window = windows.first { $0.phase == phase.rawValue }
                    let runs = phase == .preflight || state.hasLiftedOff
                    VStack(alignment: .leading, spacing: 5) {
                        if let window, runs, window.start < window.end {
                            ProgressView(timerInterval: window.start...window.end, countsDown: false) {
                                EmptyView()
                            } currentValueLabel: {
                                EmptyView()
                            }
                            .progressViewStyle(.linear)
                            .tint(.white)
                        } else {
                            Capsule()
                                .fill(Theme.hairline)
                                .frame(height: 3)
                        }
                        if showsLabels {
                            let started = runs && (window.map { $0.start <= now } ?? false)
                            Text(phase.rawValue)
                                .caps(.caption2, color: started ? .white : Theme.tertiary, tracking: 1)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityHidden(true)
        } else {
            PhaseRailView(fills: state.phaseFills, isAlert: status.isAlert, showsLabels: showsLabels)
        }
    }
}

private struct StageText: View {
    let state: StarshipFlightAttributes.ContentState

    var body: some View {
        // The result already fills the clock line.
        if let stage = state.stage, stage.caseInsensitiveCompare(state.headline ?? "") != .orderedSame {
            Text(stage)
                .caps(.caption2, color: Theme.secondary, tracking: 1.5)
                .lineLimit(1)
        }
    }
}

/// "Pad 2", dimmed beside the stage.
private struct DetailText: View {
    let state: StarshipFlightAttributes.ContentState

    var body: some View {
        if !state.detail.isEmpty {
            Text(state.detail)
                .caps(.caption2, color: Theme.tertiary, tracking: 1.5)
                .lineLimit(1)
        }
    }
}

extension StarshipFlightAttributes.ContentState {
    /// The activity only carries the current phase, so earlier phases read full and the current
    /// one half lit. Booster and ship fly at once after separation, so they light together.
    fileprivate var phaseFills: [FlightPhase: Double] {
        let phases = FlightPhase.allCases
        if LaunchStatus(name: status).isSuccess {
            return Dictionary(uniqueKeysWithValues: phases.map { ($0, 1.0) })
        }
        guard let current = FlightPhase(rawValue: phase), let index = phases.firstIndex(of: current) else {
            return [:]
        }
        let isSplit = current == .booster || current == .ship
        return Dictionary(uniqueKeysWithValues: phases.enumerated().map { offset, item in
            let isCurrent = offset == index || (isSplit && (item == .booster || item == .ship))
            return (item, isCurrent ? 0.5 : offset < index ? 1.0 : 0.0)
        })
    }
}

extension StarshipFlightAttributes {
    /// Opens the Launch tab.
    fileprivate var url: URL? {
        URL(string: "starshipwatcher://flight/\(flightID)")
    }

    /// "Starship | Flight 15" -> "Flight 15".
    fileprivate var shortName: String {
        guard let range = flightName.range(of: " | ") else { return flightName }
        return String(flightName[range.upperBound...])
    }
}

extension StarshipFlightAttributes {
    fileprivate static var preview: StarshipFlightAttributes {
        StarshipFlightAttributes(
            flightID: "preview",
            flightName: "Starship | Flight 15",
            vehicle: "Starship / Super Heavy",
            launchSite: "Starbase"
        )
    }
}

extension StarshipFlightAttributes.ContentState {
    fileprivate static var countdown: StarshipFlightAttributes.ContentState {
        StarshipFlightAttributes.ContentState(
            phase: "Preflight",
            status: "Go for launch",
            targetDate: .now.addingTimeInterval(2 * 60 * 60),
            detail: "Pad 2",
            stage: "Engine chill",
            liftoffConfirmed: false,
            upcoming: [
                StarshipFlightAttributes.Milestone(title: "Go for launch", date: .now.addingTimeInterval(2 * 60 * 60 - 30), phase: "Preflight"),
                StarshipFlightAttributes.Milestone(title: "Liftoff", date: .now.addingTimeInterval(2 * 60 * 60), phase: "Ascent")
            ],
            phaseWindows: [
                StarshipFlightAttributes.PhaseWindow(phase: "Preflight", start: .now.addingTimeInterval(-60 * 60), end: .now.addingTimeInterval(2 * 60 * 60))
            ]
        )
    }
}

#Preview("Notification", as: .content, using: StarshipFlightAttributes.preview) {
    WidgetExtensionLiveActivity()
} contentStates: {
    StarshipFlightAttributes.ContentState.countdown
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: StarshipFlightAttributes.preview) {
    WidgetExtensionLiveActivity()
} contentStates: {
    StarshipFlightAttributes.ContentState.countdown
}

#Preview("Compact", as: .dynamicIsland(.compact), using: StarshipFlightAttributes.preview) {
    WidgetExtensionLiveActivity()
} contentStates: {
    StarshipFlightAttributes.ContentState.countdown
}
