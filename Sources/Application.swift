import AppKit
import Combine
import SwiftUI

private let reopenMeridian = Notification.Name("org.codex.worldclock.reopen")

final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ClockDropdownPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { orderOut(nil) } else { super.keyDown(with: event) }
    }
}

struct LaunchOptions {
    var snapshot: String?
    var fixedInstant: Date?
    var localZone: TimeZone?
    var preview = false

    init(arguments: [String]) {
        let info = Bundle.main.infoDictionary ?? [:]
        func value(_ key: String) -> String? {
            guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        snapshot = value("--snapshot") ?? info["WorldClockSnapshot"] as? String
        if let date = value("--fixture-date") ?? info["WorldClockFixtureDate"] as? String {
            fixedInstant = ISO8601DateFormatter().date(from: date)
        }
        if let zone = value("--fixture-local-zone") ?? info["WorldClockFixtureZone"] as? String {
            localZone = TimeZone(identifier: zone)
        }
        preview = arguments.contains("--preview") || (info["WorldClockPreview"] as? Bool == true)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let options: LaunchOptions
    let store: ClockStore
    let updates: UpdateController
    private var panel: DesktopPanel!
    private var manager: NSWindow?
    private var statusItem: NSStatusItem!
    private var subscriptions = Set<AnyCancellable>()
    private var applyingLayout = false
    private var statusWindow: ClockDropdownPanel?
    private var statusFromMenuBar = false
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var reopenObserver: NSObjectProtocol?

    init(options: LaunchOptions) {
        self.options = options
        self.store = ClockStore(fixedInstant: options.fixedInstant,
            localZone: options.localZone ?? .current,
            persistent: options.fixedInstant == nil && options.snapshot == nil && !options.preview)
        self.updates = UpdateController(preview: options.preview || options.fixedInstant != nil)
        super.init()
        if options.fixedInstant != nil {
            if Bundle.main.object(forInfoDictionaryKey: "WorldClockFixtureWeather") as? Bool == true {
                store.loadPreviewWeather()
            } else {
                store.showWeather = false
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupApplicationMenu()
        setupPanel()
        setupMenuBar()
        reopenObserver = DistributedNotificationCenter.default().addObserver(forName: reopenMeridian,
            object: Bundle.main.bundleIdentifier, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    _ = self.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
                }
            }
        observeChanges()
        store.start()
        if store.desktopVisible { panel.orderFrontRegardless() }

        if let path = options.snapshot {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.capture(to: path)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        store.desktopVisible = true
        panel?.orderFrontRegardless()
        return true
    }

    private func setupPanel() {
        panel = DesktopPanel(contentRect: NSRect(origin: .zero, size: store.panelSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = store.t("世界时钟")
        panel.identifier = NSUserInterfaceItemIdentifier("world-clock-desktop")
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = NSHostingView(rootView: WorldClockView(store: store,
            manage: { [weak self] in self?.showManager() },
            showStatus: { [weak self] in self?.showStatusMenu(nil) },
            resetPosition: { [weak self] in self?.resetPosition() },
            quit: { NSApp.terminate(nil) }))
        updateLayout()
        if !options.preview && options.snapshot == nil,
           let position = UserDefaults.standard.string(forKey: "panelPosition") {
            panel.setFrameOrigin(NSPointFromString(position))
            keepOnScreen()
        } else {
            resetPosition()
        }
        updateWindowBehavior()
        panel.delegate = self
    }

    private func setupApplicationMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu()
        let viewClocks = app.addItem(withTitle: store.t("查看状态栏时钟"), action: #selector(showStatusMenu(_:)), keyEquivalent: "t")
        viewClocks.target = self
        viewClocks.keyEquivalentModifierMask = [.command, .shift]
        app.addItem(withTitle: store.t("管理地区…"), action: #selector(showManager), keyEquivalent: ",").target = self
        app.addItem(withTitle: store.t("检查更新…"), action: #selector(checkForUpdates), keyEquivalent: "").target = self
        app.addItem(.separator())
        app.addItem(withTitle: store.t("退出世界时钟"), action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = app
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: store.t("编辑"))
        edit.addItem(withTitle: store.t("撤销"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(.separator())
        edit.addItem(withTitle: store.t("剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: store.t("复制"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: store.t("粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: store.t("全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = Bundle.main.url(forResource: "StatusIcon", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
            image?.size = NSSize(width: 18, height: 18)
            image?.isTemplate = false
            button.image = image
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.toolTip = store.t("世界时钟 · 管理桌面上的多时区时钟")
            button.setAccessibilityLabel(store.t("世界时钟菜单"))
        }
        statusItem.button?.target = self
        statusItem.button?.action = #selector(showStatusMenu(_:))
        updateStatusBar()
    }

    private func updateStatusBar() {
        guard statusItem != nil else { return }
        let clocks = store.statusRegions.map { store.snapshot($0) }
        let title: String
        if clocks.count == 1, let clock = clocks.first, clock.isLocal {
            let weather = store.showWeather && !store.weatherStale(.local) ? store.weather(.local).map { " \($0.temperatureLabel)" } ?? "" : ""
            title = "\(clock.date) \(clock.time)\(weather)"
        } else {
            title = store.statusRegions.map { region in
                let clock = store.snapshot(region)
                let weather = store.showWeather && !store.weatherStale(region) ? store.weather(region).map { " \($0.temperatureLabel)" } ?? "" : ""
                return "\(clock.city) \(clock.date) \(clock.time)\(weather)"
            }.joined(separator: "  ·  ")
        }
        if statusItem.button?.title != title { statusItem.button?.title = title }
        statusItem.button?.toolTip = "Meridian\n" + store.regions.map {
            let clock = store.snapshot($0)
            return "\(clock.city)  \(clock.date) \(clock.weekday)  \(clock.time)"
        }.joined(separator: "\n")
        statusItem.button?.setAccessibilityLabel(title.isEmpty ? store.t("世界时钟菜单") : "Meridian, \(title)")
        if statusWindow?.isVisible == true { layoutStatusWindow() }
        if options.preview, let path = options.snapshot {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.capture(to: path) }
        }
    }

    @objc private func showStatusMenu(_ sender: Any?) {
        if statusWindow?.isVisible == true { statusWindow?.orderOut(nil); return }
        statusFromMenuBar = sender is NSStatusBarButton || sender is NSMenuItem
        layoutStatusWindow()
        NSApp.activate(ignoringOtherApps: true)
        statusWindow?.makeKeyAndOrderFront(nil)
        if localClickMonitor == nil {
            localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self else { return event }
                if event.window !== self.statusWindow && event.window !== self.statusItem.button?.window {
                    self.statusWindow?.orderOut(nil)
                }
                return event
            }
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.statusWindow?.orderOut(nil)
            }
        }
        if options.preview, let path = options.snapshot {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.capture(to: path) }
        }
    }

    private func layoutStatusWindow() {
        var anchor = NSRect(x: panel.frame.maxX - 75, y: panel.frame.maxY - 36, width: 32, height: 30)
        if statusFromMenuBar, let button = statusItem.button, let window = button.window {
            anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? panel.screen ?? NSScreen.main
        guard let screen else { return }
        let bounds = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let listHeight = min(CGFloat(store.regions.count * (store.showWeather ? 72 : 55) + 10), max(80, bounds.height - 152))
        let size = NSSize(width: 286, height: listHeight + 152)
        let root = StatusPopoverView(store: store, updates: updates, clockListHeight: listHeight,
            manage: { [weak self] in self?.statusWindow?.orderOut(nil); self?.showManager() },
            resetPosition: { [weak self] in self?.resetPosition() }, quit: { NSApp.terminate(nil) })
        if statusWindow == nil {
            let window = ClockDropdownPanel(contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.title = "Meridian · All clocks"
            window.identifier = NSUserInterfaceItemIdentifier("meridian-dropdown")
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.level = .popUpMenu
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.appearance = NSAppearance(named: .darkAqua)
            let host = NSHostingView(rootView: root)
            host.sizingOptions = []
            host.autoresizingMask = [.width, .height]
            window.contentView = host
            statusWindow = window
        } else if let host = statusWindow?.contentView as? NSHostingView<StatusPopoverView> {
            host.rootView = root
        }
        let frame = DropdownGeometry.frame(anchor: anchor, visibleFrame: screen.visibleFrame, size: size)
        statusWindow?.setFrame(frame, display: true)
        statusWindow?.contentView?.frame = NSRect(origin: .zero, size: size)
    }

    private func observeChanges() {
        store.$regions.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.updateLayout()
            self?.updateStatusBar()
        }.store(in: &subscriptions)
        store.$desktopRegionIDs.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.updateLayout()
        }.store(in: &subscriptions)
        store.$statusRegionIDs.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.updateStatusBar()
        }.store(in: &subscriptions)
        store.$language.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.setupApplicationMenu()
            self?.manager?.title = self?.store.t("世界时钟 · 管理地区") ?? "Meridian"
            self?.updateStatusBar()
        }.store(in: &subscriptions)
        store.$instant.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.updateStatusBar()
        }.store(in: &subscriptions)
        store.$weatherByZone.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.updateStatusBar() }.store(in: &subscriptions)
        store.$weatherFailures.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.updateStatusBar() }.store(in: &subscriptions)
        store.$showWeather.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.updateStatusBar() }.store(in: &subscriptions)
        store.$desktopVisible.dropFirst().receive(on: RunLoop.main).sink { [weak self] visible in
            if visible { self?.panel.orderFrontRegardless() } else { self?.panel.orderOut(nil) }
        }.store(in: &subscriptions)
        store.$alwaysOnTop.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.updateWindowBehavior()
        }.store(in: &subscriptions)
        store.$positionLocked.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.updateWindowBehavior()
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                self?.updateLayout()
            }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self, self.options.fixedInstant == nil else { return }
                self.store.instant = Date()
                self.store.refreshWeather()
            }.store(in: &subscriptions)
    }

    private func updateLayout() {
        guard panel != nil, !applyingLayout else { return }
        applyingLayout = true
        defer { applyingLayout = false }
        let availableWidth = (panel.screen ?? NSScreen.main)?.visibleFrame.width ?? 1440
        let columns = max(1, min(store.desktopRegions.count, Int((availableWidth - 48) / 180)))
        if store.columns != columns { store.columns = columns }
        let oldFrame = panel.frame
        let size = store.panelSize
        panel.setFrame(NSRect(x: oldFrame.minX, y: oldFrame.maxY - size.height,
            width: size.width, height: size.height), display: true)
        keepOnScreen()
    }

    private func updateWindowBehavior() {
        panel.isMovableByWindowBackground = !store.positionLocked
        if store.alwaysOnTop || options.preview || options.snapshot != nil {
            panel.level = .floating
        } else {
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
    }

    private func keepOnScreen() {
        guard let frame = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        var origin = panel.frame.origin
        origin.x = min(max(origin.x, frame.minX + 16), frame.maxX - panel.frame.width - 16)
        origin.y = min(max(origin.y, frame.minY + 16), frame.maxY - panel.frame.height - 16)
        panel.setFrameOrigin(origin)
    }

    func windowDidMove(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel,
              !applyingLayout,
              options.snapshot == nil, options.fixedInstant == nil, !options.preview else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: "panelPosition")
    }

    @objc private func resetPosition() {
        guard let screen = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: screen.midX - panel.frame.width / 2,
            y: screen.maxY - panel.frame.height - 75))
    }

    @objc private func toggleVisible() {
        store.desktopVisible.toggle()
    }
    @objc private func toggleTop() { store.alwaysOnTop.toggle() }
    @objc private func toggleLock() { store.positionLocked.toggle() }
    @objc private func checkForUpdates() { updates.check(language: store.language) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showManager() {
        if manager == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 760),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = store.t("世界时钟 · 管理地区")
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(rootView: SettingsRootView(store: store, updates: updates,
                done: { [weak self] in self?.manager?.close() }))
            window.center()
            manager = window
        }
        store.notice = nil
        manager?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func capture(to path: String) {
        guard let view = panel.contentView else { exit(2) }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            fputs("Unable to create snapshot bitmap\n", stderr)
            exit(2)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        do {
            guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(2) }
            try data.write(to: URL(fileURLWithPath: path))
            let base = URL(fileURLWithPath: path).deletingPathExtension().path
            if let button = statusItem.button,
               let statusBitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds) {
                button.cacheDisplay(in: button.bounds, to: statusBitmap)
                if let png = statusBitmap.representation(using: .png, properties: [:]) {
                    try png.write(to: URL(fileURLWithPath: base + "-status.png"))
                }
            }
            if let window = statusWindow, window.isVisible, let content = window.contentView,
               let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    try data.write(to: URL(fileURLWithPath: base + "-popover.png"))
                }
            }
            let state: [String: Any] = ["statusTitle": statusItem.button?.title ?? "",
                "statusButtonHasWindow": statusItem.button?.window != nil,
                "statusWindowVisible": statusItem.button?.window?.isVisible ?? false,
                "statusWindowFrame": (statusItem.button?.window).map { NSStringFromRect($0.frame) } ?? "none",
                "dropdownShown": statusWindow?.isVisible ?? false,
                "desktopRegionIDs": store.desktopRegions.map(\.id),
                "statusRegionIDs": store.statusRegions.map(\.id),
                "panelPosition": NSStringFromPoint(panel.frame.origin)]
            try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: base + "-state.json"))
            print("Snapshot saved: \(path)")
            if !options.preview { NSApp.terminate(nil) }
        } catch {
            fputs("Snapshot error: \(error)\n", stderr)
            exit(2)
        }
    }
}

@main
struct MeridianMain {
    @MainActor static func main() {
        let bundleID = Bundle.main.bundleIdentifier ?? "org.codex.worldclock"
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let lockURL = support.appendingPathComponent("Meridian/instances", isDirectory: true)
            .appendingPathComponent(bundleID + ".lock")
        let instance: SingleInstanceLock
        do { instance = try SingleInstanceLock(fileURL: lockURL) }
        catch {
            let alert = NSAlert()
            alert.messageText = "Meridian could not start"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return
        }
        guard instance.isOwner else {
            DistributedNotificationCenter.default().postNotificationName(reopenMeridian,
                object: bundleID, userInfo: nil, deliverImmediately: true)
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })?
                .activate(options: [])
            return
        }
        let options = LaunchOptions(arguments: CommandLine.arguments)
        let application = NSApplication.shared
        let delegate = AppDelegate(options: options)
        application.delegate = delegate
        withExtendedLifetime((delegate, instance)) { application.run() }
    }
}
