import SwiftUI

/// The next flight: a full-screen hero over its photo, then mission text and the sequence on black.
struct LaunchView: View {
    let repository: FlightRepository
    let usesUTC: Bool

    @State private var shareCard: UIImage?
    @State private var showsCalendar = false

    private var flight: StarshipFlight? {
        repository.nextFlight
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                HeroPhoto(imageURL: flight?.imageURL)
                    .ignoresSafeArea()

                content
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if let flight {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if let shareCard {
                                let image = Image(uiImage: shareCard)
                                ShareLink(item: image, preview: SharePreview(flight.shortName, image: image)) {
                                    Label("Share card", systemImage: "photo")
                                }
                            }
                            ShareLink(item: flight.shareText) {
                                Label("Share details", systemImage: "text.alignleft")
                            }
                            if flight.hasFirmDate, !flight.status.confirmsLiftoff, !flight.isMock {
                                Button {
                                    showsCalendar = true
                                } label: {
                                    Label("Add to Calendar", systemImage: "calendar.badge.plus")
                                }
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share flight")
                    }
                }
            }
            .task(id: flight) {
                shareCard = flight?.shareCardImage(usesUTC: usesUTC)
            }
            .sheet(isPresented: $showsCalendar) {
                if let flight {
                    CalendarEventSheet(flight: flight)
                        .ignoresSafeArea()
                }
            }
            .refreshingToolbar(isLoading: repository.isLoading)
        }
    }

    @ViewBuilder
    private var content: some View {
        if repository.isFirstLoad {
            FirstLoadView()
        } else if let flight {
            ScrollView {
                VStack(spacing: 0) {
                    // At least a full screen, and taller when large text needs it.
                    ZStack(alignment: .bottomLeading) {
                        Color.clear.containerRelativeFrame(.vertical)
                        LaunchHero(flight: flight, repository: repository, usesUTC: usesUTC)
                    }
                    // The hero fills the screen, so say there is more below it.
                    .overlay(alignment: .bottom) {
                        Image(systemName: "chevron.compact.down")
                            .font(.title3)
                            .foregroundStyle(Theme.tertiary)
                            .padding(.bottom, 4)
                            .accessibilityHidden(true)
                    }

                    LaunchDetails(flight: flight, repository: repository, usesUTC: usesUTC)
                }
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await repository.refresh(minInterval: 60)
            }
        } else {
            NoDataView(isLoading: repository.isLoading) {
                await repository.refresh(minInterval: 0)
            }
        }
    }

}

private struct LaunchHero: View {
    let flight: StarshipFlight
    let repository: FlightRepository
    let usesUTC: Bool

    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 46

