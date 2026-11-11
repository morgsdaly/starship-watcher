import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var repository = FlightRepository()
    @State private var newsRepository = NewsRepository()
    @AppStorage("usesUTC") private var usesUTC = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled = true
    @AppStorage("mockFlightEnabled") private var mockFlightEnabled = false
    @AppStorage("mockFlightMode") private var mockFlightMode = MockFlightMode.liftoff
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = AppTab.launch

    var body: some View {
        TabView(selection: $selectedTab) {
            LaunchView(repository: repository, usesUTC: usesUTC)
                .tabItem {
                    Label("Launch", systemImage: "timer")
                }
                .tag(AppTab.launch)

            FlightsView(repository: repository, usesUTC: usesUTC)
                .tabItem {
                    Label("Flights", systemImage: "list.bullet")
                }
                .tag(AppTab.flights)

            NewsView(repository: newsRepository)
                .tabItem {
                    Label("News", systemImage: "newspaper")
                }
                .tag(AppTab.news)

            SettingsView(
                usesUTC: $usesUTC,
                notificationsEnabled: $notificationsEnabled,
                liveActivityEnabled: $liveActivityEnabled,
                mockFlightEnabled: $mockFlightEnabled,
                mockFlightMode: $mockFlightMode
            )
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
        .tint(.white)
        // starshipwatcher://flight/<id> from the Live Activity: the countdown lives on Launch.
        .onOpenURL { url in
            if url.scheme == "starshipwatcher" { selectedTab = .launch }
        }
        .task {
            await repository.refresh()
            await syncLiveActivity()
            await NotificationScheduler().sync(flight: repository.nextFlight)
            await newsRepository.refresh()
        }
        .onChange(of: liveActivityEnabled) { _, enabled in
            Task {
                #if canImport(ActivityKit)
                if !enabled { await StarshipActivityController().endAll(includingEnded: true) }
                #endif
                await syncLiveActivity()
            }
        }
        .onChange(of: notificationsEnabled) { _, _ in
            Task { await NotificationScheduler().sync(flight: repository.nextFlight) }
        }
        .onChange(of: mockFlightEnabled) { _, _ in
            applyMockFlight()
        }
        .onChange(of: mockFlightMode) { _, _ in
            applyMockFlight()
        }
        .task(id: scenePhase) {
            // Restarts on every return to the foreground, which also covers opening from the
            // "countdown ready" reminder, a widget tap, or a liftoff marked on the Lock Screen.
            guard scenePhase == .active else { return }
            repository.liftoffMarksChanged()
            await pollLaunchLibrary()
        }
        .onChange(of: repository.nextFlight) { _, _ in
            Task {
                await syncLiveActivity()
                await NotificationScheduler().sync(flight: repository.nextFlight)
            }
        }
        .task(id: liveActivityMonitorID) {
            await monitorLiveActivityThresholds()
        }
        .task(id: repository.mockFlight?.launchDate) {
            await followMockFlight()
        }
    }

    private var liveActivityMonitorID: String {
        "\(repository.nextFlight?.id ?? "none")-\(repository.nextFlight?.launchDate?.timeIntervalSince1970 ?? 0)-\(liveActivityEnabled)"
    }

    /// Runs for as long as the app is in the foreground, whichever tab is showing. Refreshes on
    /// the flight's own schedule near launch (`pollInterval`), and lazily the rest of the time.
    private func pollLaunchLibrary() async {
        while !Task.isCancelled {
            let flight = repository.nextFlight
            let interval = flight?.pollInterval()
            await repository.refresh(minInterval: interval.map { $0 - 10 } ?? 30 * 60)
            guard !Task.isCancelled else { return }
            // Push the current stage even when Launch Library data didn't change.
            await syncLiveActivity()
            // Outside the window, look again soon: it opens at T-3h without the flight changing.
            try? await Task.sleep(for: .seconds(repository.nextFlight?.nextPollDelay() ?? 5 * 60))
        }
    }

    private func applyMockFlight() {
        if mockFlightEnabled {
            MockFlight.start(mockFlightMode)
        } else {
            MockFlight.stop()
        }
        repository.updateMockFlight()
    }

    /// Steps the mock through each event while the app is open, so status and stage update on time.
    private func followMockFlight() async {
        while !Task.isCancelled,
              let next = repository.mockFlight?.timeline.compactMap(\.targetDate).first(where: { $0 > .now }) {
            try? await Task.sleep(for: .seconds(next.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            repository.updateMockFlight()
            await syncLiveActivity()
        }
    }

    private func syncLiveActivity() async {
        #if canImport(ActivityKit)
        await StarshipActivityController().sync(flight: repository.nextFlight, canStart: true)
        #endif
    }

    private func monitorLiveActivityThresholds() async {
        #if canImport(ActivityKit)
        guard liveActivityEnabled, let flight = repository.nextFlight, flight.hasFirmDate, let launchDate = flight.launchDate else { return }
        let start = StarshipActivityController.windowStart(for: launchDate)
        while !Task.isCancelled, start > .now {
            try? await Task.sleep(for: .seconds(min(max(start.timeIntervalSinceNow, 1), 60 * 60)))
        }
        await syncLiveActivity()
        #endif
    }
}

private enum AppTab {
    case launch, flights, news, settings
}

#Preview {
    ContentView()
}
