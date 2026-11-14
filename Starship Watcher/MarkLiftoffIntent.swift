import AppIntents

#if canImport(ActivityKit)
/// The Live Activity's "Liftoff" button. Runs in the app process; the widget extension has a
/// matching stub so the button can reference it.
struct MarkLiftoffIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark Liftoff"
    static let description = IntentDescription("Starts the mission clock for the Starship flight on the pad.")

    @MainActor
    func perform() async throws -> some IntentResult {
        let repository = FlightRepository()
        repository.markLiftoff()
        // Also pushes the latest state when there was nothing to mark.
        await StarshipActivityController().sync(flight: repository.nextFlight, canStart: false)
        return .result()
    }
}
#endif
