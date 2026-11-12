import Foundation

enum LaunchLibraryError: Error {
    /// HTTP 429. The free tier allows ~15 requests/hour per IP.
    case rateLimited(retryAfter: TimeInterval?)
}

struct LaunchLibraryClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.launchLibraryWithFractionalSeconds.date(from: value) ?? ISO8601DateFormatter.launchLibrary.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(value)")
        }
    }

    /// One request for upcoming, plus one for previous when `includePrevious` is set.
    func fetchStarshipFlights(includePrevious: Bool = true) async throws -> [StarshipFlight] {
        async let upcoming = fetch(path: "launches/upcoming/", ordering: "net")
        async let previous = includePrevious ? fetch(path: "launches/previous/", ordering: "-net") : []
        let combined = try await upcoming + previous

        return combined
            .map(StarshipFlight.init(response:))
            .filter { flight in
                let searchable = "\(flight.name) \(flight.vehicle) \(flight.missionName)".lowercased()
                return searchable.contains("starship") || searchable.contains("super heavy")
            }
            .sorted { lhs, rhs in
                switch (lhs.launchDate, rhs.launchDate) {
                case let (left?, right?):
                    return left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.name < rhs.name
                }
            }
    }

    /// Upcoming static fires, rollouts and other tests, soonest first. One request.
    func fetchCampaignEvents() async throws -> [CampaignEvent] {
        let response: LaunchLibraryEventResponse = try await get(path: "events/upcoming/", query: [
            URLQueryItem(name: "search", value: "Starship"),
            URLQueryItem(name: "limit", value: "10")
        ])
        return response.results
            .compactMap { item -> CampaignEvent? in
                guard let event = item.value, let date = event.date?.value, let name = event.name.nilIfEmpty else { return nil }
                return CampaignEvent(
                    id: event.id,
                    name: name,
                    kind: event.type?.value?.name?.nilIfEmpty,
                    date: date,
                    summary: event.description?.value?.cleanedLaunchText.nilIfEmpty
                )
            }
            .sorted { $0.date < $1.date }
    }

    /// Detailed mode adds streams, timeline, vehicles and updates, which the default normal mode omits.
    private func fetch(path: String, ordering: String) async throws -> [LaunchLibraryLaunch] {
        let response: LaunchLibraryResponse = try await get(path: path, query: [
            URLQueryItem(name: "search", value: "Starship"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "ordering", value: ordering),
            URLQueryItem(name: "mode", value: "detailed")
        ])
        return response.results
    }

    private func get<Response: Decodable>(path: String, query: [URLQueryItem]) async throws -> Response {
        var components = URLComponents(string: "https://ll.thespacedevs.com/2.3.0/\(path)")!
        components.queryItems = query

        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Starship Watcher iOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw LaunchLibraryError.rateLimited(retryAfter: retryAfter)
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(Response.self, from: data)
    }
}

private extension StarshipFlight {
    init(response: LaunchLibraryLaunch) {
        self.id = response.id
        self.name = response.name
        self.missionName = response.mission?.name ?? response.name
        self.summary = response.mission?.description?.cleanedLaunchText ?? "Mission details are pending from the launch data provider."
        self.vehicle = response.rocket?.configuration.fullName ?? response.rocket?.configuration.name ?? "Starship"
        self.status = LaunchStatus(name: response.status.name)
        self.launchDate = response.net
        self.windowStart = response.windowStart
        self.windowEnd = response.windowEnd
        self.launchSite = response.pad?.location.name ?? "Starbase, Texas"
        self.padName = response.pad?.name ?? "Launch Pad"
        self.probability = response.probability
        self.imageURL = response.image?.imageURL
        self.webcastLive = response.webcastLive ?? false
        self.sourceURL = response.url
        let videos = (response.vidURLs ?? []).sorted { ($0.priority ?? .max) < ($1.priority ?? .max) }
        self.webcastURL = videos.first?.url
        self.streams = videos.map { FlightStream(name: $0.publisher?.nilIfEmpty ?? $0.url.host() ?? "Stream", url: $0.url) }
        self.netPrecision = response.netPrecision?.abbrev
        self.hasExactTime = response.netPrecision?.abbrev.map { ["SEC", "MIN"].contains($0) }
        self.publishedMilestones = response.timeline?.milestones
        self.vehicles = [
            response.rocket?.launcherStage?.first?.vehicle,
            response.rocket?.spacecraftStage?.first?.vehicle
        ].compactMap { $0 }
        self.updates = response.updates?.latest
        self.failureReason = response.failReason?.cleanedLaunchText.nilIfEmpty
        self.padLatitude = response.pad?.latitude?.value?.value
        self.padLongitude = response.pad?.longitude?.value?.value
    }
}

