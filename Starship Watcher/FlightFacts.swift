import SwiftUI

/// What went wrong, what's flying and what's changed. Sibling sections, spaced by the parent stack;
/// each one disappears when Launch Library has nothing for it.
struct FlightFacts: View {
    let flight: StarshipFlight
    let usesUTC: Bool
    /// Every known flight, to show where else a vehicle has flown.
    var allFlights: [StarshipFlight] = []

    var body: some View {
        if let failureReason = flight.failureReason {
            FactSection(title: "What went wrong") {
                Text(failureReason)
                    .font(.body.weight(.light))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if let vehicles = flight.vehicles, !vehicles.isEmpty {
            FactSection(title: "Vehicles") {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(vehicles, id: \.self) { vehicle in
                        VehicleRow(vehicle: vehicle, otherFlights: otherFlights(of: vehicle))
                    }
                }
            }
        }

        if let updates = flight.updates, !updates.isEmpty {
            FactSection(title: "Latest updates") {
                VStack(spacing: 0) {
                    ForEach(updates, id: \.self) { update in
                        UpdateRow(update: update, usesUTC: usesUTC)
                    }
                }
            }
        }
    }
}

extension FlightFacts {
    /// Short names of the other flights this vehicle is on, oldest first.
    fileprivate func otherFlights(of vehicle: FlightVehicle) -> [String] {
        allFlights
            .filter { other in other.id != flight.id && (other.vehicles ?? []).contains { $0.name == vehicle.name } }
            .sorted { ($0.launchDate ?? .distantFuture) < ($1.launchDate ?? .distantFuture) }
            .map(\.shortName)
    }
}

/// Static fires, rollouts and other tests still to come before the launch.
struct CampaignSection: View {
    let events: [CampaignEvent]
    let usesUTC: Bool

    @ScaledMetric(relativeTo: .footnote) private var dateWidth: CGFloat = 86

    var body: some View {
        if !events.isEmpty {
            FactSection(title: "Test campaign") {
                VStack(spacing: 0) {
                    ForEach(events.prefix(4)) { event in
                        AdaptiveRow {
                            Text(event.date.formatted(Date.FormatStyle(timeZone: usesUTC ? .gmt : .current).month(.abbreviated).day()))
                                .font(.footnote.weight(.light).monospacedDigit())
                                .foregroundStyle(Theme.secondary)
                                .frame(minWidth: dateWidth, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.name)
                                    .font(.subheadline.weight(.light))
                                    .foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let kind = event.kind {
                                    Text(kind).caps(.caption2, color: Theme.tertiary, tracking: 1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 11)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

private struct FactSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).caps(color: Theme.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VehicleRow: View {
    let vehicle: FlightVehicle
    var otherFlights: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveRow {
                Text(vehicle.name).caps(.subheadline.weight(.light), tracking: 1.5)
                Spacer(minLength: 0)
                if let statusText = vehicle.statusText {
                    Text(statusText).caps(.caption2, color: Theme.secondary, tracking: 1)
                }
            }
            if let details = vehicle.details {
                Text(details)
                    .font(.subheadline.weight(.light))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let landingSummary = vehicle.landingSummary {
                Text(landingSummary)
                    .font(.footnote.weight(.light))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The plan, until there is an outcome to report instead.
            if vehicle.landingSucceeded == nil, let landingPlan = vehicle.landingPlan {
                Text("Landing plan: \(landingPlan)")
                    .caps(.caption2, color: Theme.secondary, tracking: 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !otherFlights.isEmpty {
                Text("Also on \(otherFlights.joined(separator: " · "))")
                    .caps(.caption2, color: Theme.tertiary, tracking: 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct UpdateRow: View {
    let update: FlightUpdate
    let usesUTC: Bool

    @ScaledMetric(relativeTo: .footnote) private var dateWidth: CGFloat = 86

    var body: some View {
        AdaptiveRow {
            Text(dateText)
                .font(.footnote.weight(.light).monospacedDigit())
                .frame(minWidth: dateWidth, alignment: .leading)
            Text(update.text)
                .font(.subheadline.weight(.light))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.secondary)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var dateText: String {
        var style = Date.FormatStyle(timeZone: usesUTC ? .gmt : .current).month(.abbreviated).day()
        if !Calendar.current.isDate(update.date, equalTo: .now, toGranularity: .year) {
            style = style.year()
        }
        return update.date.formatted(style)
    }
}
