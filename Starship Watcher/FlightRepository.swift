import Foundation
import Observation
import WidgetKit

@Observable
@MainActor
final class FlightRepository {
    private(set) var flights: [StarshipFlight] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?
    /// Takes over as next flight. Kept out of `flights`, so real data and its cache stay untouched.
    private(set) var mockFlight: StarshipFlight?

    private let client: LaunchLibraryClient

    init(client: LaunchLibraryClient? = nil) {
        self.client = client ?? LaunchLibraryClient()
        if let cached = FlightCache.load() {
            flights = cached.flights
            lastUpdated = cached.lastUpdated
        }
        mockFlight = MockFlight.current()
    }

    /// True during the very first fetch when no trusted data has ever loaded — used to
    /// drive loading skeletons instead of flashing placeholder content.
    var isFirstLoad: Bool {
        isLoading && lastUpdated == nil
    }

    var nextFlight: StarshipFlight? {
        // The liftoff mark lives in UserDefaults; reading this makes views follow it.
        _ = liftoffMarkRevision
        return mockFlight ?? flights.nextFlight
    }

    private var liftoffMarkRevision = 0

    /// The viewer saw it leave the pad: start the mission clock now, ahead of Launch Library.
    func markLiftoff(at date: Date = .now) {
        guard let flight = nextFlight, flight.canMarkLiftoff(now: date) else { return }
        ManualLiftoff.mark(flightID: flight.id, at: date)
        liftoffMarksChanged()
    }

    func clearLiftoffMark() {
        ManualLiftoff.clear()
        liftoffMarksChanged()
    }

    /// Also picks up a mark made from the Live Activity while the app was in the background.
    func liftoffMarksChanged() {
        liftoffMarkRevision += 1
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Picks up a mock starting, stopping or changing status with the clock.
    func updateMockFlight() {
        let current = MockFlight.current()
        guard current != mockFlight else { return }
        mockFlight = current
        WidgetCenter.shared.reloadAllTimelines()
    }

    var pastFlights: [StarshipFlight] {
        flights
            .filter { !$0.isUpcoming }
            .sorted { ($0.launchDate ?? .distantPast) > ($1.launchDate ?? .distantPast) }
    }

    /// Launch Library's free tier allows ~15 requests/hour per IP, shared by the app, background
    /// refresh and the start-countdown intent. Skips the network if the last attempt (from any of
    /// those) was within `minInterval`, or while backing off after a 429.
    func refresh(minInterval: TimeInterval = 10 * 60) async {
        updateMockFlight()

        let defaults = UserDefaults.standard
        let now = Date.now
        if let cooldown = defaults.object(forKey: Self.cooldownKey) as? Date, cooldown > now { return }
        if let lastAttempt = defaults.object(forKey: Self.lastAttemptKey) as? Date, now.timeIntervalSince(lastAttempt) < minInterval { return }
        defaults.set(now, forKey: Self.lastAttemptKey)

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Past flights rarely change: refetch every 6h, or once a cached flight has launched.
        let lastPreviousFetch = defaults.object(forKey: Self.lastPreviousFetchKey) as? Date ?? .distantPast
        let launchedSinceFetch = flights.contains { flight in
            guard let launchDate = flight.launchDate else { return false }
            return launchDate > lastPreviousFetch && launchDate < now
        }
        // Not around liftoff, though: the second request would come out of the once-a-minute budget.
        let nearLiftoff = flights.contains { flight in
            guard let launchDate = flight.launchDate else { return false }
            return abs(launchDate.timeIntervalSince(now)) < 20 * 60
        }
        let includePrevious = lastUpdated == nil
            || (!nearLiftoff && (launchedSinceFetch || now.timeIntervalSince(lastPreviousFetch) > 6 * 60 * 60))

        do {
            let fetchedFlights = try await client.fetchStarshipFlights(includePrevious: includePrevious)
            guard !fetchedFlights.isEmpty else {
                throw URLError(.zeroByteResource)
            }
            let merged: [StarshipFlight]
            if includePrevious {
                defaults.set(now, forKey: Self.lastPreviousFetchKey)
                merged = fetchedFlights
            } else {
                let fetchedIDs = Set(fetchedFlights.map(\.id))
                let cachedPast = flights.filter { !fetchedIDs.contains($0.id) && ($0.launchDate ?? .distantFuture) < now }
                merged = fetchedFlights + cachedPast
            }
            flights = merged
            lastUpdated = .now
            saveCachedFlights(merged)
        } catch LaunchLibraryError.rateLimited(let retryAfter) {
            defaults.set(now.addingTimeInterval(retryAfter ?? 15 * 60), forKey: Self.cooldownKey)
            errorMessage = "Launch Library rate limit reached. Showing saved data."
        } catch {
            errorMessage = flights.isEmpty ? nil : "Launch Library is unavailable. Showing saved data."
        }
    }

    private static let lastAttemptKey = "launchDataLastAttempt"
    private static let lastPreviousFetchKey = "launchDataLastPreviousFetch"
    private static let cooldownKey = "launchDataCooldownUntil"

    private func saveCachedFlights(_ flights: [StarshipFlight]) {
        do {
            try FlightCache.save(flights)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = "Fresh launch data loaded, but cache storage failed."
        }
    }
}