    var body: some View {
        // Ticks land on whole seconds of the countdown, in step with the webcast clock.
        TimelineView(.periodic(from: Countdown.tickAnchor(for: flight.launchDate), by: 1)) { timeline in
            let now = timeline.date
            VStack(alignment: .leading, spacing: 18) {
                Text(flight.shortName)
                    .caps(.title3.weight(.bold), tracking: 4)

                ExplainerButton(explainer: flight.clockExplainer) {
                    Text(clockText(now: now))
                        .font(.system(size: clockSize, weight: .light).monospacedDigit())
                        .textCase(.uppercase)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        // Digits roll rather than snap: down before liftoff, up after.
                        .contentTransition(.numericText(countsDown: !flight.hasLiftedOff(now: now)))
                        .animation(.snappy(duration: 0.3), value: clockText(now: now))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        ExplainerButton(explainer: flight.status.explainer) {
                            Text(flight.status.displayName)
                                .caps(color: flight.status.color)
                        }
                        if flight.isLive(now: now) {
                            Text("● Live").caps(color: Theme.alert)
                        }
                    }
                    Text([flight.relativeDay(now: now), flight.hasFirmDate ? flight.dateText(usesUTC: usesUTC) : nil, flight.placeText]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                        .caps(.caption, color: Theme.secondary, tracking: 1.5)
                        .fixedSize(horizontal: false, vertical: true)
                    if let windowText = flight.windowText(now: now, usesUTC: usesUTC) {
                        Text(windowText)
                            .caps(.caption, color: Theme.secondary, tracking: 1.5)
                            .monospacedDigit()
                    }
                    // Up here, not at the foot of the page: stale data changes how to read the clock.
                    if let errorMessage = repository.errorMessage {
                        NoticeText(message: errorMessage)
                    }
                }

                if flight.isInActiveWindow(now: now) {
                    StageTracker(flight: flight, now: now, checked: flight.isMock ? nil : repository.lastUpdated)
                        .padding(.top, 6)
                }

                LiftoffMark(flight: flight, repository: repository, now: now)

                if let streamURL = flight.liveStreamURL(now: now) {
                    HStack(spacing: 20) {
                        Button("Watch Live") { openURL(streamURL) }
                            .buttonStyle(OutlineButtonStyle())
                        let others = flight.otherStreams(now: now)
                        if !others.isEmpty {
                            Menu {
                                ForEach(others, id: \.self) { stream in
                                    Button(stream.name) { openURL(stream.url) }
                                }
                            } label: {
                                Text("Other streams").caps(.caption, color: Theme.secondary, tracking: 1.5)
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .onChange(of: flight.keepsScreenAwake(now: now), initial: true) { _, keepsAwake in
                UIApplication.shared.isIdleTimerDisabled = keepsAwake
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 28)
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        // The moment itself, whether Launch Library or the viewer called it.
        .sensoryFeedback(.success, trigger: flight.status.confirmsLiftoff)
        .accessibilityElement(children: .contain)
    }

    private func clockText(now: Date) -> String {
        switch flight.clock(now: now) {
        case .net(let text): text
        case .awaitingLiftoff: "Awaiting liftoff"
        case .countdown(let date), .elapsed(let date): Countdown.text(to: date, now: now)
        }
    }
}

/// The viewer's own liftoff call. Launch Library's status can trail the pad by minutes, and the
/// app never assumes liftoff from the clock, so this is the fastest way to start the mission timer.
private struct LiftoffMark: View {
    let flight: StarshipFlight
    let repository: FlightRepository
    let now: Date

    var body: some View {
        if flight.canMarkLiftoff(now: now) {
            VStack(alignment: .leading, spacing: 8) {
                Button("Mark liftoff") { repository.markLiftoff() }
                    .buttonStyle(OutlineButtonStyle())
                Text("Tap as it leaves the pad to start the mission clock.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.top, 6)
        } else if flight.hasManualLiftoff {
            Button { repository.clearLiftoffMark() } label: {
                Text("Liftoff marked by you · Undo")
                    .caps(.caption2, color: Theme.secondary, tracking: 1.5)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Tap for a short explanation of a term. Shows the label alone when there's nothing to explain.
private struct ExplainerButton<Label: View>: View {
    let explainer: Explainer?
    @ViewBuilder let label: Label

    @State private var isShowing = false

    var body: some View {
        if let explainer {
            Button { isShowing = true } label: {
                // The glyph says the term can be tapped.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    label
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                        .accessibilityHidden(true)
                }
            }
                .buttonStyle(.plain)
                .accessibilityHint("Explains this term")
                .popover(isPresented: $isShowing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(explainer.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(explainer.message)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 260, alignment: .leading)
                    .padding(16)
                    // Solid, so the photo and hero text can't show through.
                    .presentationBackground(.black)
                    .presentationCompactAdaptation(.popover)
                }
        } else {
            label
        }
    }
}

private struct LaunchDetails: View {
    let flight: StarshipFlight
    let repository: FlightRepository
    let usesUTC: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fades the fixed photo out as the details scroll up over it.
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)

            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Mission").caps(color: Theme.secondary)
                    Text(flight.summary)
                        .font(.body.weight(.light))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LaunchWeatherSection(flight: flight)

                FlightFacts(flight: flight, usesUTC: usesUTC, allFlights: repository.flights)

                CampaignSection(events: repository.campaignEvents, usesUTC: usesUTC)

                SequenceList(flight: flight)

                if let lastUpdated = repository.lastUpdated {
                    Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))")
                        .caps(.caption2, color: Theme.tertiary, tracking: 1.5)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Overscroll at the bottom must not reveal the photo.
            .background(Color.black.padding(.bottom, -1000))
        }
    }
}

/// Planned offsets, never live data: the flight's published sequence or, without one, a template.
/// The tracker sits here until launch nears, then moves up into the hero.
private struct SequenceList: View {
    let flight: StarshipFlight

    var body: some View {
        TimelineView(.periodic(from: Countdown.tickAnchor(for: flight.launchDate), by: 1)) { timeline in
            let events = flight.timeline
            // A placeholder date passing proves nothing, so soft dates mark no progress.
            let current = flight.hasFirmDate ? flight.currentEventIndex(in: events, now: timeline.date) : nil
            VStack(alignment: .leading, spacing: 36) {
                if !flight.isInActiveWindow(now: timeline.date) {
                    StageTracker(flight: flight, now: timeline.date)
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Sequence").caps(color: Theme.secondary)
                        Spacer()
                        Text(flight.hasPublishedTimeline ? "Planned timeline" : "Typical timeline")
                            .caps(.caption2, color: Theme.tertiary, tracking: 1.5)
                    }

                    VStack(spacing: 0) {
                        ForEach(events.indices, id: \.self) { index in
                            SequenceRow(event: events[index], color: color(for: index, current: current))
                        }
                    }
                }
            }
        }
    }

    private func color(for index: Int, current: Int?) -> Color {
        guard let current else { return Theme.secondary }
        if index == current { return .white }
        return index < current ? Theme.tertiary : Theme.secondary
    }
}

private struct SequenceRow: View {
    let event: FlightEvent
    let color: Color

    @ScaledMetric(relativeTo: .footnote) private var offsetWidth: CGFloat = 86

    var body: some View {
        AdaptiveRow {
            Text(event.offsetText)
                .font(.footnote.weight(.light).monospacedDigit())
                .frame(minWidth: offsetWidth, alignment: .leading)
            Text(event.title)
                .font(.subheadline.weight(.light))
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Fixed flight photo, darkened for the hero text. A flight without a photo keeps the last one
/// shown; plain black only when there has never been one.
private struct HeroPhoto: View {
    let imageURL: URL?
    @State private var image: UIImage?

    init(imageURL: URL?) {
        self.imageURL = imageURL
        // Seed from the memory/disk cache so a known photo is there on the first frame.
        let url = imageURL ?? BackdropImageLoader.lastShownURL
        _image = State(initialValue: url.flatMap { BackdropImageLoader.shared.cachedImage(for: $0) })
    }

    var body: some View {
        GeometryReader { proxy in
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.45), location: 0),
                                .init(color: .black.opacity(0.2), location: 0.35),
                                .init(color: .black.opacity(0.95), location: 0.95)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .transition(.opacity)
            }
        }
        .accessibilityHidden(true)
        .task(id: imageURL) {
            // No photo for this flight: keep the last one shown.
            guard let url = imageURL ?? BackdropImageLoader.lastShownURL else { return }
            if let cached = BackdropImageLoader.shared.cachedImage(for: url) {
                image = cached
                BackdropImageLoader.lastShownURL = url
                return
            }
            // A failed download also keeps the current photo rather than going black.
            guard let loaded = await BackdropImageLoader.shared.image(for: url) else { return }
            BackdropImageLoader.lastShownURL = url
            withAnimation(.easeOut(duration: 0.4)) { image = loaded }
        }
    }
}
