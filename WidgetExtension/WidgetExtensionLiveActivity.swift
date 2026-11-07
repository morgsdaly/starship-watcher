import ActivityKit
import WidgetKit
import SwiftUI

struct StarshipFlightAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        let phase: String
        let status: String
        let targetDate: Date?
        let detail: String
        /// Current mission event ("Hot staging"). Optional so states from older builds still decode.
        var stage: String? = nil
    }

    let flightID: String
    let flightName: String
    let vehicle: String
    let launchSite: String
}

struct WidgetExtensionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StarshipFlightAttributes.self) { context in
            LockScreenActivity(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(Color.white)
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
                        HStack(alignment: .firstTextBaseline) {
                            StageText(state: context.state)
                            Spacer(minLength: 8)
                            DetailText(state: context.state)
                        }
                        PhaseRailView(fills: context.state.phaseFills, isAlert: status.isAlert, showsLabels: false)
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
            .widgetURL(URL(string: "starshipwatcher://flight/\(context.attributes.flightID)"))
            .keylineTint(Color.white.opacity(0.55))
        }
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
                HStack(alignment: .firstTextBaseline) {
                    StageText(state: state)
                    Spacer(minLength: 8)
                    DetailText(state: state)
                }
                PhaseRailView(fills: state.phaseFills, isAlert: status.isAlert)
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
        Group {
            if let targetDate = state.targetDate {
                if targetDate > .now {
                    Text("T-\(Text(timerInterval: Date.now...targetDate, countsDown: true))")
                } else if LaunchStatus(name: state.status).isHoldOrTBD {
                    Text("Awaiting liftoff")
                } else {
                    // Re-rendered when the activity goes stale at the target date. Unlike the app it runs on
                    // while Go: between background refreshes a frozen clock would look broken mid-flight.
                    Text("T+\(Text(targetDate, style: .timer))")
                }
            } else {
                Text("Date TBD")
            }
        }
        .font(font.weight(.light).monospacedDigit())
        .textCase(.uppercase)
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

private struct CompactCountdown: View {
    let state: StarshipFlightAttributes.ContentState

    var body: some View {
        Group {
            if let targetDate = state.targetDate, targetDate > .now {
                if targetDate.timeIntervalSinceNow >= 86400 {
                    Text("\(Int(targetDate.timeIntervalSinceNow / 86400))d")
                } else {
                    Text(timerInterval: Date.now...targetDate, countsDown: true)
                }
            } else if state.targetDate != nil {
                Text(targetDateIsLive ? "LIVE" : "—")
                    .foregroundStyle(targetDateIsLive ? Theme.alert : .white)
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

    private var targetDateIsLive: Bool {
        let status = LaunchStatus(name: state.status)
        return !status.isHoldOrTBD && !status.isSuccess && !status.isAlert
    }
}

private struct StageText: View {
    let state: StarshipFlightAttributes.ContentState

    var body: some View {
        if let stage = state.stage {
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
            stage: "Engine chill"
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
