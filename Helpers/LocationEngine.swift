import Foundation
import CoreFoundation
import Darwin

protocol SimulationPreferences {
    func read() throws -> SimulationSnapshot
    func write(_ snapshot: SimulationSnapshot) throws
    func refresh() throws
}

protocol SimulationBackup {
    func load() throws -> SimulationSnapshot?
    func create(_ snapshot: SimulationSnapshot) throws
    func remove() throws
}

enum SimulationFailure: Error {
    case invalid, system, unsafeState, busy, commandFailed(String)
    static func detail(_ error: Error) -> String {
        switch error {
        case SimulationFailure.commandFailed(let label): return label
        case SimulationFailure.invalid: return "invalidValue"
        case SimulationFailure.unsafeState: return "unsafeState"
        case SimulationFailure.busy: return "operationLocked"
        default: return "systemOperation"
        }
    }
}

struct LocationTransaction {
    let preferences: SimulationPreferences
    let backup: SimulationBackup

    func apply(_ place: SimulatedPlace) -> LocationHelperReply {
        guard place.isValid else { return .init(code: "invalid", recoveryAvailable: false) }
        let before: SimulationSnapshot
        do {
            before = try preferences.read()
            guard before.isValid else { throw SimulationFailure.invalid }
        } catch { return .init(code: "backupFailed", recoveryAvailable: true, detail: "readPreferences:" + SimulationFailure.detail(error)) }
        do {
            if let original = try backup.load() {
                guard original.isValid else { throw SimulationFailure.unsafeState }
            } else { try backup.create(before) }
        } catch { return .init(code: "backupFailed", recoveryAvailable: true, detail: "saveOriginal:" + SimulationFailure.detail(error)) }
        do {
            let target = SimulationSnapshot.target(place)
            try preferences.write(target)
            guard try preferences.read().matches(target) else { throw SimulationFailure.system }
            try preferences.refresh()
            return .init(code: "applied", recoveryAvailable: true)
        } catch {
            let applyFailure = SimulationFailure.detail(error)
            do {
                try preferences.write(before)
                guard try preferences.read() == before else { throw SimulationFailure.system }
                try preferences.refresh()
                return .init(code: "rolledBack", recoveryAvailable: true, detail: "apply:" + applyFailure)
            } catch { return .init(code: "recoveryRequired", recoveryAvailable: true, detail: "apply:" + applyFailure + ";rollback:" + SimulationFailure.detail(error)) }
        }
    }

    func restore() -> LocationHelperReply {
        do {
            guard let original = try backup.load() else { return .init(code: "noBackup", recoveryAvailable: false) }
            guard original.isValid else { throw SimulationFailure.unsafeState }
            try preferences.write(original)
            guard try preferences.read() == original else { throw SimulationFailure.system }
            try preferences.refresh()
            try backup.remove()
            return .init(code: "restored", recoveryAvailable: false)
        } catch { return .init(code: "recoveryRequired", recoveryAvailable: true, detail: "restore:" + SimulationFailure.detail(error)) }
    }
}

enum SimulationPreferencePlist {
    static func literal(_ number: Double) throws -> String {
        guard number.isFinite else { throw SimulationFailure.invalid }
        return "<real>" + String(number) + "</real>"
    }

    static func fields(_ data: Data) throws -> [String: SimulationValue] {
        guard data.count <= 1_048_576,
              let values = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { throw SimulationFailure.invalid }
        var fields = [String: SimulationValue]()
        for key in LocationSimulationSchema.keys {
            guard let value = values[key] else { fields[key] = SimulationValue(number: nil); continue }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { throw SimulationFailure.invalid }
            fields[key] = SimulationValue(number: number.doubleValue)
        }
        return fields
    }
}

