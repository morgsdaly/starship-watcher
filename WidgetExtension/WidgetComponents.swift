import SwiftUI
import WidgetKit

// Shared by the Home Screen widgets and the Live Activity. Everything stays white on black,
// red only for bad news, but with some depth: the app icon's glowing ship, a horizon, a lit rail.

/// The app icon's Starship V3 upper stage, traced from its 1024 x 1536 artwork.
struct StarshipSilhouette: Shape {
    /// Width over height of the traced outline.
    static let aspectRatio: CGFloat = 350.0 / 1455.0

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        var path = Path()
        path.move(to: point(0.5, 0))
        // Ogive nose down to the forward flaps.
        path.addQuadCurve(to: point(0.706, 0.089), control: point(0.665, 0.028))
        path.addLine(to: point(1.0, 0.146))
        path.addLine(to: point(1.0, 0.175))
        path.addLine(to: point(0.826, 0.175))
        // Barrel down to the aft flaps.
        path.addLine(to: point(0.826, 0.728))
        path.addLine(to: point(0.926, 0.756))
        path.addLine(to: point(0.926, 1.0))
        path.addLine(to: point(0.074, 1.0))
        path.addLine(to: point(0.074, 0.756))
        path.addLine(to: point(0.174, 0.728))
        path.addLine(to: point(0.174, 0.175))
        path.addLine(to: point(0.0, 0.175))
        path.addLine(to: point(0.0, 0.146))
        path.addLine(to: point(0.294, 0.089))
        path.addQuadCurve(to: point(0.5, 0), control: point(0.335, 0.028))
        path.closeSubpath()
        return path
    }
}

/// The ship with the icon's glow. Size it by height.
struct StarshipMark: View {
    var color: Color = .white
    var glows = true

    var body: some View {
        StarshipSilhouette()
            .fill(color)
            .aspectRatio(StarshipSilhouette.aspectRatio, contentMode: .fit)
            .shadow(color: color.opacity(glows ? 0.6 : 0), radius: 6)
            .shadow(color: color.opacity(glows ? 0.25 : 0), radius: 16)
            .accessibilityHidden(true)
    }
}

/// Black sky over the curve of the Earth, as in the app icon, with a faint glow up top.
struct HorizonBackdrop: View {
    /// How far the horizon rises from the bottom edge, as a share of the height.
    var rise: CGFloat = 0.16

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let radius = max(size.width, size.height) * 1.6
            let crest = size.height * (1 - rise)

            ZStack {
                Color.black
                RadialGradient(
                    colors: [.white.opacity(0.09), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.8
                )
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.10), .white.opacity(0.02)],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.04)
                        )
                    )
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.38), lineWidth: 1)
                    }
                    .shadow(color: .white.opacity(0.28), radius: 10)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(x: size.width / 2, y: crest + radius)
            }
        }
        .clipped()
    }
}

/// Status as a capsule: solid white when all is well, solid red for bad news, outlined while unsettled.
struct StatusBadge: View {
    let status: LaunchStatus

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let style = BadgeStyle(status: status, isFullColor: renderingMode == .fullColor)
        Text(status.shortName)
            .caps(.caption2, color: style.foreground, tracking: 1.5)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background { Capsule().fill(style.fill) }
            .overlay { Capsule().strokeBorder(style.stroke, lineWidth: 1) }
            .fixedSize()
    }
}

private struct BadgeStyle {
    let foreground: Color
    let fill: Color
    let stroke: Color

    init(foreground: Color, fill: Color, stroke: Color) {
        self.foreground = foreground
        self.fill = fill
        self.stroke = stroke
    }

    init(status: LaunchStatus, isFullColor: Bool) {
        // Tinted and vibrant modes flatten colour, so a filled badge would lose its text.
        if !isFullColor {
            self.init(foreground: .white, fill: .clear, stroke: .white.opacity(0.6))
        } else if status.isAlert {
            self.init(foreground: .black, fill: Theme.alert, stroke: .clear)
        } else if status.isGo || status.isSuccess || status.confirmsLiftoff {
            self.init(foreground: .black, fill: .white, stroke: .clear)
        } else {
            self.init(foreground: .white, fill: .clear, stroke: .white.opacity(0.5))
        }
    }
}

/// Preflight, ascent, booster, ship. Lit segments glow. Equal steps, as in the app's stage tracker.
struct PhaseRailView: View {
    let fills: [FlightPhase: Double]
    var isAlert = false
    var showsLabels = true

    var body: some View {
        let tint = isAlert ? Theme.alert : Color.white
        HStack(alignment: .top, spacing: 6) {
            ForEach(FlightPhase.allCases, id: \.self) { phase in
                let fill = fills[phase] ?? 0
                VStack(alignment: .leading, spacing: 5) {
                    Capsule()
                        .fill(Theme.hairline)
                        .frame(height: 3)
                        .overlay {
                            Capsule()
                                .fill(tint)
                                .scaleEffect(x: fill, y: 1, anchor: .leading)
                                .shadow(color: tint.opacity(fill > 0 ? 0.7 : 0), radius: 3)
                        }
                    if showsLabels {
                        Text(phase.rawValue)
                            .caps(.caption2, color: fill > 0 ? .white : Theme.tertiary, tracking: 1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityHidden(true)
    }
}

extension LaunchStatus {
    /// Ship and rail colour.
    var markColor: Color {
        isAlert ? Theme.alert : .white
    }
}
