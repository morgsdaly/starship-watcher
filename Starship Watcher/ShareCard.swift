import SwiftUI
import UIKit

/// A picture of the flight for Messages or social: name, time, place, status.
struct ShareCard: View {
    let flight: StarshipFlight
    let usesUTC: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Starship").caps(.caption, color: Theme.secondary, tracking: 4)
            Spacer(minLength: 24)
            Text(flight.shortName)
                .caps(.largeTitle.weight(.light), tracking: 4)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(flight.dateText(usesUTC: usesUTC, year: true))
                .caps(.title3.weight(.light), tracking: 2)
                .padding(.top, 14)
            Text(flight.placeText)
                .caps(.footnote, color: Theme.secondary, tracking: 2)
                .padding(.top, 8)
            Spacer(minLength: 24)
            HStack {
                Text(flight.status.displayName).caps(.footnote, color: flight.status.color)
                Spacer()
                Text("Starship Watcher").caps(.caption2, color: Theme.tertiary, tracking: 2)
            }
        }
        .padding(28)
        .frame(width: 360, height: 450, alignment: .leading)
        .background {
            ZStack {
                Color.black
                RadialGradient(colors: [.white.opacity(0.14), .clear], center: .topTrailing, startRadius: 0, endRadius: 380)
            }
        }
        .overlay { Rectangle().strokeBorder(Theme.hairline, lineWidth: 1) }
        // Rendered off screen, where the app's dark scheme isn't inherited.
        .environment(\.colorScheme, .dark)
    }
}

extension StarshipFlight {
    @MainActor
    func shareCardImage(usesUTC: Bool) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCard(flight: self, usesUTC: usesUTC))
        renderer.scale = 3
        return renderer.uiImage
    }
}
