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

    /// Detailed mode adds streams, timeline, vehicles and updates, which the default normal mode omits.
    private func fetch(path: String, ordering: String) async throws -> [LaunchLibraryLaunch] {
        var components = URLComponents(string: "https://ll.thespacedevs.com/2.3.0/\(path)")!
        components.queryItems = [
            URLQueryItem(name: "search", value: "Starship"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "ordering", value: ordering),
            URLQueryItem(name: "mode", value: "detailed")
        ]

        guard let url = components.url else { return [] }
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
        return try decoder.decode(LaunchLibraryResponse.self, from: data).results
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
        self.webcastURL = response.vidURLs?.min { ($0.priority ?? .max) < ($1.priority ?? .max) }?.url
        self.netPrecision = response.netPrecision?.abbrev
        self.hasExactTime = response.netPrecision?.abbrev.map { ["SEC", "MIN"].contains($0) }
        self.publishedMilestones = response.timeline?.milestones
        self.vehicles = [
            response.rocket?.launcherStage?.first?.vehicle,
            response.rocket?.spacecraftStage?.first?.vehicle
        ].compactMap { $0 }
        self.updates = response.updates?.latest
        self.failureReason = response.failReason?.cleanedLaunchText.nilIfEmpty
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
            landingSucceeded: landing?.outcome
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
            landingSucceeded: landing?.outcome
        )
    }
}

private extension LaunchLibraryLanding {
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
            let phase: FlightPhase
            if offset < 0 {
                phase = .preflight
            } else if name.contains("booster") || name.contains("stage 1") {
                phase = .booster
            } else {
                phase = offset <= staging ? .ascent : .ship
            }
            return FlightMilestone(title: title, offset: offset, phase: phase)
        }
        return FlightPhase.allCases.allSatisfy { phase in milestones.contains { $0.phase == phase } } ? milestones : nil
    }
}

private struct LaunchLibraryResponse: Decodable {
    let results: [LaunchLibraryLaunch]
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
