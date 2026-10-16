import AppKit
import SwiftUI

@MainActor
final class ClockStore: ObservableObject {
    @Published var language: AppLanguage { didSet { notice = nil; save() } }
    @Published var regions: [ClockRegion] { didSet { save() } }
    @Published var instant: Date
    @Published var localZone: TimeZone
    @Published var alwaysOnTop: Bool { didSet { save() } }
    @Published var positionLocked: Bool { didSet { save() } }
    @Published var snapToEdges: Bool { didSet { save() } }
    @Published var desktopRegionIDs: Set<String> { didSet { save() } }
    @Published var statusRegionIDs: Set<String> { didSet { save() } }
    @Published var desktopVisible: Bool { didSet { save() } }
    @Published var showWeather: Bool { didSet { save(); if showWeather { refreshWeather() } } }
    @Published private(set) var weatherByZone: [String: WeatherReading] = [:]
    @Published private(set) var weatherFailures = Set<String>()
    @Published private(set) var weatherLoading = Set<String>()
    @Published var columns: Int = 4
    @Published var search = ""
    @Published var notice: String?
    let maximumRegions = 6
    let fixedInstant: Date?
    private let persistence: UserDefaults?
    private var timer: Timer?
    private var weatherTask: Task<Void, Never>?
    private var weatherAttempt: [String: Date] = [:]