private extension Array where Element == LaunchLibraryUpdate {
    /// Newest first, capped at what the screens show so the shared cache stays small.
    var latest: [FlightUpdate] {
        compactMap { update -> FlightUpdate? in
            guard let date = update.createdOn, let text = update.comment?.cleanedLaunchText.nilIfEmpty else { return nil }
            return FlightUpdate(date: date, text: text)
        }
        .sorted { $0.date > $1.date }
        .prefix(5)
        .map { $0 }
    }
}

private extension LaunchLibraryLauncherStage {
    var vehicle: FlightVehicle? {
        guard let launcher, launcher.isPlaceholder != true, let name = launcher.serialNumber?.nilIfEmpty else { return nil }
        return FlightVehicle(
            name: name,
            flightNumber: launcherFlightNumber,
            details: launcher.details?.cleanedLaunchText.nilIfEmpty,
            landingSummary: landing?.description?.cleanedLaunchText.nilIfEmpty,
            landingSucceeded: landing?.outcome,
            role: "Booster",
            landingPlan: landing?.plan
        )
    }
}

private extension LaunchLibrarySpacecraftStage {
    var vehicle: FlightVehicle? {
        guard let spacecraft, spacecraft.isPlaceholder != true, let name = spacecraft.name?.nilIfEmpty else { return nil }
        return FlightVehicle(
            name: name,
            flightNumber: nil,
            details: spacecraft.description?.cleanedLaunchText.nilIfEmpty,
            landingSummary: landing?.description?.cleanedLaunchText.nilIfEmpty,
            landingSucceeded: landing?.outcome,
            role: "Ship",
            landingPlan: landing?.plan
        )
    }
}

private extension LaunchLibraryLanding {
    /// "Return to Launch Site · Starbase". Nil when no landing is planned or nothing is listed.
    var plan: String? {
        guard attempt != false else { return nil }
        let parts = [type?.value?.name, landingLocation?.value?.name].compactMap { $0?.nilIfEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Nil when no landing was attempted or it hasn't happened yet.
    var outcome: Bool? {
        attempt == true ? success : nil
    }
}

private extension Array where Element == LaunchLibraryTimelineEvent {
    /// Nil without a staging event or with an empty phase: progress divides by each phase's count.
    var milestones: [FlightMilestone]? {
        let parsed = compactMap { event -> (title: String, offset: TimeInterval)? in
            guard let title = event.type?.abbrev, let offset = event.relativeTime?.durationSeconds else { return nil }
            return (title, offset)
        }.sorted { $0.offset < $1.offset }

        let isStaging = { (title: String) in title.lowercased().contains("separation") || title.lowercased().contains("staging") }
        guard let staging = parsed.first(where: { isStaging($0.title) })?.offset else { return nil }

        let milestones = parsed.map { title, offset -> FlightMilestone in
            let name = title.lowercased()
            let mentions = { (words: [String]) in words.contains { name.contains($0) } }
            let phase: FlightPhase
            if offset < 0 {
                phase = .preflight
            } else if offset <= staging, !mentions(["boostback"]) {
                phase = .ascent
            } else if mentions(["booster", "super heavy", "stage 1", "first stage", "boostback", "jettison"]) {
                phase = .booster
            } else if mentions(["ship", "stage 2", "second stage", "seco", "payload", "entry"]) {
                phase = .ship
            } else if mentions(["landing", "catch"]) {
                // Unnamed landings: the booster is down within about five minutes of staging.
                phase = offset <= staging + 6 * 60 ? .booster : .ship
            } else {
                phase = .ship
            }
            return FlightMilestone(title: title, offset: offset, phase: phase)
        }
        return FlightPhase.allCases.allSatisfy { phase in milestones.contains { $0.phase == phase } } ? milestones : nil
    }
}

private struct LaunchLibraryResponse: Decodable {
    let results: [LaunchLibraryLaunch]
}

/// Decodes to nil instead of throwing. For fields whose shape hasn't been checked against the
/// live API: a surprise there must not fail the whole launch list.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        // Through a container, so dates still use the decoder's date strategy.
        value = try? decoder.singleValueContainer().decode(Value.self)
    }
}