// Never accept paths, domains, keys or executable names from a caller.
struct SystemSimulationPreferences: SimulationPreferences {
    private func run(_ executable: String, _ args: [String], allowFailure: Bool = false) throws -> (Int32, String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C", "LC_ALL": "C"]
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output; process.standardError = errors
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)
        let text = output.fileHandleForReading.readDataToEndOfFile()
        let error = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit(); timeout.cancel()
        guard allowFailure || process.terminationStatus == 0 else {
            let diagnostic = (String(decoding: text, as: UTF8.self) + String(decoding: error, as: UTF8.self)).lowercased()
            let reason = diagnostic.contains("system integrity protection") ? "systemProtection" : diagnostic.contains("not permitted") ? "denied" : "rejected"
            throw SimulationFailure.commandFailed(URL(fileURLWithPath: executable).lastPathComponent + ":" + String(process.terminationStatus) + ":" + reason)
        }
        return (process.terminationStatus, String(decoding: text, as: UTF8.self), String(decoding: error, as: UTF8.self))
    }

    private func defaults(_ domain: String, operation: String, arguments: [String]) throws -> (Int32, String, String) {
        guard LocationSimulationSchema.domains.contains(domain), ["export", "write", "delete"].contains(operation) else { throw SimulationFailure.invalid }
        let uid = try run("/usr/bin/id", ["-u", "_locationd"]).1.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty, uid.allSatisfy(\.isNumber) else { throw SimulationFailure.system }
        return try run("/bin/launchctl", ["asuser", uid, "/usr/bin/sudo", "-n", "-H", "-u", "_locationd",
            "/usr/bin/defaults", "-currentHost", operation, domain] + arguments, allowFailure: true)
    }

    private func checked(_ result: (Int32, String, String), operation: String) throws -> Bool {
        if result.0 != 0 {
            if ["export", "delete"].contains(operation), SimulationPreferenceOutput.isMissing(status: result.0, text: result.1 + result.2) { return false }
            let reason = result.2.lowercased().contains("not permitted") ? "denied" : result.2.lowercased().contains("bootstrap") ? "bootstrap" : "rejected"
            throw SimulationFailure.commandFailed("preference-" + operation + ":" + String(result.0) + ":" + reason)
        }
        return true
    }

    func read() throws -> SimulationSnapshot {
        var result = [String: [String: SimulationValue]]()
        for domain in LocationSimulationSchema.domains {
            // Human-readable `defaults read` rounds real numbers on macOS 27.
            // XML export preserves the original numeric precision; retain only
            // the six simulation values, never the rest of the domain.
            let exported = try defaults(domain, operation: "export", arguments: ["-"])
            if try checked(exported, operation: "export") {
                result[domain] = try SimulationPreferencePlist.fields(Data(exported.1.utf8))
            } else {
                result[domain] = Dictionary(uniqueKeysWithValues: LocationSimulationSchema.keys.map { ($0, SimulationValue(number: nil)) })
            }
        }
        return SimulationSnapshot(values: result)
    }

    func write(_ snapshot: SimulationSnapshot) throws {
        guard snapshot.isValid else { throw SimulationFailure.invalid }
        for domain in LocationSimulationSchema.domains {
            for key in LocationSimulationSchema.keys {
                let number = snapshot.values[domain]![key]!.number
                // A plist real literal avoids `-float` narrowing to Float32.
                let operation = number == nil ? "delete" : "write"
                let arguments = try [key] + (number.map { [try SimulationPreferencePlist.literal($0)] } ?? [])
                _ = try checked(defaults(domain, operation: operation, arguments: arguments), operation: operation)
            }
        }
    }

    func refresh() throws {
        // Gracefully restart only the two named system services. No security
        // settings, TCC database, Find My daemon or user app is changed.
        do { _ = try run("/usr/bin/killall", ["-TERM", "-u", "root", "cfprefsd"]) }
        catch { throw SimulationFailure.commandFailed("restartPreferences:" + SimulationFailure.detail(error)) }
        Thread.sleep(forTimeInterval: 2)
        let old = try run("/usr/bin/pgrep", ["-u", "_locationd", "-x", "locationd"]).1
        do { _ = try run("/usr/bin/killall", ["-TERM", "-u", "_locationd", "locationd"]) }
        catch { throw SimulationFailure.commandFailed("restartLocation:" + SimulationFailure.detail(error)) }
        for _ in 0..<40 {
            Thread.sleep(forTimeInterval: 0.2)
            let current = try run("/usr/bin/pgrep", ["-u", "_locationd", "-x", "locationd"], allowFailure: true)
            if current.0 == 0, !current.1.isEmpty, current.1 != old {
                _ = try run("/usr/bin/notifyutil", ["-p", "com.apple.locationd/Prefs"])
                return
            }
        }
        throw SimulationFailure.commandFailed("restartLocation:timeout")
    }
}

// Root-only, no-follow state directory; a kernel lock serializes set/reset
// across app copies. The original backup survives failures and app updates.
final class SecureSimulationBackup: SimulationBackup {
    private let directory: Int32
    private let lock: Int32

    init(path: String = LocationSimulationSchema.statePath, owner: uid_t = 0) throws {
        if mkdir(path, 0o700) != 0 && errno != EEXIST { throw SimulationFailure.unsafeState }
        directory = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw SimulationFailure.unsafeState }
        var info = stat()
        guard fstat(directory, &info) == 0, info.st_uid == owner, info.st_mode & 0o777 == 0o700 else {
            close(directory); throw SimulationFailure.unsafeState
        }
        lock = openat(directory, "lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { close(directory); throw SimulationFailure.unsafeState }
        guard fstat(lock, &info) == 0, info.st_uid == owner, info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o777 == 0o600, info.st_nlink == 1 else {
            close(lock); close(directory); throw SimulationFailure.unsafeState
        }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { close(lock); close(directory); throw SimulationFailure.busy }
        self.owner = owner
    }
    private let owner: uid_t
    deinit { close(lock); close(directory) }

    func load() throws -> SimulationSnapshot? {
        let fd = openat(directory, "original.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 { if errno == ENOENT { return nil }; throw SimulationFailure.unsafeState }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == owner, info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o777 == 0o600, info.st_nlink == 1, info.st_size > 0, info.st_size <= 8192 else { throw SimulationFailure.unsafeState }
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
        guard Darwin.read(fd, &bytes, bytes.count) == bytes.count else { throw SimulationFailure.unsafeState }
        let decoded = try JSONDecoder().decode(SimulationSnapshot.self, from: Data(bytes))
        guard decoded.isValid else { throw SimulationFailure.unsafeState }
        return decoded
    }

    func create(_ snapshot: SimulationSnapshot) throws {
        guard snapshot.isValid else { throw SimulationFailure.invalid }
        let bytes = try JSONEncoder().encode(snapshot)
        // A crash leaves a temporary file, never a half-written original backup.
        let name = "pending-" + UUID().uuidString
        let fd = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw SimulationFailure.unsafeState }
        defer { close(fd); unlinkat(directory, name, 0) }
        let written = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        guard written == bytes.count, fsync(fd) == 0,
              linkat(directory, name, directory, "original.json", 0) == 0 else { throw SimulationFailure.unsafeState }
        // Remove the temporary hard link before exposing a nlink==1 backup.
        guard unlinkat(directory, name, 0) == 0, fsync(directory) == 0 else { throw SimulationFailure.unsafeState }
    }

    func remove() throws {
        guard try load() != nil else { return }
        guard unlinkat(directory, "original.json", 0) == 0, fsync(directory) == 0 else { throw SimulationFailure.unsafeState }
    }
}
