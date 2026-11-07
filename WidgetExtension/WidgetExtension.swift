import AppIntents
import WidgetKit
import SwiftUI

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StarshipWidgetEntry {
        StarshipWidgetEntry(date: .now, configuration: ConfigurationAppIntent(), flight: .preview)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> StarshipWidgetEntry {
        StarshipWidgetEntry(date: .now, configuration: configuration, flight: FlightCache.nextFlight ?? .preview)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<StarshipWidgetEntry> {
        // The app keeps the shared cache fresh (and reloads widgets when it does), so the widget
        // only hits the network itself before the app has ever loaded data.
        var flight = FlightCache.nextFlight
        if flight == nil {
            flight = (try? await LaunchLibraryClient().fetchStarshipFlights(includePrevious: false))?.nextFlight
        }

        let now = Date()
        let reloadDate = now.addingTimeInterval(60 * 60)
        // "T-1D 12H" needs a fresh entry each hour, and the timer text ticks on its own.
        // The large widget's stage changes at each event, and the pin button appears at T-8h.
        var dates = stride(from: 0, to: 60, by: 15).map { now.addingTimeInterval(TimeInterval($0 * 60)) }
        if let flight, flight.hasFirmDate, let launchDate = flight.launchDate {
            dates += flight.timeline.compactMap(\.targetDate) + [launchDate.addingTimeInterval(-8 * 60 * 60)]
        }
        let entries = dates
            .filter { $0 >= now && $0 < reloadDate }
            .sorted()
            .map { StarshipWidgetEntry(date: $0, configuration: configuration, flight: flight) }
        return Timeline(entries: entries, policy: .after(reloadDate))
    }
}

struct StarshipWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    /// Nil only when nothing is cached and the network failed.
    let flight: StarshipFlight?
}

struct WidgetExtensionEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StarshipWidgetEntry

    var body: some View {
        Group {
            if let flight = entry.flight {
                switch family {
                case .systemSmall:
                    SmallStarshipWidget(flight: flight, now: entry.date)
                case .systemLarge:
                    LargeStarshipWidget(flight: flight, now: entry.date)
                case .accessoryInline:
                    Text("\(flight.shortName) \(clockText(for: flight, now: entry.date))")
                case .accessoryRectangular:
                    AccessoryStarshipWidget(flight: flight, now: entry.date)
                default:
                    MediumStarshipWidget(flight: flight, now: entry.date)
                }
            } else {
                Text("No data").caps(.caption, color: Theme.secondary)
            }
        }
        .containerBackground(for: .widget) {
            switch family {
            case .systemSmall, .systemMedium, .systemLarge:
                HorizonBackdrop(rise: family == .systemLarge ? 0.1 : 0.16)
            default:
                Color.black
            }
        }
    }
}

struct SmallStarshipWidget: View {
    let flight: StarshipFlight
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    FlightNameText(flight: flight)
                    StatusBadge(status: flight.status)
                }
                Spacer(minLength: 0)
                StarshipMark(color: flight.status.markColor)
                    .frame(height: 62)
                    .padding(.trailing, 4)
            }
            Spacer(minLength: 6)
            ClockLabel(flight: flight, now: now)
            WidgetClock(flight: flight, now: now, font: .title2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct MediumStarshipWidget: View {
    let flight: StarshipFlight
    let now: Date

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                FlightNameText(flight: flight)
                Spacer(minLength: 4)
                ClockLabel(flight: flight, now: now)
                WidgetClock(flight: flight, now: now, font: .largeTitle)
                Spacer(minLength: 4)
                HStack(alignment: .center, spacing: 8) {
                    StatusBadge(status: flight.status)
                    PlaceText(flight: flight)
                    Spacer(minLength: 0)
                    StartCountdownButton(flight: flight, now: now)
                }
            }
            StarshipMark(color: flight.status.markColor)
                .frame(height: 118)
                .padding(.trailing, 6)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct LargeStarshipWidget: View {
    let flight: StarshipFlight
    let now: Date

    var body: some View {
        let progress = flight.progress(now: now)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                FlightNameText(flight: flight)
                Spacer(minLength: 8)
                StatusBadge(status: flight.status)
            }

            // The old countdown card, with the ship standing beside it.
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    ClockLabel(flight: flight, now: now)
                    WidgetClock(flight: flight, now: now, font: .largeTitle)
                    if flight.hasFirmDate {
                        Text(flight.dateText(usesUTC: false))
                            .caps(.caption2, color: Theme.secondary, tracking: 1.5)
                            .lineLimit(1)
                    }
                }
                StarshipMark(color: flight.status.markColor)
                    .frame(height: 96)
                    .padding(.trailing, 4)
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }

            PhaseRailView(fills: progress.fills, isAlert: progress.isAlert)

            if flight.isInActiveWindow(now: now) {
                WidgetStage(progress: progress)
            } else {
                Text(flight.summary)
                    .font(.footnote.weight(.light))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 12) {
                PlaceText(flight: flight)
                Spacer(minLength: 0)
                StartCountdownButton(flight: flight, now: now)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Launch hour on the large widget. System-drawn timers aside, a snapshot, so no live remaining time.
private struct WidgetStage: View {
    let progress: MissionProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(progress.title)
                .caps(.footnote, color: progress.isAlert ? Theme.alert : .white)
            ForEach(progress.upcoming) { event in
                HStack(spacing: 12) {
                    Text(event.offsetText)
                        .font(.caption.weight(.light).monospacedDigit())
                    Text(event.title)
                        .font(.caption.weight(.light))
                }
                .foregroundStyle(Theme.secondary)
            }
        }
    }
}