/// A number that may arrive as a string, as Launch Library's coordinates have across versions.
private struct FlexibleDouble: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self), let number = Double(text) {
            value = number
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a number")
        }
    }
}

private struct LaunchLibraryNamed: Decodable {
    let name: String?
}

private struct LaunchLibraryEventResponse: Decodable {
    let results: [Lenient<LaunchLibraryEvent>]
}

private struct LaunchLibraryEvent: Decodable {
    let id: Int
    let name: String
    let date: Lenient<Date>?
    let type: Lenient<LaunchLibraryNamed>?
    let description: Lenient<String>?
}

private struct LaunchLibraryLaunch: Decodable {
    let id: String
    let url: URL?
    let name: String
    let status: LaunchLibraryStatus
    let net: Date?
    let netPrecision: LaunchLibraryPrecision?
    let windowStart: Date?
    let windowEnd: Date?
    let probability: Int?
    let rocket: LaunchLibraryRocket?
    let mission: LaunchLibraryMission?
    let pad: LaunchLibraryPad?
    let webcastLive: Bool?
    let image: LaunchLibraryImage?
    let vidURLs: [LaunchLibraryVideo]?
    let timeline: [LaunchLibraryTimelineEvent]?
    let updates: [LaunchLibraryUpdate]?
    let failReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case name
        case status
        case net
        case netPrecision = "net_precision"
        case windowStart = "window_start"
        case windowEnd = "window_end"
        case probability
        case rocket
        case mission
        case pad
        case webcastLive = "webcast_live"
        case image
        case vidURLs = "vid_urls"
        case timeline
        case updates
        case failReason = "failreason"
    }
}

/// `abbrev`: SEC, MIN, HR, AM, PM, DAY, WK, M, Q1-Q4, H1, H2, Y, FY, DEC.
private struct LaunchLibraryPrecision: Decodable {
    let abbrev: String?
}

private struct LaunchLibraryUpdate: Decodable {
    let comment: String?
    let createdOn: Date?

    enum CodingKeys: String, CodingKey {
        case comment
        case createdOn = "created_on"
    }
}

private struct LaunchLibraryImage: Decodable {
    let imageURL: URL?

    enum CodingKeys: String, CodingKey {
        case imageURL = "image_url"
    }
}

/// Optional fields so one malformed event can't fail the whole launch list.
private struct LaunchLibraryTimelineEvent: Decodable {
    let type: LaunchLibraryTimelineEventType?
    let relativeTime: String?

    enum CodingKeys: String, CodingKey {
        case type
        case relativeTime = "relative_time"
    }
}

private struct LaunchLibraryTimelineEventType: Decodable {
    let abbrev: String?
}

private struct LaunchLibraryVideo: Decodable {
    let url: URL
    let priority: Int?
    let publisher: String?

