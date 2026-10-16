import Foundation

struct RegionLocation: Sendable {
    let countryCode: String
    let latitude: Double
    let longitude: Double
}

enum WorldArea: String, CaseIterable, Identifiable {
    case all, popular, asia, europe, americas, africa, oceania, atlantic, indian, antarctica, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "全球地区"
        case .popular: return "常用地区"
        case .asia: return "亚洲"
        case .europe: return "欧洲"
        case .americas: return "美洲"
        case .africa: return "非洲"
        case .oceania: return "大洋洲"
        case .atlantic: return "大西洋"
        case .indian: return "印度洋"
        case .antarctica: return "南极洲"
        case .other: return "UTC 与其他时区"
        }
    }
    static func containing(_ identifier: String) -> WorldArea {
        switch identifier.split(separator: "/").first {
        case "Asia": return .asia
        case "Europe": return .europe
        case "America": return .americas
        case "Africa": return .africa
        case "Australia", "Pacific": return .oceania
        case "Atlantic": return .atlantic
        case "Indian": return .indian
        case "Antarctica", "Arctic": return .antarctica
        default: return .other
        }
    }
}

struct RegionSection: Identifiable {
    let area: WorldArea
    let identifiers: [String]
    var id: String { area.id }
}

extension CityCatalog {
    static func canonicalIdentifier(_ identifier: String) -> String {
        if ["UTC", "GMT", "Etc/GMT", "Etc/UTC", "Etc/UCT", "UCT", "Universal", "Zulu"].contains(identifier) {
            return "Etc/UTC"
        }
        // Keep separate representative cities, even when their clock rules are
        // linked (e.g. Stockholm and Berlin). Only merge obsolete spellings.
        var current = identifier
        var visited = Set<String>()
        while WorldRegionData.places[current] == nil,
              let target = WorldRegionData.aliases[current], visited.insert(current).inserted {
            current = target
        }
        return current == "Etc/GMT" || current == "Etc/UTC" ? "Etc/UTC" : current
    }

    static func location(for identifier: String) -> RegionLocation? {
        WorldRegionData.places[canonicalIdentifier(identifier)]
    }

    static func country(for identifier: String, language: AppLanguage = .english) -> String? {
        guard let code = location(for: identifier)?.countryCode else { return nil }
        return Locale(identifier: language == .english ? "en" : "zh-Hans")
            .localizedString(forRegionCode: code)
    }

    static let allIdentifiers: [String] = {
        let candidates = TimeZone.knownTimeZoneIdentifiers + Array(WorldRegionData.places.keys) + ["Etc/UTC"]
        return Set(candidates.map(canonicalIdentifier)).filter { TimeZone(identifier: $0) != nil }.sorted()
    }()

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "/", with: " ")
    }

    private static let extraSearchNames: [String: String] = [
        "Asia/Shanghai": "Beijing Peking 北京 北京时间 中国标准时间",
        "Asia/Kolkata": "India Kolkata Calcutta Delhi 加尔各答 新德里",
        "Europe/London": "UK United Kingdom Britain 英国",
        "Asia/Dubai": "UAE United Arab Emirates 阿联酋",
    ]

    private static let countrySearchNames: [String: String] = [
        "US": "USA U.S.A. United States 美国",
        "GB": "UK Britain United Kingdom 英国",
        "AE": "UAE United Arab Emirates 阿联酋",
        "TR": "Turkey Turkiye Türkiye 土耳其",
        "CZ": "Czechia Czech Republic 捷克",
        "CI": "Ivory Coast Côte d’Ivoire 科特迪瓦",
    ]

    private static let searchIndex: [String: String] = {
        var legacy = [String: [String]]()
        for identifier in WorldRegionData.aliases.keys {
            legacy[canonicalIdentifier(identifier), default: []].append(identifier)
        }
        return Dictionary(uniqueKeysWithValues: allIdentifiers.map { identifier in
            let fields = [identifier, name(for: identifier), name(for: identifier, language: .simplifiedChinese),
                country(for: identifier) ?? "", country(for: identifier, language: .simplifiedChinese) ?? "",
                location(for: identifier)?.countryCode ?? "", extraSearchNames[identifier] ?? "",
                countrySearchNames[location(for: identifier)?.countryCode ?? ""] ?? "",
                WorldArea.containing(identifier).title,
                AppLanguage.english.text(WorldArea.containing(identifier).title),
                (legacy[identifier] ?? []).joined(separator: " ")].joined(separator: " ")
            let normalized = normalize(fields)
            return (identifier, normalized + " " + normalized.filter { !$0.isWhitespace })
        })
    }()

    static func search(_ query: String, area: WorldArea = .all, language: AppLanguage = .english) -> [String] {
        let text = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let popularSet = Set(popular.map(canonicalIdentifier))
        return allIdentifiers.filter { identifier in
            let inArea = area == .all || (area == .popular ? popularSet.contains(identifier) : WorldArea.containing(identifier) == area)
            return inArea && tokens.allSatisfy { searchIndex[identifier]?.contains($0) == true }
        }.sorted {
            name(for: $0, language: language).compare(name(for: $1, language: language),
                options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: language.rawValue)) == .orderedAscending
        }
    }

    static func sections(for identifiers: [String], showPopular: Bool) -> [RegionSection] {
        var remaining = identifiers
        var sections = [RegionSection]()
        if showPopular {
            let favorites = popular.map(canonicalIdentifier).filter { identifiers.contains($0) }
            if !favorites.isEmpty { sections.append(.init(area: .popular, identifiers: favorites)) }
            let favoriteSet = Set(favorites)
            remaining.removeAll { favoriteSet.contains($0) }
        }
        for area in WorldArea.allCases where area != .all && area != .popular {
            let items = remaining.filter { WorldArea.containing($0) == area }
            if !items.isEmpty { sections.append(.init(area: area, identifiers: items)) }
        }
        return sections
    }
}
