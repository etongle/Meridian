import Foundation
import Darwin

@main
struct MeridianLocationHelper {
    static func main() {
        var reply = LocationHelperReply(code: "invalid", recoveryAvailable: false)
        let args = Array(CommandLine.arguments.dropFirst())
        // Refuse unprivileged operations before reading any system preferences.
        guard geteuid() == 0 else { emit(.init(code: "administratorRequired", recoveryAvailable: false)); return }
        if args == ["diagnose"] {
            let available = FileManager.default.fileExists(atPath: LocationSimulationSchema.statePath + "/original.json")
            do {
                guard try SystemSimulationPreferences().read().isValid else { throw SimulationFailure.invalid }
                emit(.init(code: "diagnosticReady", recoveryAvailable: available))
            } catch { emit(.init(code: "diagnosticFailed", recoveryAvailable: available, detail: SimulationFailure.detail(error))) }
            return
        }
        var place: SimulatedPlace?
        if args.count == 4, args[0] == "apply", let latitude = Double(args[1]), let longitude = Double(args[2]), let accuracy = Double(args[3]) {
            place = SimulatedPlace(id: "manual", latitude: latitude, longitude: longitude, accuracy: accuracy)
        }
        guard (args == ["restore"]) || (place?.isValid == true) else { emit(reply); return }
        do {
            let backup = try SecureSimulationBackup()
            let transaction = LocationTransaction(preferences: SystemSimulationPreferences(), backup: backup)
            reply = place.map { transaction.apply($0) } ?? transaction.restore()
        } catch { reply = .init(code: "backupFailed", recoveryAvailable: true, detail: "stateDirectory:" + SimulationFailure.detail(error)) }
        emit(reply)
    }

    private static func emit(_ reply: LocationHelperReply) {
        if let data = try? JSONEncoder().encode(reply), let text = String(data: data, encoding: .utf8) { print(text) }
    }
}
