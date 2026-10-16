import Foundation

struct WeatherReading: Codable, Equatable, Sendable {
    let temperature: Double
    let code: Int
    let isDay: Bool
    let observedAt: Date
    let fetchedAt: Date

    var temperatureLabel: String { "\(Int(temperature.rounded()))°C" }
    var condition: String {
        switch code {
        case 0: return "晴"
        case 1, 2: return "多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51, 53, 55: return "毛毛雨"
        case 56, 57, 66, 67: return "冻雨"
        case 61: return "小雨"
        case 63: return "中雨"
        case 65: return "大雨"
        case 71, 73, 75, 77, 85, 86: return "雪"
        case 80, 81, 82: return "阵雨"
        case 95, 96, 97, 99: return "雷雨"
        default: return "天气"
        }
    }
    func condition(in language: AppLanguage) -> String { language.text(condition) }
    var symbol: String {
        switch code {
        case 0: return isDay ? "sun.max" : "moon.stars"
        case 1, 2: return isDay ? "cloud.sun" : "cloud.moon"
        case 3: return "cloud"
        case 45, 48: return "cloud.fog"
        case 51, 53, 55: return "cloud.drizzle"
        case 56, 57, 66, 67: return "cloud.sleet"
        case 61, 63, 65, 80, 81, 82: return "cloud.rain"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow"
        case 95, 96, 97, 99: return "cloud.bolt.rain"
        default: return "cloud"
        }
    }
    func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(fetchedAt) > 30 * 60 || date.timeIntervalSince(observedAt) > 60 * 60
    }
}

struct WeatherCoordinate: Sendable {
    let latitude: Double
    let longitude: Double
}

enum WeatherError: Error { case unavailable, invalidResponse }

enum WeatherClient {
    // Coordinates refer to the city printed on the clock, never the device's precise location.
    static let coordinates: [String: WeatherCoordinate] = [
        "America/New_York": .init(latitude: 40.71, longitude: -74.01),
        "Europe/London": .init(latitude: 51.51, longitude: -0.13),
        "Asia/Shanghai": .init(latitude: 31.23, longitude: 121.47),
        "Asia/Tokyo": .init(latitude: 35.68, longitude: 139.69),
        "America/Los_Angeles": .init(latitude: 34.05, longitude: -118.24),
        "Asia/Singapore": .init(latitude: 1.29, longitude: 103.85),
        "Europe/Paris": .init(latitude: 48.85, longitude: 2.35),
        "Australia/Sydney": .init(latitude: -33.87, longitude: 151.21),
        "Asia/Hong_Kong": .init(latitude: 22.28, longitude: 114.16),
        "Asia/Dubai": .init(latitude: 25.20, longitude: 55.27),
        "Asia/Kolkata": .init(latitude: 28.61, longitude: 77.21),
        "Asia/Calcutta": .init(latitude: 28.61, longitude: 77.21),
        "Asia/Kathmandu": .init(latitude: 27.72, longitude: 85.32),
        "Asia/Katmandu": .init(latitude: 27.72, longitude: 85.32),
        "Pacific/Auckland": .init(latitude: -36.85, longitude: 174.76),
        "Asia/Taipei": .init(latitude: 25.03, longitude: 121.57),
        "Asia/Seoul": .init(latitude: 37.57, longitude: 126.98),
        "America/Chicago": .init(latitude: 41.88, longitude: -87.63),
        "Europe/Berlin": .init(latitude: 52.52, longitude: 13.41),
        "Europe/Istanbul": .init(latitude: 41.01, longitude: 28.98),
        "Pacific/Fiji": .init(latitude: -18.14, longitude: 178.44)
    ]

    static func cityQuery(for zone: String) -> String? {
        guard zone.contains("/"), !zone.hasPrefix("Etc/") else { return nil }
        return zone.split(separator: "/").last.map { String($0).replacingOccurrences(of: "_", with: " ") }
    }

    private struct Locations: Decodable {
        struct Location: Decodable {
            let latitude: Double
            let longitude: Double
            let timezone: String?
        }
        let results: [Location]?
    }
    private struct Forecast: Decodable {
        struct Current: Decodable {
            let time: Double
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        let current: Current
    }

    static func decode(_ data: Data, fetchedAt: Date = Date()) throws -> WeatherReading {
        let value = try JSONDecoder().decode(Forecast.self, from: data).current
        guard value.temperature_2m.isFinite, (-100...70).contains(value.temperature_2m),
              value.time.isFinite, value.is_day == 0 || value.is_day == 1 else { throw WeatherError.invalidResponse }
        return WeatherReading(temperature: value.temperature_2m, code: value.weather_code,
            isDay: value.is_day == 1, observedAt: Date(timeIntervalSince1970: value.time), fetchedAt: fetchedAt)
    }

    private static func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw WeatherError.unavailable }
        return data
    }

    static func fetch(zone: String) async throws -> WeatherReading {
        let coordinate: WeatherCoordinate
        if let known = coordinates[zone] {
            coordinate = known
        } else {
            guard let name = cityQuery(for: zone) else { throw WeatherError.unavailable }
            var query = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
            query.queryItems = [.init(name: "name", value: name), .init(name: "count", value: "20"), .init(name: "language", value: "en")]
            let places = try JSONDecoder().decode(Locations.self, from: await data(from: query.url!))
            // Never silently use a namesake city in another time zone.
            guard let place = places.results?.first(where: { $0.timezone == zone }) else { throw WeatherError.unavailable }
            coordinate = .init(latitude: place.latitude, longitude: place.longitude)
        }
        var query = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        query.queryItems = [
            .init(name: "latitude", value: String(coordinate.latitude)),
            .init(name: "longitude", value: String(coordinate.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "temperature_unit", value: "celsius"),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "forecast_days", value: "1")
        ]
        return try decode(await data(from: query.url!))
    }
}
