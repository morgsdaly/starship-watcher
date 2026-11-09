import SwiftUI

/// What went wrong, what's flying and what's changed. Sibling sections, spaced by the parent stack;
/// each one disappears when Launch Library has nothing for it.
struct FlightFacts: View {
    let flight: StarshipFlight
    let usesUTC: Bool

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
                        VehicleRow(vehicle: vehicle)
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