struct AccessoryStarshipWidget: View {
    let flight: StarshipFlight
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            StarshipMark(glows: false)
                .frame(height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(flight.shortName)
                    .font(.caption.weight(.light))
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .lineLimit(1)
                clockText(for: flight, now: now)
                    .font(.headline.weight(.light).monospacedDigit())
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct FlightNameText: View {
    let flight: StarshipFlight

    var body: some View {
        Text(flight.shortName)
            .caps(.caption, color: Theme.secondary)
            .lineLimit(1)
    }
}

/// "Liftoff in" above the clock, so a bare number reads as an instrument.
private struct ClockLabel: View {
    let flight: StarshipFlight
    let now: Date

    var body: some View {
        Text(title)
            .caps(.caption2, color: Theme.tertiary, tracking: 1.5)
            .lineLimit(1)
    }

    private var title: String {
        switch flight.clock(now: now) {
        case .net: "Target"
        case .countdown: "Liftoff in"
        case .awaitingLiftoff: "Countdown"
        case .elapsed: "Mission time"
        }
    }
}

private struct PlaceText: View {
    let flight: StarshipFlight

    var body: some View {
        Text(flight.placeText)
            .caps(.caption2, color: Theme.secondary, tracking: 1.5)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private struct WidgetClock: View {
    let flight: StarshipFlight
    let now: Date
    let font: Font

    var body: some View {
        clockText(for: flight, now: now)
            .font(font.weight(.light).monospacedDigit())
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Starts the Live Activity in place. Only shown inside the 8 hour Live Activity limit.
private struct StartCountdownButton: View {
    let flight: StarshipFlight
    let now: Date

    var body: some View {
        if flight.hasFirmDate, let launchDate = flight.launchDate,
           launchDate > now, launchDate.timeIntervalSince(now) <= 8 * 60 * 60 {
            Button(intent: StartLaunchCountdownIntent()) {
                Label("Pin", systemImage: "pin")
                    .caps(.caption2, tracking: 2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay { Capsule().strokeBorder(.white, lineWidth: 1) }
            }
            .buttonStyle(.plain)
        }
    }
}

struct WidgetExtension: Widget {
    let kind: String = "WidgetExtension"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            WidgetExtensionEntryView(entry: entry)
        }
        .configurationDisplayName("Starship Countdown")
        .description("Track the next Starship flight from your Home Screen or StandBy.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

/// Widgets are snapshots: under a day out, use system timer text so it ticks every second.
/// Further out, whole days/hours are fine since the timeline has an entry every 15 minutes.
func clockText(for flight: StarshipFlight, now: Date) -> Text {
    switch flight.clock(now: now) {
    case .net(let text):
        return Text(text)
    case .awaitingLiftoff:
        return Text("Awaiting liftoff")
    case .elapsed(let date):
        return Text("T+\(Text(date, style: .timer))")
    case .countdown(let date):
        let remaining = Int(date.timeIntervalSince(now))
        if remaining < 86_400 {
            return Text("T-\(Text(timerInterval: now...date, countsDown: true))")
        }
        return Text(String(format: "T-%dD %02dH", remaining / 86_400, remaining / 3_600 % 24))
    }
}

extension StarshipFlight {
    /// Sample for the widget gallery.
    static let preview = StarshipFlight(
        id: "preview", name: "Starship | Flight 15", missionName: "Flight 15",
        summary: "Next Starship flight test from Starbase.", vehicle: "Starship",
        status: LaunchStatus(name: "Go for Launch"), launchDate: .now.addingTimeInterval(26 * 60 * 60),
        windowStart: nil, windowEnd: nil, launchSite: "Starbase", padName: "Pad 2", probability: nil,
        imageURL: nil, webcastLive: false, sourceURL: nil
    )
}

extension ConfigurationAppIntent {
    fileprivate static var previewIntent: ConfigurationAppIntent {
        ConfigurationAppIntent()
    }
}

#Preview(as: .systemSmall) {
    WidgetExtension()
} timeline: {
    StarshipWidgetEntry(date: .now, configuration: .previewIntent, flight: .preview)
}

#Preview(as: .systemMedium) {
    WidgetExtension()
} timeline: {
    StarshipWidgetEntry(date: .now, configuration: .previewIntent, flight: .preview)
}

#Preview(as: .systemLarge) {
    WidgetExtension()
} timeline: {
    StarshipWidgetEntry(date: .now, configuration: .previewIntent, flight: .preview)
}
