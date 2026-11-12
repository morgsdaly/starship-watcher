import AppIntents

/// Mirror of the app target's intent. LiveActivityIntent runs in the app process, so this copy
/// only exists so the Live Activity's button can reference the type.
struct MarkLiftoffIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark Liftoff"
    static let description = IntentDescription("Starts the mission clock for the Starship flight on the pad.")

    func perform() async throws -> some IntentResult {
        .result()
    }
}
