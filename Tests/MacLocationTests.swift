import Foundation
import Darwin

private final class MemoryPreferences: SimulationPreferences {
    var value: SimulationSnapshot
    var writes = 0, refreshes = 0
    var failWrites = Set<Int>(), failRefreshes = Set<Int>()
    var ignoreWrites = false
    init(_ value: SimulationSnapshot) { self.value = value }
    func read() throws -> SimulationSnapshot { value }
    func write(_ snapshot: SimulationSnapshot) throws {
        writes += 1
        if failWrites.contains(writes) {
            // Simulate a command failing after just one domain was modified.
            var partial = value.values
            partial[LocationSimulationSchema.domains[0]] = snapshot.values[LocationSimulationSchema.domains[0]]
            value = SimulationSnapshot(values: partial)
            throw SimulationFailure.system
        }
        if !ignoreWrites { value = snapshot }
    }
    func refresh() throws {
        refreshes += 1
        if failRefreshes.contains(refreshes) { throw SimulationFailure.system }
    }
}

private final class MemoryBackup: SimulationBackup {
    var value: SimulationSnapshot?
    var failCreate = false, failRemove = false
    func load() throws -> SimulationSnapshot? { value }
    func create(_ snapshot: SimulationSnapshot) throws {
        guard !failCreate, value == nil else { throw SimulationFailure.unsafeState }
        value = snapshot
    }
    func remove() throws { if failRemove { throw SimulationFailure.unsafeState }; value = nil }
}

