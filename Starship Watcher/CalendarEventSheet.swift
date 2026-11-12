import EventKit
@preconcurrency import EventKitUI
import SwiftUI

/// The system's "New Event" sheet, filled in for a flight. It runs outside the app, so adding the
/// event needs no calendar permission. The event is a copy: it doesn't follow later slips.
struct CalendarEventSheet: UIViewControllerRepresentable {
    let flight: StarshipFlight

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        let start = flight.launchDate ?? .now
        event.title = "Starship \(flight.shortName) launch"
        event.startDate = start
        // The window when there is one, else liftoff through splashdown.
        event.endDate = max(flight.windowEnd ?? start, start.addingTimeInterval(75 * 60))
        event.location = "\(flight.padName), \(flight.launchSite)"
        event.url = flight.webcastURL ?? flight.sourceURL
        event.notes = "Launch times move often. Check Starship Watcher for the current target."
        event.addAlarm(EKAlarm(relativeOffset: -30 * 60))

        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }
}
