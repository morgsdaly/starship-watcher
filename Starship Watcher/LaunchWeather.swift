import SwiftUI

/// The forecast hour nearest liftoff at the pad.
struct LaunchForecast: Equatable {
    /// Celsius.
    let temperature: Double
    /// Kilometres per hour, at 10 m.
    let wind: Double
    let gusts: Double?
    /// Percent.
    let cloudCover: Double?
    let rainChance: Double?
}

/// Open-Meteo's free forecast API: no key, no account. Forecasts reach about two weeks out, so
/// this only answers for a firm launch time inside that.
enum LaunchWeather {
    private static var cache: [String: (fetched: Date, forecast: LaunchForecast)] = [:]

    static func forecast(for flight: StarshipFlight, now: Date = .now) async -> LaunchForecast? {
        guard flight.hasFirmDate, !flight.isMock, let launchDate = flight.launchDate,
              launchDate > now, launchDate.timeIntervalSince(now) < 15 * 86_400,
              let (latitude, longitude) = coordinates(for: flight) else { return nil }

        // One request an hour per launch time is plenty for a forecast.
        let key = "\(flight.id)-\(Int(launchDate.timeIntervalSince1970))"
        if let cached = cache[key], now.timeIntervalSince(cached.fetched) < 60 * 60 { return cached.forecast }

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "hourly", value: "temperature_2m,wind_speed_10m,wind_gusts_10m,cloud_cover,precipitation_probability"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "GMT"),
            URLQueryItem(name: "forecast_days", value: "16")
        ]
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let hourly = (try? JSONDecoder().decode(Response.self, from: data))?.hourly else { return nil }

        let target = launchDate.timeIntervalSince1970
        guard let index = hourly.time.indices.min(by: { abs(hourly.time[$0] - target) < abs(hourly.time[$1] - target) }),
              abs(hourly.time[index] - target) <= 60 * 60,
              let temperature = hourly.temperature[safe: index] ?? nil,
              let wind = hourly.wind[safe: index] ?? nil else { return nil }

        let forecast = LaunchForecast(
            temperature: temperature,
            wind: wind,
            gusts: hourly.gusts?[safe: index] ?? nil,
            cloudCover: hourly.cloudCover?[safe: index] ?? nil,
            rainChance: hourly.rainChance?[safe: index] ?? nil
        )
        cache[key] = (now, forecast)
        return forecast
    }

    /// Launch Library's pad coordinates, or Starbase when it gives none.
    private static func coordinates(for flight: StarshipFlight) -> (Double, Double)? {
        if let latitude = flight.padLatitude, let longitude = flight.padLongitude { return (latitude, longitude) }
        let site = flight.launchSite.lowercased()
        return site.contains("starbase") || site.contains("texas") ? (25.9972, -97.1560) : nil
    }

    private struct Response: Decodable {
        let hourly: Hourly
    }

    private struct Hourly: Decodable {
        let time: [Double]
        let temperature: [Double?]
        let wind: [Double?]
        let gusts: [Double?]?
        let cloudCover: [Double?]?
        let rainChance: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case wind = "wind_speed_10m"
            case gusts = "wind_gusts_10m"
            case cloudCover = "cloud_cover"
            case rainChance = "precipitation_probability"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// "Forecast at liftoff" on the Launch page. Absent until there is a forecast to show.
struct LaunchWeatherSection: View {
    let flight: StarshipFlight

    @State private var forecast: LaunchForecast?

    var body: some View {
        Group {
            if let forecast {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Forecast at liftoff").caps(color: Theme.secondary)
                        Spacer()
                        Text("Open-Meteo").caps(.caption2, color: Theme.tertiary, tracking: 1.5)
                    }
                    Text(summary(forecast))
                        .font(.body.weight(.light))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .task(id: flight.launchDate) {
            forecast = await LaunchWeather.forecast(for: flight)
        }
    }

    /// "24°C. Wind 22 km/h, gusting 35 km/h. Cloud 40%. Rain 10%." in the viewer's own units.
    private func summary(_ forecast: LaunchForecast) -> String {
        let whole = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
        let speed = { (value: Double) in
            Measurement(value: value, unit: UnitSpeed.kilometersPerHour)
                .formatted(.measurement(width: .abbreviated, usage: .general, numberFormatStyle: whole))
        }
        let temperature = Measurement(value: forecast.temperature, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: whole))

        var parts = [temperature]
        parts.append(forecast.gusts.map { "Wind \(speed(forecast.wind)), gusting \(speed($0))" } ?? "Wind \(speed(forecast.wind))")
        if let cloud = forecast.cloudCover { parts.append("Cloud \(Int(cloud.rounded()))%") }
        if let rain = forecast.rainChance { parts.append("Rain \(Int(rain.rounded()))%") }
        return parts.joined(separator: ". ") + "."
    }
}