    init(fixedInstant: Date? = nil, localZone: TimeZone = .current, persistent: Bool = true) {
        self.language = persistent ? AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "en") ?? .english : .english
        self.persistence = persistent ? .standard : nil
        self.fixedInstant = fixedInstant
        self.instant = fixedInstant ?? Date()
        self.localZone = localZone
        self.alwaysOnTop = persistent && UserDefaults.standard.bool(forKey: "alwaysOnTop")
        self.positionLocked = persistent && UserDefaults.standard.bool(forKey: "positionLocked")
        self.snapToEdges = persistent ? (UserDefaults.standard.object(forKey: "snapToEdges") as? Bool ?? true) : true
        let loadedRegions: [ClockRegion]
        if persistent, let data = UserDefaults.standard.data(forKey: "regions"),
           let saved = try? JSONDecoder().decode([ClockRegion].self, from: data) {
            var seen = Set(["system"])
            loadedRegions = [.local] + saved.filter {
                !$0.followsSystem && TimeZone(identifier: $0.id) != nil
                    && seen.insert(CityCatalog.canonicalIdentifier($0.id)).inserted
            }.prefix(5)
        } else {
            loadedRegions = CityCatalog.defaults(local: localZone)
        }
        self.regions = loadedRegions
        let validIDs = Set(loadedRegions.map(\.id))
        self.desktopRegionIDs = persistent ? Set(UserDefaults.standard.stringArray(forKey: "desktopRegionIDs") ?? Array(validIDs)).intersection(validIDs) : validIDs
        self.statusRegionIDs = persistent ? Set(UserDefaults.standard.stringArray(forKey: "statusRegionIDs") ?? ["system"]).intersection(validIDs) : ["system"]
        self.desktopVisible = persistent ? (UserDefaults.standard.object(forKey: "desktopVisible") as? Bool ?? true) : true
        self.showWeather = persistent ? (UserDefaults.standard.object(forKey: "showWeather") as? Bool ?? true) : true
        if persistent, let data = UserDefaults.standard.data(forKey: "weatherCache"),
           let cache = try? JSONDecoder().decode([String: WeatherReading].self, from: data) {
            self.weatherByZone = cache.filter { Date().timeIntervalSince($0.value.fetchedAt) < 86400 }
        }
    }

    func start() {
        guard timer == nil, fixedInstant == nil else { return }
        refreshWeather()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let now = Date()
                let zone = TimeZone.current
                if Int(now.timeIntervalSince1970 / 60) != Int(self.instant.timeIntervalSince1970 / 60) || zone != self.localZone {
                    self.instant = now
                    self.localZone = zone
                    self.refreshWeather()
                }
            }
        }
        timer?.tolerance = 0.25
    }

    private func save() {
        guard let persistence else { return }
        if let data = try? JSONEncoder().encode(regions) { persistence.set(data, forKey: "regions") }
        persistence.set(alwaysOnTop, forKey: "alwaysOnTop")
        persistence.set(positionLocked, forKey: "positionLocked")
        persistence.set(snapToEdges, forKey: "snapToEdges")
        persistence.set(Array(desktopRegionIDs), forKey: "desktopRegionIDs")
        persistence.set(Array(statusRegionIDs), forKey: "statusRegionIDs")
        persistence.set(desktopVisible, forKey: "desktopVisible")
        persistence.set(showWeather, forKey: "showWeather")
        persistence.set(language.rawValue, forKey: "language")
    }

    func t(_ source: String) -> String { language.text(source) }

    func snapshot(_ region: ClockRegion) -> ClockSnapshot {
        ClockSnapshot(region: region, instant: instant, local: localZone, language: language)
    }

    func contains(_ identifier: String) -> Bool {
        let canonical = CityCatalog.canonicalIdentifier(identifier)
        return canonical == CityCatalog.canonicalIdentifier(localZone.identifier)
            || regions.contains { !$0.followsSystem && CityCatalog.canonicalIdentifier($0.id) == canonical }
    }

    func add(_ identifier: String) {
        guard TimeZone(identifier: identifier) != nil, !contains(identifier) else { return }
        guard regions.count < maximumRegions else {
            notice = t("最多显示 6 个地区，请先移除一个地区。")
            return
        }
        regions.append(ClockRegion(id: identifier))
        desktopRegionIDs.insert(identifier)
        refreshWeather()
        notice = "\(t("已添加")) · \(CityCatalog.name(for: identifier, language: language))"
    }

    func remove(_ region: ClockRegion) {
        guard !region.followsSystem else { return }
        regions.removeAll { $0.id == region.id }
        desktopRegionIDs.remove(region.id)
        statusRegionIDs.remove(region.id)
        notice = nil
    }

    func move(_ region: ClockRegion, direction: Int) {
        guard let index = regions.firstIndex(of: region) else { return }
        let destination = index + direction
        guard index > 0, destination > 0, destination < regions.count else { return }
        regions.swapAt(index, destination)
    }

    func reset() {
        regions = CityCatalog.defaults(local: localZone)
        desktopRegionIDs = Set(regions.map(\.id))
        statusRegionIDs = ["system"]
        notice = t("已恢复默认地区")
        refreshWeather()
    }

    func weather(_ region: ClockRegion) -> WeatherReading? {
        weatherByZone[region.timeZone(local: localZone).identifier]
    }

    func weatherStale(_ region: ClockRegion) -> Bool {
        let zone = region.timeZone(local: localZone).identifier
        return weatherFailures.contains(zone) || weatherByZone[zone]?.isStale(at: fixedInstant ?? Date()) == true
    }

    func weatherMessage(_ region: ClockRegion) -> String {
        let zone = region.timeZone(local: localZone).identifier
        if weatherLoading.contains(zone) { return t("天气更新中…") }
        if WeatherClient.cityQuery(for: zone) == nil { return t("此时区无城市天气") }
        return t("天气暂不可用")
    }

    func refreshWeather(force: Bool = false) {
        guard showWeather, fixedInstant == nil, weatherTask == nil else { return }
        let now = Date()
        let zones = Set(regions.map { $0.timeZone(local: localZone).identifier }).filter { zone in
            guard WeatherClient.cityQuery(for: zone) != nil else { return false }
            return force || now.timeIntervalSince(weatherAttempt[zone] ?? .distantPast) >= 15 * 60
        }
        guard !zones.isEmpty else { return }
        for zone in zones { weatherAttempt[zone] = now }
        weatherLoading.formUnion(zones)
        weatherTask = Task { [weak self] in
            await withTaskGroup(of: (String, WeatherReading?).self) { group in
                for zone in zones {
                    group.addTask { (zone, try? await WeatherClient.fetch(zone: zone)) }
                }
                for await (zone, reading) in group {
                    guard let self else { continue }
                    self.weatherLoading.remove(zone)
                    if let reading {
                        self.weatherByZone[zone] = reading
                        self.weatherFailures.remove(zone)
                    } else {
                        self.weatherFailures.insert(zone)
                    }
                }
            }
            guard let self else { return }
            self.weatherTask = nil
            if let data = try? JSONEncoder().encode(self.weatherByZone) {
                self.persistence?.set(data, forKey: "weatherCache")
            }
            // A city may have been added while the previous batch was in flight.
            self.refreshWeather()
        }
    }

    func loadPreviewWeather() {
        guard let fixedInstant else { return }
        for (zone, temperature, code, day) in [
            ("America/New_York", 18.0, 2, true), ("Europe/London", 12.0, 3, false),
            ("Asia/Shanghai", 21.0, 0, false), ("Asia/Tokyo", 17.0, 61, false)
        ] {
            weatherByZone[zone] = WeatherReading(temperature: temperature, code: code,
                isDay: day, observedAt: fixedInstant, fetchedAt: fixedInstant)
        }
    }

    var desktopRegions: [ClockRegion] { regions.filter { desktopRegionIDs.contains($0.id) } }
    var statusRegions: [ClockRegion] { regions.filter { statusRegionIDs.contains($0.id) } }

    func setDesktop(_ region: ClockRegion, visible: Bool) {
        if visible { desktopRegionIDs.insert(region.id) } else { desktopRegionIDs.remove(region.id) }
    }

    func setStatus(_ region: ClockRegion, visible: Bool) {
        if visible { statusRegionIDs.insert(region.id) } else { statusRegionIDs.remove(region.id) }
    }

    var panelSize: NSSize {
        if desktopRegions.isEmpty { return NSSize(width: 360, height: 110) }
        let count = max(1, min(columns, desktopRegions.count))
        let rows = Int(ceil(Double(desktopRegions.count) / Double(count)))
        return NSSize(width: max(220, count * 180), height: 36 + rows * 174)
    }
}
