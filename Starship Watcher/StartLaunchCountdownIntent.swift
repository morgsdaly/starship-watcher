import AppIntents

#if canImport(ActivityKit)
/// Starts the Live Activity without opening the app. Runs in the app process; the widget
/// extension has a matching stub so its buttons and controls can reference it.
struct StartLaunchCountdownIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Launch Countdown"
    static let description = IntentDescription("Pins the next Starship launch countdown to the Lock Screen.")

    @MainActor
    func perform() async throws -> some IntentResult {
        let repository = FlightRepository()
        await repository.refresh(minInterval: 15 * 60)
        guard let flight = repository.nextFlight else { throw CountdownStartError.launchTBD }
        try await StarshipActivityController().startNow(flight: flight)
        BackgroundRefresh.schedule()
        return .result()
    }
}

/// "When's the next Starship Watcher launch?" Siri reads the answer; nothing opens.
struct NextLaunchIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Starship Launch"
    static let description = IntentDescription("Says when the next Starship flight is due.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let repository = FlightRepository()
        await repository.refresh(minInterval: 15 * 60)
        guard let flight = repository.nextFlight else {
            return .result(dialog: "No Starship flight is listed yet.")
        }
        return .result(dialog: "\(flight.spokenSummary())")
    }
}

struct StarshipShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextLaunchIntent(),
            phrases: ["When is the next \(.applicationName) launch", "Next launch in \(.applicationName)"],
            shortTitle: "Next Launch",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: StartLaunchCountdownIntent(),
            phrases: ["Start the \(.applicationName) countdown", "Pin the \(.applicationName) countdown"],
            shortTitle: "Start Countdown",
            systemImageName: "timer"
        )
    }
}
#endif
