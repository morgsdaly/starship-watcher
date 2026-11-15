import SwiftUI
import WidgetKit

// Shared by the Home Screen widgets and the Live Activity. Everything stays white on black,
// red only for bad news, but with some depth: the app icon's glowing ship, a horizon, a lit rail.

/// The app icon's Starship V3 upper stage, from the icon's own artwork, with a faint halo
/// like the icon's glass edge. Size it by height.
struct StarshipMark: View {
    var color: Color = .white
    var glows = true

    var body: some View {
        // Template asset cropped tight to the ship, so it tints and sizes like a shape.
        Image("StarshipSilhouette")
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(color)
            .shadow(color: color.opacity(glows ? 0.3 : 0), radius: 3)
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
                            .railLabel(isLit: fill > 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// One fixed size for all four rail labels. Scaling each to fit made "Preflight" shrink
    /// beside a full-size "Ship".
    func railLabel(isLit: Bool) -> some View {
        self
            .font(.system(size: 9, weight: .medium))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(isLit ? Color.white : Theme.tertiary)
            .lineLimit(1)
            .allowsTightening(true)
    }
}

extension LaunchStatus {
    /// Ship and rail colour.
    var markColor: Color {
        isAlert ? Theme.alert : .white
    }
}