    enum CodingKeys: String, CodingKey {
        case url, priority, publisher
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(URL.self, forKey: .url)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority)
        // Lenient: a publisher in an unexpected shape must not fail the whole launch list.
        publisher = (try? container.decodeIfPresent(String.self, forKey: .publisher)) ?? nil
    }
}

private struct LaunchLibraryStatus: Decodable {
    let name: String
}

private struct LaunchLibraryRocket: Decodable {
    let configuration: LaunchLibraryRocketConfiguration
    let launcherStage: [LaunchLibraryLauncherStage]?
    let spacecraftStage: [LaunchLibrarySpacecraftStage]?

    enum CodingKeys: String, CodingKey {
        case configuration
        case launcherStage = "launcher_stage"
        case spacecraftStage = "spacecraft_stage"
    }
}

private struct LaunchLibraryLauncherStage: Decodable {
    let launcherFlightNumber: Int?
    let launcher: LaunchLibraryLauncher?
    let landing: LaunchLibraryLanding?

    enum CodingKeys: String, CodingKey {
        case launcherFlightNumber = "launcher_flight_number"
        case launcher
        case landing
    }
}

private struct LaunchLibraryLauncher: Decodable {
    let serialNumber: String?
    let details: String?
    let isPlaceholder: Bool?

    enum CodingKeys: String, CodingKey {
        case serialNumber = "serial_number"
        case details
        case isPlaceholder = "is_placeholder"
    }
}

private struct LaunchLibrarySpacecraftStage: Decodable {
    let spacecraft: LaunchLibrarySpacecraft?
    let landing: LaunchLibraryLanding?
}

private struct LaunchLibrarySpacecraft: Decodable {
    let name: String?
    let description: String?
    let isPlaceholder: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case isPlaceholder = "is_placeholder"
    }
}

private struct LaunchLibraryLanding: Decodable {
    let attempt: Bool?
    let success: Bool?
    let description: String?
    let type: Lenient<LaunchLibraryNamed>?
    let landingLocation: Lenient<LaunchLibraryNamed>?

    enum CodingKeys: String, CodingKey {
        case attempt, success, description, type
        case landingLocation = "landing_location"
    }
}

private struct LaunchLibraryRocketConfiguration: Decodable {
    let name: String?
    let fullName: String?

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
    }
}

private struct LaunchLibraryMission: Decodable {
    let name: String?
    let description: String?
}

private struct LaunchLibraryPad: Decodable {
    let name: String
    let location: LaunchLibraryLocation
    let latitude: Lenient<FlexibleDouble>?
    let longitude: Lenient<FlexibleDouble>?
}

private struct LaunchLibraryLocation: Decodable {
    let name: String
}

private extension ISO8601DateFormatter {
    static let launchLibrary: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let launchLibraryWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private extension String {
    var cleanedLaunchText: String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    /// Seconds in an ISO 8601 duration: "-PT35M33S", "PT1H17M40S", "P0D". Nil if malformed.
    var durationSeconds: TimeInterval? {
        var rest = Substring(self)
        let sign: TimeInterval = rest.first == "-" ? -1 : 1
        if rest.first == "-" || rest.first == "+" { rest = rest.dropFirst() }
        guard rest.first == "P" else { return nil }

        var total: TimeInterval = 0
        var number = ""
        var inTime = false
        for character in rest.dropFirst() {
            if character == "T" {
                inTime = true
            } else if character.isNumber || character == "." {
                number.append(character)
            } else {
                let unit: TimeInterval
                switch (character, inTime) {
                case ("D", false): unit = 86_400
                case ("H", true): unit = 3_600
                case ("M", true): unit = 60
                case ("S", true): unit = 1
                default: return nil
                }
                guard let value = TimeInterval(number) else { return nil }
                total += value * unit
                number = ""
            }
        }
        return number.isEmpty ? sign * total : nil
    }
}
