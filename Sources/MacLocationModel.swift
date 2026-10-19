import Foundation

struct SimulatedPlace: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    var accuracy: Double = 20
    var displayName: String? = nil

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && accuracy.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
            && (1...100_000).contains(accuracy)
    }
}

enum PlaceSearchQuery {
    static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: #"\s+[-–—·]\s+"#, with: ", ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func requestURL(_ text: String, language: String = "en") -> URL? {
        let query = normalized(text)
        guard (2...240).contains(query.count) else { return nil }
        var parts = query.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        var country: String?
        if let last = parts.last, parts.count >= 3 || (parts.count == 2 && (last.count > 2 || last.uppercased() == "UK")),
           let code = countryCode(last) {
            country = code; parts.removeLast()
        }
        var url = URLComponents()
        url.scheme = "https"; url.host = "geocoding-api.open-meteo.com"; url.path = "/v1/search"
        url.queryItems = [URLQueryItem(name: "name", value: parts.joined(separator: ", ")),
            URLQueryItem(name: "count", value: "12"), URLQueryItem(name: "language", value: language == "zh" ? "zh" : "en"),
            URLQueryItem(name: "format", value: "json")]
        if let country { url.queryItems?.append(URLQueryItem(name: "countryCode", value: country)) }
        return url.url
    }

    private static func countryCode(_ name: String) -> String? {
        func key(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .filter { $0.isLetter || $0.isNumber }
        }
        let wanted = key(name)
        let aliases = ["usa": "US", "unitedstatesofamerica": "US", "uk": "GB", "greatbritain": "GB", "prc": "CN"]
        if let alias = aliases[wanted] { return alias }
        let locales = [Locale(identifier: "en_US"), Locale(identifier: "zh_Hans"), Locale.current]
        return Locale.Region.isoRegions.first { region in
            key(region.identifier) == wanted || locales.contains { locale in
                locale.localizedString(forRegionCode: region.identifier).map { key($0) == wanted } ?? false
            }
        }?.identifier
    }
}

struct ResolvedPlace: Identifiable, Equatable, Sendable {
    let target: SimulatedPlace
    let subtitle: String
    var id: String { target.id }
}

struct GeographicSearchResponse: Decodable {
    let results: [GeographicSearchResult]?
}

struct GeographicSearchResult: Decodable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let admin1: String?
    let admin2: String?
    let country: String?
    let timezone: String?

    var resolved: ResolvedPlace? {
        let label = [name, admin1, country].compactMap { $0 }.reduce(into: [String]()) {
            if !$1.isEmpty, !$0.contains($1) { $0.append($1) }
        }.joined(separator: ", ")
        let target = SimulatedPlace(id: "geonames:\(id)", latitude: latitude, longitude: longitude, displayName: label)
        guard id > 0, target.isValid else { return nil }
        let detail = [admin2, timezone].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return ResolvedPlace(target: target, subtitle: detail)
    }
}

struct LocationHelperReply: Codable, Sendable {
    let code: String
    let recoveryAvailable: Bool
    let detail: String?
    init(code: String, recoveryAvailable: Bool, detail: String? = nil) {
        self.code = code; self.recoveryAvailable = recoveryAvailable; self.detail = detail
    }
}

enum LocationSimulationSchema {
    static let domains = ["com.apple.locationd", "com.apple.locationd.notbackedup"]
    static let keys = ["SimulatedLocationLatitude", "SimulatedLocationLongitude", "SimulatedLocationAccuracy"]
    static let statePath = "/var/db/meridian-location"
}

enum SimulationPreferenceOutput {
    static func isMissing(status: Int32, text: String) -> Bool {
        guard status == 1 else { return false }
        if text.contains("domain/default pair"), text.contains("does not exist") { return true }
        // macOS 27 changed defaults' absent-domain/key messages. Match only the
        // known absence formats; permission and bootstrap failures still abort.
        let patterns = [
            #"(?m)^Error: (Domain|Key) '[^'\r\n]+' not found\.\s*$"#,
            #"(?m)^Error: Could not find key '[^'\r\n]+' in domain '[^'\r\n]+'\.\s*$"#,
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }
}

struct SimulationValue: Codable, Equatable {
    let number: Double?
}

struct SimulationSnapshot: Codable, Equatable {
    let values: [String: [String: SimulationValue]]
    var isValid: Bool {
        Set(values.keys) == Set(LocationSimulationSchema.domains)
            && values.values.allSatisfy { fields in
                Set(fields.keys) == Set(LocationSimulationSchema.keys)
                    && fields.values.allSatisfy { $0.number?.isFinite ?? true }
            }
    }
    func matches(_ other: SimulationSnapshot) -> Bool {
        guard isValid, other.isValid else { return false }
        return LocationSimulationSchema.domains.allSatisfy { domain in
            LocationSimulationSchema.keys.allSatisfy { key in
                let a = values[domain]![key]!.number, b = other.values[domain]![key]!.number
                if let a, let b { return abs(a - b) <= 0.000001 }
                return a == nil && b == nil
            }
        }
    }
    static func target(_ place: SimulatedPlace) -> SimulationSnapshot {
        let numbers = [place.latitude, place.longitude, place.accuracy]
        let fields = Dictionary(uniqueKeysWithValues: zip(LocationSimulationSchema.keys, numbers).map {
            ($0.0, SimulationValue(number: $0.1))
        })
        return SimulationSnapshot(values: Dictionary(uniqueKeysWithValues: LocationSimulationSchema.domains.map { ($0, fields) }))
    }
}

// Keep privilege boundaries and all shell escaping in one auditable place.
enum LocationAuthorizationCommand {
    static func script(helper: String, operation: String, place: SimulatedPlace?) -> String? {
        guard helper.hasPrefix("/"), helper.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }), ["apply", "restore", "diagnose"].contains(operation) else { return nil }
        var args = [helper, operation]
        if operation == "apply" {
            guard let place, place.isValid else { return nil }
            args += [String(place.latitude), String(place.longitude), String(place.accuracy)]
        } else if place != nil { return nil }
        let command = args.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(literal)\" with administrator privileges\n"
    }
}