@main
struct MacLocationTests {
    static func main() throws {
        var count = 0
        func expect(_ value: Bool, _ name: String) {
            count += 1; if !value { fatalError("FAILED: " + name) }
        }
        func rejected(_ name: String, _ operation: () throws -> Void) {
            do { try operation(); expect(false, name) } catch { expect(true, name) }
        }
        let paris = SimulatedPlace(id: "Europe/Paris", latitude: 48.8566, longitude: 2.3522)
        expect(PlaceSearchQuery.normalized("  Cupertino, CA - United States  ") == "Cupertino, CA, United States", "Accept pasted city, state and country searches")
        expect(PlaceSearchQuery.normalized("库比蒂诺，加利福尼亚州，美国") == "库比蒂诺,加利福尼亚州,美国", "Accept full-width punctuation in international searches")
        expect(PlaceSearchQuery.normalized("Wilkes-Barre, PA – United States") == "Wilkes-Barre, PA, United States", "Normalize separators without damaging hyphenated city names")
        let named = SimulatedPlace(id: "place:37.3183833,-122.028425", latitude: 37.3183833, longitude: -122.028425, displayName: "Cupertino, CA · United States")
        expect(try JSONDecoder().decode(SimulatedPlace.self, from: JSONEncoder().encode(named)) == named, "Selected search result keeps its name and exact coordinates after relaunch")
        let legacy = Data(#"{"id":"manual","latitude":37.3183833,"longitude":-122.028425,"accuracy":20}"#.utf8)
        expect(try JSONDecoder().decode(SimulatedPlace.self, from: legacy).displayName == nil, "Existing saved targets remain readable after adding place names")
        func queryItems(_ text: String, language: String = "en") -> [String: String] {
            let url = PlaceSearchQuery.requestURL(text, language: language)!
            return Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        }
        let cupertinoQuery = queryItems("Cupertino, CA - United States")
        expect(cupertinoQuery["name"] == "Cupertino, CA" && cupertinoQuery["countryCode"] == "US", "Resolve the state qualifier and hard country filter from the exact requested input")
        let torontoQuery = queryItems("Toronto, Ontario - Canada")
        expect(torontoQuery["name"] == "Toronto, Ontario" && torontoQuery["countryCode"] == "CA", "Distinguish country Canada from state California")
        let chineseQuery = queryItems("库比蒂诺，CA - 美国", language: "zh")
        expect(chineseQuery["countryCode"] == "US" && chineseQuery["language"] == "zh", "Localize results and recognize a Chinese country name")
        expect(queryItems("Cupertino, CA")["countryCode"] == nil, "Keep a two-part state abbreviation as a regional qualifier")
        expect(PlaceSearchQuery.requestURL("a") == nil && PlaceSearchQuery.requestURL(",,,") == nil && PlaceSearchQuery.requestURL(String(repeating: "a", count: 241)) == nil, "Reject empty or out-of-bounds online queries")
        let geographicFixture = Data(#"{"results":[{"id":5341145,"name":"Cupertino","latitude":37.323,"longitude":-122.03218,"admin1":"California","admin2":"Santa Clara County","country":"United States","timezone":"America/Los_Angeles"}]}"#.utf8)
        let geographicPlace = try JSONDecoder().decode(GeographicSearchResponse.self, from: geographicFixture).results!.first!.resolved!
        expect(geographicPlace.target.displayName == "Cupertino, California, United States" && geographicPlace.target.latitude == 37.323 && geographicPlace.target.longitude == -122.03218, "Decode a named Cupertino candidate with exact WGS84 coordinates")
        expect(try JSONDecoder().decode(GeographicSearchResponse.self, from: Data("{}".utf8)).results == nil, "An empty service response is a valid no-results state")
        let invalidResult = GeographicSearchResult(id: 1, name: "Invalid", latitude: 999, longitude: 0, admin1: nil, admin2: nil, country: nil, timezone: nil)
        expect(invalidResult.resolved == nil, "Reject service coordinates outside valid geographic bounds")
        let ny = SimulatedPlace(id: "America/New_York", latitude: 40.7128, longitude: -74.006)
        let empty = SimulationSnapshot(values: Dictionary(uniqueKeysWithValues: LocationSimulationSchema.domains.map { domain in
            (domain, Dictionary(uniqueKeysWithValues: LocationSimulationSchema.keys.map { ($0, SimulationValue(number: nil)) }))
        }))
        let preferences = MemoryPreferences(empty), backup = MemoryBackup()
        let engine = LocationTransaction(preferences: preferences, backup: backup)
        expect(engine.apply(paris).code == "applied", "Apply saves the original state before mutation")
        expect(backup.value == empty && preferences.value.matches(.target(paris)), "All six keys written, missing originals preserved")
        expect(engine.apply(ny).code == "applied" && backup.value == empty, "Changing target keeps the FIRST session backup")
        expect(engine.restore().code == "restored" && preferences.value == empty && backup.value == nil, "Restore removes originally absent keys and clears backup only after refresh")
        let refreshes = preferences.refreshes
        expect(engine.restore().code == "noBackup" && preferences.refreshes == refreshes, "No backup means no system changes")
        for (lat, lon, accuracy) in [(91.0, 0.0, 20.0), (-91, 0, 20), (0, 181, 20), (0, -181, 20), (.nan, 0, 20), (0, .infinity, 20), (0, 0, 0), (0, 0, 100001)] {
            let before = preferences.writes
            expect(engine.apply(.init(id: "bad", latitude: lat, longitude: lon, accuracy: accuracy)).code == "invalid" && preferences.writes == before, "Reject invalid coordinates before touching any state")
        }
        expect(SimulatedPlace(id: "edge", latitude: -90, longitude: 180, accuracy: 1).isValid, "Coordinate boundaries are accepted")
        expect(SimulationPreferenceOutput.isMissing(status: 1, text: "The domain/default pair of (com.apple.locationd, SimulatedLocationLatitude) does not exist"), "Recognize the legacy absent-key format")
        expect(SimulationPreferenceOutput.isMissing(status: 1, text: "Error: Domain 'com.apple.locationd' not found.\n"), "Recognize macOS 27 absent domains")
        expect(SimulationPreferenceOutput.isMissing(status: 1, text: "Error: Could not find key 'SimulatedLocationLatitude' in domain 'com.apple.locationd'.\n"), "Recognize macOS 27 absent keys")
        expect(!SimulationPreferenceOutput.isMissing(status: 1, text: "Operation not permitted"), "Do not treat permission rejection as an absent key")
        expect(!SimulationPreferenceOutput.isMissing(status: 1, text: "Could not find domain for user 205: bootstrap failed"), "Do not treat bootstrap failure as an absent preference domain")
        expect(!SimulationPreferenceOutput.isMissing(status: 72, text: "Error: Domain 'com.apple.locationd' not found."), "Absence parsing also requires the expected exit code")
        expect(!SimulationPreferenceOutput.isMissing(status: 1, text: "Unexpected failure: something not found"), "Unknown errors never silently become missing keys")
        let preciseValues = ["SimulatedLocationLatitude": 37.3183833, "SimulatedLocationLongitude": -122.028425, "SimulatedLocationAccuracy": 20.0]
        let preciseXML = try PropertyListSerialization.data(fromPropertyList: preciseValues, format: .xml, options: 0)
        let preciseFields = try SimulationPreferencePlist.fields(preciseXML)
        expect(preciseFields["SimulatedLocationLatitude"]?.number == 37.3183833 && preciseFields["SimulatedLocationLongitude"]?.number == -122.028425, "XML reads preserve full coordinate precision")
        let absentXML = try PropertyListSerialization.data(fromPropertyList: ["Unrelated": "not retained"], format: .xml, options: 0)
        expect(try SimulationPreferencePlist.fields(absentXML).values.allSatisfy { $0.number == nil }, "Export retains only fixed simulation keys and preserves absence")
        rejected("Never mistake a boolean for numeric location data") {
            let data = try PropertyListSerialization.data(fromPropertyList: ["SimulatedLocationLatitude": true], format: .xml, options: 0)
            _ = try SimulationPreferencePlist.fields(data)
        }
        rejected("Never coerce an unexpected preference string into a coordinate") {
            let data = try PropertyListSerialization.data(fromPropertyList: ["SimulatedLocationLatitude": "37"], format: .xml, options: 0)
            _ = try SimulationPreferencePlist.fields(data)
        }
        rejected("Refuse non-finite XML numbers") { _ = try SimulationPreferencePlist.literal(.infinity) }
        let precisionDirectory = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("MeridianPrecisionTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: precisionDirectory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: precisionDirectory) }
        let precisionFile = precisionDirectory.appendingPathComponent("probe.plist").path
        func probeDefaults(_ arguments: [String]) throws -> Data {
            let process = Process(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            process.arguments = ["-currentHost"] + arguments
            process.standardOutput = output; process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw SimulationFailure.system }
            return data
        }
        for (key, number) in preciseValues {
            _ = try probeDefaults(["write", precisionFile, key, SimulationPreferencePlist.literal(number)])
        }
        let exportedProbe = try probeDefaults(["export", precisionFile, "-"])
        expect(try SimulationPreferencePlist.fields(exportedProbe) == preciseFields, "Actual defaults XML write/export round trip keeps Cupertino coordinates exact in a temporary plist")
        preferences.failWrites = [preferences.writes + 1]
        expect(engine.apply(paris).code == "rolledBack" && preferences.value == empty && backup.value == empty, "A partial write is rolled back and original backup retained")
        preferences.failWrites = []
        preferences.failRefreshes = [preferences.refreshes + 1]
        expect(engine.apply(paris).code == "rolledBack" && preferences.value == empty, "A restart failure restores the pre-command state")
        preferences.failRefreshes = [preferences.refreshes + 1, preferences.refreshes + 2]
        expect(engine.apply(paris).code == "recoveryRequired" && backup.value != nil, "Failed rollback keeps recovery data and reports failure")
        preferences.failRefreshes = []
        expect(engine.restore().code == "restored", "Recovery succeeds after a transient failure")
        preferences.ignoreWrites = true
        expect(engine.apply(paris).code == "rolledBack", "A successful write exit code is insufficient without matching readback")
        preferences.ignoreWrites = false
        _ = engine.restore()
        backup.failCreate = true
        let writes = preferences.writes
        expect(engine.apply(paris).code == "backupFailed" && preferences.writes == writes, "Never mutate when the original settings cannot be saved")
        backup.failCreate = false
        backup.value = .init(values: [:])
        expect(engine.apply(paris).code == "backupFailed" && preferences.writes == writes, "Reject a corrupted existing backup")
        backup.value = empty
        backup.failRemove = true
        expect(engine.restore().code == "recoveryRequired" && backup.value == empty, "Do not report restoration complete when backup removal fails")

        expect(LocationAuthorizationCommand.script(helper: "/Applications/Meridian.app/Contents/MacOS/MeridianLocationHelper", operation: "apply", place: paris)?.contains("with administrator privileges") == true, "One-off native administrator authorization")
        expect(LocationAuthorizationCommand.script(helper: "/tmp/it's $(touch bad).app/helper", operation: "restore", place: nil)?.contains("'\\\\''") == true, "Shell paths are quoted before AppleScript escaping")
        expect(LocationAuthorizationCommand.script(helper: "/tmp/helper", operation: "sh", place: nil) == nil, "No arbitrary operation reaches the privileged helper")
        expect(LocationAuthorizationCommand.script(helper: "/tmp/helper", operation: "apply", place: nil) == nil, "Apply requires valid numeric coordinates")
        expect(LocationAuthorizationCommand.script(helper: "/tmp/helper\nanything", operation: "restore", place: nil) == nil, "Reject control characters in the executable path")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MeridianLocationTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("state")
        var secure: SecureSimulationBackup? = try SecureSimulationBackup(path: folder.path, owner: geteuid())
        try secure!.create(empty)
        expect(try secure!.load() == empty, "Private atomic backup round trip without system preference access")
        rejected("Never overwrite the original backup") { try secure!.create(.target(paris)) }
        expect(try secure!.load() == empty, "Failed replacement preserves the original")
        rejected("Concurrent processes cannot apply or restore simultaneously") { _ = try SecureSimulationBackup(path: folder.path, owner: geteuid()) }
        try secure!.remove()
        expect(try secure!.load() == nil, "Restore cleanup removes only its own backup")
        secure = nil
        let linked = root.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: folder)
        rejected("Reject a symlinked state directory") { _ = try SecureSimulationBackup(path: linked.path, owner: geteuid()) }
        let original = folder.appendingPathComponent("original.json")
        try JSONEncoder().encode(empty).write(to: original)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: original.path)
        secure = try SecureSimulationBackup(path: folder.path, owner: geteuid())
        rejected("Reject a publicly writable/readable backup") { _ = try secure!.load() }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: original.path)
        expect(try secure!.load() == empty, "Accept the correctly protected backup")
        let alias = folder.appendingPathComponent("alias")
        try FileManager.default.linkItem(at: original, to: alias)
        rejected("Reject hard-linked backup data") { _ = try secure!.load() }
        secure = nil
        print("Passed \(count) Mac location checks: coordinate validation, transactions, rollback, original backup, recovery, locking, file protection and authorization escaping. No system location preferences were accessed or changed.")
    }
}
