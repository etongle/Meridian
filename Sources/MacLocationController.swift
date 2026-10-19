import AppKit
import CoreLocation
import SwiftUI

@MainActor
final class MacLocationController: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var busy = false
    @Published private(set) var status = "尚未应用模拟定位"
    @Published private(set) var appliedPlace: SimulatedPlace?
    @Published private(set) var needsRestore: Bool
    @Published private(set) var verifying = false
    @Published private(set) var diagnosticDetail: String?
    @Published var selectedTab = 0
    private let defaults: UserDefaults
    private let manager = CLLocationManager()
    private var verificationStarted: Date?
    private var verificationTarget: SimulatedPlace?
    private var verificationTimeout: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        needsRestore = defaults.bool(forKey: "macLocationNeedsRestore")
        if let data = defaults.data(forKey: "macLocationTarget"),
           let saved = try? JSONDecoder().decode(SimulatedPlace.self, from: data), saved.isValid {
            appliedPlace = saved
        }
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        if needsRestore { status = "上次模拟定位可能仍在生效，请验证或恢复" }
    }

    func apply(_ place: SimulatedPlace) {
        guard place.isValid, !busy else { return }
        perform(operation: "apply", place: place)
    }

    func restore(completion: ((Bool) -> Void)? = nil) {
        guard !busy else { completion?(false); return }
        perform(operation: "restore", place: nil, completion: completion)
    }
    func diagnose() { guard !busy else { return }; perform(operation: "diagnose", place: nil) }

    private func perform(operation: String, place: SimulatedPlace?, completion: ((Bool) -> Void)? = nil) {
        stopVerification()
        busy = true
        diagnosticDetail = nil
        let previousNeedsRestore = needsRestore
        // Save the recovery indicator before invoking the privileged process, so
        // a crash after a successful write cannot silently forget the session.
        if operation == "apply" { needsRestore = true; defaults.set(true, forKey: "macLocationNeedsRestore") }
        status = operation == "diagnose" ? "等待管理员授权并检查兼容性…" : operation == "restore" ? "等待管理员授权并恢复设置…" : "等待管理员授权并应用设置…"
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/MeridianLocationHelper").path
        Task { [weak self] in
            let reply = await Task.detached(priority: .userInitiated) { Self.authorized(helper: helper, operation: operation, place: place) }.value
            guard let self else { return }
            self.busy = false
            self.diagnosticDetail = reply.detail
            if operation == "diagnose" {
                self.status = reply.code == "diagnosticReady" ? "可读取系统模拟设置；仍需应用和定位验证" : "兼容性检查未通过，未修改系统定位"
                return
            }
            // Cancellation never changes the remembered session or original backup.
            if reply.code == "cancelled" {
                self.needsRestore = previousNeedsRestore
                self.defaults.set(previousNeedsRestore, forKey: "macLocationNeedsRestore")
            } else {
                self.needsRestore = reply.recoveryAvailable
                self.defaults.set(self.needsRestore, forKey: "macLocationNeedsRestore")
            }
            switch reply.code {
            case "applied":
                self.appliedPlace = place
                if let data = try? JSONEncoder().encode(place) { self.defaults.set(data, forKey: "macLocationTarget") }
                self.status = "设置已应用，尚未验证系统定位"
            case "restored", "noBackup":
                self.appliedPlace = nil
                self.defaults.removeObject(forKey: "macLocationTarget")
                self.status = reply.code == "restored" ? "原定位设置已恢复，请让其他应用重新获取定位" : "没有 Meridian 定位备份，系统设置未更改"
            case "cancelled": self.status = "已取消授权，定位未更改"
            case "rolledBack": self.status = "应用失败，本次更改已回退；原始备份仍保留"
            case "recoveryRequired": self.status = "恢复尚未完成，备份已保留，请再次点击恢复原定位"
            case "backupFailed": self.status = "无法安全读取或保存原设置，已停止操作"
            default: self.status = "操作未完成，不能确认定位已改变；可尝试恢复原定位"
            }
            completion?(["restored", "noBackup"].contains(reply.code))
        }
    }

    nonisolated private static func authorized(helper: String, operation: String, place: SimulatedPlace?) -> LocationHelperReply {
        guard FileManager.default.isExecutableFile(atPath: helper),
              let script = LocationAuthorizationCommand.script(helper: helper, operation: operation, place: place) else {
            return .init(code: "unavailable", recoveryAvailable: true)
        }
        // Standard Additions supplies a one-off macOS administrator prompt. No
        // password is collected and no daemon or passwordless rule is installed.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "AppleScript"]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        do {
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: Data(script.utf8))
            try input.fileHandleForWriting.close()
            let bytes = output.fileHandleForReading.readDataToEndOfFile()
            let error = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let text = String(decoding: error, as: UTF8.self)
                return .init(code: text.contains("(-128)") ? "cancelled" : "failed", recoveryAvailable: true)
            }
            guard bytes.count <= 4096, let reply = try? JSONDecoder().decode(LocationHelperReply.self, from: bytes) else {
                return .init(code: "failed", recoveryAvailable: true)
            }
            return reply
        } catch { return .init(code: "failed", recoveryAvailable: true) }
    }

    func verify(target: SimulatedPlace? = nil) {
        guard !busy, !verifying, let target = target ?? appliedPlace, target.isValid else { return }
        verifying = true
        verificationTarget = target
        verificationStarted = Date()
        status = "正在读取本机定位，请在系统提示中允许定位权限…"
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways: manager.requestLocation()
        default: stopVerification(); status = "请在系统设置中允许 Meridian 使用定位服务"
        }
        verificationTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, let self, self.verifying else { return }
            self.stopVerification()
            self.status = "未收到新的系统定位，不能确认模拟已生效"
        }
    }

    private func stopVerification() {
        verifying = false
        verificationStarted = nil
        verificationTarget = nil
        verificationTimeout?.cancel()
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, self.verifying else { return }
            if self.manager.authorizationStatus == .authorizedAlways { self.manager.requestLocation() }
            else if [.denied, .restricted].contains(self.manager.authorizationStatus) {
                self.stopVerification(); self.status = "请在系统设置中允许 Meridian 使用定位服务"
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            guard let self, self.verifying, let started = self.verificationStarted, let target = self.verificationTarget,
                  let location = locations.last, location.horizontalAccuracy >= 0,
                  location.timestamp >= started.addingTimeInterval(-2) else { return }
            let distance = location.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
            self.stopVerification()
            self.status = distance <= 1000 && location.horizontalAccuracy <= 1000 ? "Core Location 已返回目标地区；请在目标应用中刷新定位" : "系统返回的位置与目标地区不同，模拟尚未验证成功"
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.verifying else { return }
            self.stopVerification(); self.status = "读取定位失败，不能确认模拟已生效"
        }
    }
}
