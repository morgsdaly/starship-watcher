import SwiftUI

/// The programme in numbers, worked out from the flights Launch Library has returned.
struct ProgrammeStats: Equatable {
    let flown: Int
    let successes: Int
    /// Successful flights in a row, counting back from the latest.
    let streak: Int
    let daysSinceLast: Int?
    let boosterLandings: Int
    let boosterAttempts: Int
    /// Shortest gap between two consecutive flights.
    let fastestTurnaroundDays: Int?

    init(flights: [StarshipFlight], now: Date = .now) {
        let dated = flights.compactMap { flight -> (flight: StarshipFlight, date: Date)? in
            guard !flight.isMock, flight.status.isFinal, let date = flight.launchDate, date <= now else { return nil }
            return (flight, date)
        }
        .sorted { $0.date < $1.date }

        flown = dated.count
        successes = dated.count { $0.flight.status.isSuccess }
        streak = dated.reversed().prefix { $0.flight.status.isSuccess }.count
        daysSinceLast = dated.last.map { Int(now.timeIntervalSince($0.date) / 86_400) }

        let boosters = dated.compactMap { entry in
            entry.flight.vehicles?.first { $0.role == "Booster" }?.landingSucceeded
        }
        boosterAttempts = boosters.count
        boosterLandings = boosters.count { $0 }

        let gaps = zip(dated, dated.dropFirst()).map { $1.date.timeIntervalSince($0.date) }
        fastestTurnaroundDays = gaps.min().map { Int(($0 / 86_400).rounded()) }
    }
}

struct ProgrammeStatsView: View {
    let stats: ProgrammeStats

    var body: some View {
        if stats.flown > 0 {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 20) {
                StatTile(value: "\(stats.flown)", label: "Flights")
                StatTile(value: "\(stats.successes)", label: "Successful")
                StatTile(value: "\(stats.streak)", label: "In a row")
                if let days = stats.daysSinceLast {
                    StatTile(value: "\(days)", label: days == 1 ? "Day since last" : "Days since last")
                }
                if stats.boosterAttempts > 0 {
                    StatTile(value: "\(stats.boosterLandings)/\(stats.boosterAttempts)", label: "Booster landings")
                }
                if let days = stats.fastestTurnaroundDays {
                    StatTile(value: "\(days)", label: days == 1 ? "Day, fastest turnaround" : "Days, fastest turnaround")
                }
            }
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title.weight(.light).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .caps(.caption2, color: Theme.secondary, tracking: 1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
