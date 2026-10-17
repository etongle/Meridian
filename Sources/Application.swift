import AppKit
import Combine
import SwiftUI

private let reopenMeridian = Notification.Name("org.codex.worldclock.reopen")

final class DesktopPanel: NSPanel {
    var dragBegan: (() -> Void)?
    var dragEnded: (() -> Void)?
    var closeRequested: (() -> Void)?
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var movedDuringDrag = false
    var isDragging: Bool { dragStart != nil }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func performClose(_ sender: Any?) { closeRequested?() }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, isMovable,
           event.locationInWindow.y >= frame.height - 35,
           event.locationInWindow.x < frame.width - 128 {
            dragStart = (convertPoint(toScreen: event.locationInWindow), frame.origin)
            movedDuringDrag = false
            dragBegan?()
            return
        }
        if let start = dragStart {
            if event.type == .leftMouseDragged {
                let mouse = convertPoint(toScreen: event.locationInWindow)
                guard movedDuringDrag || hypot(mouse.x - start.mouse.x, mouse.y - start.mouse.y) >= 3 else { return }
                movedDuringDrag = true
                setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x,
                    y: start.origin.y + mouse.y - start.mouse.y))
                return
            }
            if event.type == .leftMouseUp {
                dragStart = nil
                if movedDuringDrag { dragEnded?() }
                return
            }
        }
        super.sendEvent(event)
    }
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
    private var panels: [String: DesktopPanel] = [:]
    private var panelPositionKeys: [String: String] = [:]
    private var statusAnchorID = "combined"
    private var panel: DesktopPanel? { panels[statusAnchorID] ?? panels["combined"] ?? store.desktopRegions.compactMap { panels[$0.id] }.first }
    private var manager: NSWindow?
    private var statusItem: NSStatusItem!
    private var subscriptions = Set<AnyCancellable>()
    private var applyingLayout = false
    private var statusWindow: ClockDropdownPanel?
    private var statusFromMenuBar = false
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var reopenObserver: NSObjectProtocol?
    private var desktopRevealed = false

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
        updateLayout()
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
        updateDesktopVisibility()

        if let path = options.snapshot {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.capture(to: path)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDesktop()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func makePanel(id: String, metrics: DesktopLayoutMetrics) -> DesktopPanel {
        let panel = DesktopPanel(contentRect: NSRect(origin: .zero, size: metrics.size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = store.t("世界时钟")
        panel.identifier = NSUserInterfaceItemIdentifier("world-clock-desktop-\(id)")
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.dragBegan = { [weak self] in self?.statusWindow?.orderOut(nil) }
        panel.dragEnded = { [weak self] in self?.finishDesktopDrag(id: id) }
        panel.closeRequested = { [weak self] in self?.store.closeDesktopPanel(id) }
        let host = NSHostingView(rootView: desktopView(id: id, metrics: metrics))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.delegate = self
        return panel
    }

    private func desktopView(id: String, metrics: DesktopLayoutMetrics) -> WorldClockView {
        WorldClockView(store: store, panelID: id, metrics: metrics,
            manage: { [weak self] in self?.showManager() },
            showStatus: { [weak self] in
                self?.statusAnchorID = id
                self?.showStatusMenu(nil)
            },
            resetPosition: { [weak self] in self?.resetPosition() },
            quit: { NSApp.terminate(nil) })
    }

    private func setupApplicationMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu()
        let viewClocks = app.addItem(withTitle: store.t("查看状态栏时钟"), action: #selector(showStatusMenu(_:)), keyEquivalent: "t")
        viewClocks.target = self
        viewClocks.keyEquivalentModifierMask = [.command, .shift]
        let desktop = app.addItem(withTitle: store.t("显示桌面时钟"), action: #selector(showDesktop), keyEquivalent: "d")
        desktop.target = self
        desktop.keyEquivalentModifierMask = [.command, .shift]
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
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        installClickMonitors()
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
        }.joined(separator: "\n") + "\n\n" + store.t("点击展开菜单，选择“打开”显示桌面时钟。")
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
        if options.preview, let path = options.snapshot {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.capture(to: path) }
        }
    }

    private func installClickMonitors() {
        if localClickMonitor == nil {
            localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self else { return event }
                if event.window !== self.statusWindow && event.window !== self.statusItem.button?.window {
                    self.statusWindow?.orderOut(nil)
                }
                if !self.panels.values.contains(where: { $0 === event.window }) && event.window !== self.statusWindow
                    && event.window !== self.statusItem.button?.window && event.window !== self.manager {
                    self.endDesktopReveal()
                }
                return event
            }
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.statusWindow?.orderOut(nil)
                self?.endDesktopReveal()
            }
        }
    }

    private func layoutStatusWindow() {
        let desktopFrame = panel?.frame ?? .zero
        var anchor = NSRect(x: desktopFrame.maxX - 98, y: desktopFrame.maxY - 36, width: 32, height: 30)
        if statusFromMenuBar, let button = statusItem.button, let window = button.window {
            anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? panel?.screen ?? NSScreen.main
        guard let screen else { return }
        let bounds = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let chromeHeight = StatusPopoverView.chromeHeight
        let listHeight = min(CGFloat(store.regions.count * (store.showWeather ? 72 : 55) + 10), max(0, bounds.height - chromeHeight))
        let size = NSSize(width: 286, height: listHeight + chromeHeight)
        let root = StatusPopoverView(store: store, updates: updates, clockListHeight: listHeight,
            manage: { [weak self] in self?.statusWindow?.orderOut(nil); self?.showManager() },
            showDesktop: { [weak self] in self?.showDesktop() },
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
        store.$desktopLayout.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.updateLayout()
            self?.updateStatusBar()
        }.store(in: &subscriptions)
        store.$dismissedDesktopIDs.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.updateDesktopVisibility()
        }.store(in: &subscriptions)
        store.$statusRegionIDs.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.updateStatusBar()
        }.store(in: &subscriptions)
        store.$language.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.setupApplicationMenu()
            self?.manager?.title = self?.store.t("世界时钟 · 管理地区") ?? "Meridian"
            self?.updateStatusBar()
            self?.updateLayout()
        }.store(in: &subscriptions)
        store.$instant.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.updateStatusBar()
        }.store(in: &subscriptions)
        store.$weatherByZone.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.updateStatusBar() }.store(in: &subscriptions)
        store.$weatherFailures.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.updateStatusBar() }.store(in: &subscriptions)
        store.$showWeather.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.updateStatusBar() }.store(in: &subscriptions)
        store.$desktopVisible.dropFirst().receive(on: RunLoop.main).sink { [weak self] visible in
            self?.updateDesktopVisibility()
            if !visible { self?.endDesktopReveal() }
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
                self.store.seconds.instant = self.store.instant
                self.store.refreshWeather()
            }.store(in: &subscriptions)
    }

    private var savesPositions: Bool {
        options.snapshot == nil && options.fixedInstant == nil && !options.preview
    }

    private func updateLayout() {
        guard !applyingLayout else { return }
        applyingLayout = true
        defer { applyingLayout = false }
        let anchor = panel?.frame
        let ids = store.desktopLayout.panelIDs(for: store.desktopRegions.map(\.id))
        for id in Array(panels.keys) where !ids.contains(id) || panelPositionKeys[id] != store.desktopLayout.positionKey(for: id) {
            guard let old = panels.removeValue(forKey: id) else { continue }
            savePanelPosition(old, id: id)
            old.delegate = nil
            old.orderOut(nil)
            old.close()
            panelPositionKeys.removeValue(forKey: id)
        }
        for (index, id) in ids.enumerated() {
            let existing = panels[id]
            let restored = existing == nil ? savedPosition(id: id) : nil
            let reference = existing?.frame ?? restored.map { NSRect(origin: $0, size: NSSize(width: 220, height: 210)) } ?? anchor ?? .zero
            let screen = DesktopGeometry.screen(for: reference, in: NSScreen.screens.map(\.visibleFrame))
                ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let metrics = DesktopLayoutMetrics(layout: store.desktopLayout,
                clockCount: id == "combined" ? store.desktopRegions.count : 1, availableSize: screen.size)
            let desktop = existing ?? makePanel(id: id, metrics: metrics)
            panels[id] = desktop
            panelPositionKeys[id] = store.desktopLayout.positionKey(for: id)
            desktop.title = id == "combined" ? "Meridian" : "Meridian · " + (store.desktopRegions.first { $0.id == id }?.name(local: store.localZone, language: store.language) ?? id)
            let oldFrame = desktop.frame
            let newFrame = NSRect(x: oldFrame.minX, y: oldFrame.maxY - metrics.size.height,
                width: metrics.size.width, height: metrics.size.height)
            desktop.setFrame(newFrame, display: false)
            if let host = desktop.contentView as? NSHostingView<WorldClockView> {
                host.rootView = desktopView(id: id, metrics: metrics)
                host.frame = NSRect(origin: .zero, size: metrics.size)
            }
            if existing == nil {
                if let origin = restored {
                    desktop.setFrameOrigin(origin)
                } else {
                    desktop.setFrameOrigin(defaultOrigin(index: index, total: ids.count,
                        size: metrics.size, screen: screen, anchor: anchor))
                }
            }
            keepOnScreen(desktop)
            savePanelPosition(desktop, id: id)
        }
        if panels[statusAnchorID] == nil { statusAnchorID = ids.first ?? "combined" }
        updateWindowBehavior()
        updateDesktopVisibility()
        if options.preview, let path = options.snapshot {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.capture(to: path) }
        }
    }

    private func updateWindowBehavior() {
        for desktop in panels.values {
            desktop.isMovable = !store.positionLocked
            desktop.isMovableByWindowBackground = false
            if store.alwaysOnTop || desktopRevealed || options.preview || options.snapshot != nil {
                desktop.level = .floating
            } else {
                desktop.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            }
        }
    }

    private func updateDesktopVisibility() {
        for (id, desktop) in panels {
            if store.panelVisible(id) { desktop.orderFrontRegardless() } else { desktop.orderOut(nil) }
        }
    }

    private func keepOnScreen(_ desktop: DesktopPanel) {
        guard let screen = DesktopGeometry.screen(for: desktop.frame, in: NSScreen.screens.map(\.visibleFrame)) else { return }
        desktop.setFrameOrigin(DesktopGeometry.origin(for: desktop.frame, in: screen, snap: false))
    }

    private func finishDesktopDrag(id: String) {
        updateLayout()
        guard let desktop = panels[id],
              let screen = DesktopGeometry.screen(for: desktop.frame, in: NSScreen.screens.map(\.visibleFrame)) else { return }
        desktop.setFrameOrigin(DesktopGeometry.origin(for: desktop.frame, in: screen, snap: store.snapToEdges))
        savePanelPosition(desktop, id: id)
        if options.preview, let path = options.snapshot { capture(to: path) }
    }

    func windowDidMove(_ notification: Notification) {
        guard let desktop = notification.object as? DesktopPanel,
              let id = panels.first(where: { $0.value === desktop })?.key,
              !applyingLayout else { return }
        if !desktop.isDragging { savePanelPosition(desktop, id: id) }
        if statusWindow?.isVisible == true && !statusFromMenuBar { layoutStatusWindow() }
    }

    private func savedPosition(id: String) -> NSPoint? {
        guard savesPositions else { return nil }
        let positions = UserDefaults.standard.dictionary(forKey: "desktopPanelPositions") as? [String: String] ?? [:]
        let key = store.desktopLayout.positionKey(for: id)
        let value = positions[key] ?? (key == "horizontal" ? UserDefaults.standard.string(forKey: "panelPosition") : nil)
        guard let value else { return nil }
        let point = NSPointFromString(value)
        return point.x.isFinite && point.y.isFinite ? point : nil
    }

    private func savePanelPosition(_ desktop: DesktopPanel, id: String) {
        guard savesPositions, let key = panelPositionKeys[id] else { return }
        var positions = UserDefaults.standard.dictionary(forKey: "desktopPanelPositions") as? [String: String] ?? [:]
        positions[key] = NSStringFromPoint(desktop.frame.origin)
        UserDefaults.standard.set(positions, forKey: "desktopPanelPositions")
        if key == "horizontal" { UserDefaults.standard.set(NSStringFromPoint(desktop.frame.origin), forKey: "panelPosition") }
    }

    private func defaultOrigin(index: Int, total: Int, size: NSSize, screen: NSRect, anchor: NSRect?) -> NSPoint {
        let gap: CGFloat = 12
        let columns = min(total, max(1, Int((screen.width - 32 + gap) / (size.width + gap))))
        let rows = Int(ceil(Double(total) / Double(columns)))
        let clusterWidth = CGFloat(columns) * (size.width + gap) - gap
        let clusterHeight = CGFloat(rows) * (size.height + gap) - gap
        let left = min(max(anchor?.minX ?? (screen.midX - clusterWidth / 2), screen.minX + 16), max(screen.minX + 16, screen.maxX - clusterWidth - 16))
        let top = max(min(anchor?.maxY ?? (screen.maxY - 75), screen.maxY - 16), min(screen.maxY - 16, screen.minY + clusterHeight + 16))
        return NSPoint(x: left + CGFloat(index % columns) * (size.width + gap),
            y: top - CGFloat(index / columns) * (size.height + gap) - size.height)
    }

    @objc private func resetPosition() {
        let ids = store.desktopLayout.panelIDs(for: store.desktopRegions.map(\.id))
        guard let screen = NSScreen.main?.visibleFrame else { return }
        for (index, id) in ids.enumerated() {
            guard let desktop = panels[id] else { continue }
            desktop.setFrameOrigin(defaultOrigin(index: index, total: ids.count,
                size: desktop.frame.size, screen: screen, anchor: nil))
            keepOnScreen(desktop)
            savePanelPosition(desktop, id: id)
        }
        showDesktop()
    }

    @objc private func showDesktop() {
        statusWindow?.orderOut(nil)
        store.revealDesktop()
        desktopRevealed = true
        updateWindowBehavior()
        for desktop in panels.values { keepOnScreen(desktop) }
        updateDesktopVisibility()
    }

    private func endDesktopReveal() {
        guard desktopRevealed else { return }
        desktopRevealed = false
        updateWindowBehavior()
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
        guard let panel, let view = panel.contentView else { exit(2) }
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
                "desktopVisible": store.desktopVisible,
                "desktopLayout": store.desktopLayout.rawValue,
                "panels": panels.mapValues { ["frame": NSStringFromRect($0.frame), "visible": String($0.isVisible)] },
                "positionLocked": store.positionLocked,
                "snapToEdges": store.snapToEdges,
                "dragTracking": panel.isDragging,
                "panelFrame": NSStringFromRect(panel.frame),
                "screenVisibleFrame": panel.screen.map { NSStringFromRect($0.visibleFrame) } ?? "none",
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
