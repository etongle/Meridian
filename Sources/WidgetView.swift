import AppKit
import SwiftUI

// Use the property-wrapper type on SDKs that also export the newer @State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

private enum Palette {
    static let ink = Color(red: 1, green: 0.96, blue: 0.93)
    static let secondary = Color(red: 0.76, green: 0.78, blue: 0.82)
    static let quiet = Color(red: 0.68, green: 0.71, blue: 0.76)
    static let day = Color(red: 0.98, green: 0.81, blue: 0.59)
    static let night = Color(red: 0.67, green: 0.81, blue: 0.96)
}

struct DesktopMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct HoverButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @ViewState private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(hovered ? .white : Palette.quiet)
                .frame(width: 30, height: 30)
                .background(.white.opacity(hovered ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
        .onHover { hovered = $0 }
    }
}

struct WorldClockView: View {
    @ObservedObject var store: ClockStore
    let panelID: String
    let metrics: DesktopLayoutMetrics
    let manage: () -> Void
    let showStatus: () -> Void
    let resetPosition: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: store.positionLocked ? "lock.fill" : "line.3.horizontal")
                        .font(.system(size: 10)).foregroundStyle(Palette.quiet)
                    Text(store.t("世界时钟"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                    Spacer(minLength: 0)
                    if metrics.size.width >= 360 {
                        Text(store.t(store.positionLocked ? "已锁定" : "拖动"))
                            .font(.system(size: 10)).foregroundStyle(Palette.quiet)
                            .padding(.trailing, 12)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 35)
                .overlay(DesktopDragArea(enabled: !store.positionLocked,
                    hint: store.t(store.positionLocked ? "位置已锁定，可在右键菜单解锁。" : (store.snapToEdges ? "拖动标题栏可移动，靠近屏幕边缘自动吸附。" : "拖动标题栏可移动。"))))
                DesktopLayoutMenu(store: store)
                HoverButton(symbol: "globe", label: store.t("查看全部时钟"), action: showStatus)
                HoverButton(symbol: "plus", label: store.t("管理地区"), action: manage)
                HoverButton(symbol: "xmark", label: store.t("收起到状态栏")) { store.closeDesktopPanel(panelID) }
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 35)

            Rectangle().fill(.white.opacity(0.075)).frame(height: 1)

            let regions = panelID == "combined" ? store.desktopRegions : store.desktopRegions.filter { $0.id == panelID }
            if regions.isEmpty {
                Text(store.t("点右上角 +，选择要在桌面显示的时钟"))
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !regions.isEmpty {
                if metrics.needsScrolling {
                    ScrollView(.vertical) { clockGrid(regions) }
                        .frame(maxHeight: .infinity)
                } else {
                    clockGrid(regions)
                }
            }
        }
        .frame(width: metrics.size.width, height: metrics.size.height)
        .background(Color(red: 0.12, green: 0.135, blue: 0.16).opacity(0.88))
        .background(DesktopMaterial())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.24), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .contextMenu {
            DesktopLayoutPicker(store: store)
            Divider()
            Button(store.t("管理地区…"), action: manage)
            Button(store.t("查看状态栏时钟"), action: showStatus)
            Toggle(store.t("始终置顶"), isOn: $store.alwaysOnTop)
            Toggle(store.t("锁定位置"), isOn: $store.positionLocked)
            Toggle(store.t("吸附屏幕边缘"), isOn: $store.snapToEdges)
            Button(store.t("重置位置"), action: resetPosition)
            Button(store.t("收起到状态栏")) { store.closeDesktopPanel(panelID) }
            Divider()
            Button(store.t("退出世界时钟"), action: quit)
        }
        .preferredColorScheme(.dark)
    }

    private func clockGrid(_ regions: [ClockRegion]) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<metrics.rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<metrics.columns, id: \.self) { column in
                        let index = row * metrics.columns + column
                        if index < regions.count {
                            TickingClockColumn(store: store, region: regions[index])
                                .frame(maxWidth: .infinity)
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                        if column < metrics.columns - 1 {
                            Rectangle().fill(.white.opacity(0.12))
                                .frame(width: 1, height: 142).offset(y: -6)
                        }
                    }
                }.frame(height: 174)
                if row < metrics.rows - 1 {
                    Rectangle().fill(.white.opacity(0.1))
                        .frame(height: 1).padding(.horizontal, 16).padding(.bottom, -1)
                }
            }
        }
    }
}

private struct DesktopLayoutPicker: View {
    @ObservedObject var store: ClockStore
    var body: some View {
        Picker(store.t("桌面布局"), selection: $store.desktopLayout) {
            ForEach(DesktopLayout.allCases) { layout in
                Label(store.t(layout.title), systemImage: layout.symbol).tag(layout)
            }
        }
    }
}

private struct DesktopLayoutMenu: View {
    @ObservedObject var store: ClockStore
    @ViewState private var hovered = false
    var body: some View {
        Menu { DesktopLayoutPicker(store: store) } label: {
            Image(systemName: store.desktopLayout.symbol)
                .font(.system(size: 14))
                .foregroundStyle(hovered ? .white : Palette.quiet)
                .frame(width: 30, height: 30)
                .background(.white.opacity(hovered ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(store.t("桌面布局"))
        .accessibilityLabel(store.t("桌面布局"))
        .onHover { hovered = $0 }
    }
}

private struct TickingClockColumn: View {
    @ObservedObject var store: ClockStore
    let region: ClockRegion
    @ObservedObject private var seconds: ClockSeconds

    init(store: ClockStore, region: ClockRegion) {
        self.store = store
        self.region = region
        self.seconds = store.seconds
    }

    var body: some View {
        // All cards and windows read one sampled instant. Only these columns observe
        // seconds; the menu bar and weather do not rebuild on every tick.
        ClockColumn(snapshot: store.snapshot(region, at: seconds.instant), showWeather: store.showWeather,
            weather: store.weather(region), stale: store.weatherStale(region),
            weatherMessage: store.weatherMessage(region))
    }
}

private struct SecondsOrbit: View {
    let second: Int
    let language: AppLanguage

    var body: some View {
        ZStack {
            Canvas { context, size in
                drawTicks(in: &context, size: size)
            }
            counter
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }

    private var counter: some View {
        VStack(spacing: -1) {
            Text(String(format: "%02d", second))
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(Palette.ink)
            Text(language == .english ? "s" : "秒")
                .font(.system(size: 8, weight: .medium)).foregroundStyle(Palette.quiet)
        }
    }

    // Keep drawing arithmetic outside the view builder so older Swift toolchains
    // can type-check the native data visualization without a large expression.
    private func drawTicks(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius: CGFloat = min(size.width, size.height) / 2 - 1
        let inner: CGFloat = radius - 3.4
        for tick in 0..<60 {
            let angle: Double = Double(tick) / 60 * 2 * Double.pi - Double.pi / 2
            let dx = CGFloat(cos(angle))
            let dy = CGFloat(sin(angle))
            let highlighted = tick < second
            var mark = Path()
            mark.move(to: CGPoint(x: center.x + dx * inner, y: center.y + dy * inner))
            mark.addLine(to: CGPoint(x: center.x + dx * radius, y: center.y + dy * radius))
            let color: Color = highlighted ? Palette.night : Palette.quiet.opacity(0.48)
            let width: CGFloat = highlighted ? 1.5 : 0.8
            context.stroke(mark, with: .color(color), style: StrokeStyle(lineWidth: width))
        }
    }
}

private struct ClockColumn: View {
    let snapshot: ClockSnapshot
    let showWeather: Bool
    let weather: WeatherReading?
    let stale: Bool
    let weatherMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text(snapshot.city)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if snapshot.isLocal {
                    badge(snapshot.language.text("本地"), local: true)
                } else if let day = snapshot.dayLabel {
                    badge(day, local: false)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 23)
            .foregroundStyle(Palette.ink)

            Group {
                if showWeather {
                    if let weather {
                        HStack(spacing: 7) {
                            Image(systemName: weather.symbol).font(.system(size: 23, weight: .light))
                                .foregroundStyle(weather.isDay ? Palette.day : Palette.night)
                            Text("\(weather.temperatureLabel) \(stale ? snapshot.language.text("未更新") : weather.condition(in: snapshot.language))")
                                .font(.system(size: 11).monospacedDigit()).foregroundStyle(Palette.secondary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    } else {
                        Text(weatherMessage).font(.system(size: 11)).foregroundStyle(Palette.quiet)
                    }
                } else {
                    Image(systemName: snapshot.isDaytime ? "sun.max" : "moon")
                        .font(.system(size: 23, weight: .light))
                        .foregroundStyle(snapshot.isDaytime ? Palette.day : Palette.night)
                        .accessibilityLabel(snapshot.isDaytime ? snapshot.language.text("白天时段") : snapshot.language.text("夜间时段"))
                }
            }
            .frame(height: 32, alignment: .center)
            .padding(.top, 3)

            Text(snapshot.time)
                .font(.system(size: 38, weight: .regular, design: .default).monospacedDigit())
                .tracking(-1)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 45, alignment: .leading)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.date)
                        .font(.system(size: 14, weight: .regular).monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    Text("\(snapshot.weekday) · \(snapshot.differenceLabel)")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.quiet)
                        .lineLimit(1).minimumScaleFactor(0.65)
                }.frame(maxWidth: .infinity, alignment: .leading)
                SecondsOrbit(second: snapshot.second, language: snapshot.language)
            }
            .padding(.top, 2).padding(.trailing, -10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 25)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.city)，\(snapshot.date)，\(snapshot.weekday)，\(snapshot.timeWithSeconds)，\(snapshot.differenceLabel)" + (showWeather ? "，\(weather.map { "\($0.temperatureLabel)，\(stale ? snapshot.language.text("天气未更新") : $0.condition(in: snapshot.language))" } ?? weatherMessage)" : ""))
    }

    private func badge(_ text: String, local: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(local ? Color(red: 0.75, green: 0.86, blue: 0.81) : Color(red: 0.77, green: 0.78, blue: 0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(local ? Color(red: 0.45, green: 0.63, blue: 0.53).opacity(0.17) : .white.opacity(0.08), in: Capsule())
            .fixedSize()
    }
}

struct RegionManagerView: View {
    @ObservedObject var store: ClockStore
    let done: () -> Void
    @FocusState private var searchFocused: Bool
    @ViewState private var selectedArea: WorldArea = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.t("管理地区")).font(.system(size: 22, weight: .semibold))
                    Text(store.t("分别选择桌面和状态栏要显示的时钟，设置自动保存。"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(store.regions.count) / \(store.maximumRegions)")
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
            }.padding(24)

            HStack(spacing: 10) {
                Text(store.t("已添加的地区")).frame(maxWidth: .infinity, alignment: .leading)
                Text(store.t("桌面")).frame(width: 50)
                Text(store.t("状态栏")).frame(width: 60)
                Text(store.t("排序 / 移除")).frame(width: 76)
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .padding(.horizontal, 39).padding(.bottom, 8)

            ScrollView {
              VStack(spacing: 0) {
                ForEach(Array(store.regions.enumerated()), id: \.element.id) { index, region in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(region.name(local: store.localZone, language: store.language)).font(.system(size: 13, weight: .medium))
                            Text(region.followsSystem ? "\(store.t("本地")) · \(store.localZone.identifier)" : region.id)
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("", isOn: Binding(get: { store.desktopRegionIDs.contains(region.id) },
                            set: { store.setDesktop(region, visible: $0) }))
                            .toggleStyle(.checkbox).labelsHidden().frame(width: 50)
                            .accessibilityLabel("\(store.t("在桌面显示")) \(region.name(local: store.localZone, language: store.language))")
                        Toggle("", isOn: Binding(get: { store.statusRegionIDs.contains(region.id) },
                            set: { store.setStatus(region, visible: $0) }))
                            .toggleStyle(.checkbox).labelsHidden().frame(width: 60)
                            .accessibilityLabel("\(store.t("在状态栏显示")) \(region.name(local: store.localZone, language: store.language))")
                        HStack(spacing: 7) {
                            if !region.followsSystem {
                                Button { store.move(region, direction: -1) } label: { Image(systemName: "chevron.up") }
                                    .disabled(index <= 1).help(store.t("向前移动")).accessibilityLabel("\(store.t("向前移动时钟")) \(region.name(local: store.localZone, language: store.language))")
                                Button { store.move(region, direction: 1) } label: { Image(systemName: "chevron.down") }
                                    .disabled(index == store.regions.count - 1).help(store.t("向后移动")).accessibilityLabel("\(store.t("向后移动时钟")) \(region.name(local: store.localZone, language: store.language))")
                                Button { store.remove(region) } label: { Image(systemName: "minus.circle") }
                                    .help(store.t("移除地区")).accessibilityLabel("\(store.t("移除时钟")) \(region.name(local: store.localZone, language: store.language))")
                            }
                        }
                        .frame(width: 76, alignment: .trailing)
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 15).frame(height: 48)
                    if index < store.regions.count - 1 { Divider().padding(.leading, 15) }
                }
              }
            }
            .frame(height: min(CGFloat(store.regions.count) * 49 - 1, 195))
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 24)

            HStack {
                Toggle(store.t("显示天气（°C）"), isOn: $store.showWeather).toggleStyle(.checkbox)
                Spacer()
                Link(store.t("天气数据 · Open-Meteo"), destination: URL(string: "https://open-meteo.com/")!)
                    .font(.system(size: 10))
            }.padding(.horizontal, 24).padding(.top, 14)
            TextField(store.t("搜索城市、国家或时区，例如：东京、France"), text: $store.search)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .accessibilityLabel(store.t("搜索城市、国家或时区"))
                .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)

            let results = CityCatalog.search(store.search, area: selectedArea, language: store.language)
            HStack {
                Picker(store.t("浏览"), selection: $selectedArea) {
                    ForEach(WorldArea.allCases) { area in Text(store.t(area.title)).tag(area) }
                }.pickerStyle(.menu).frame(width: 225)
                    .accessibilityLabel(store.t("按地区筛选"))
                Spacer()
                Text("\(results.count) \(store.t("个可选地区"))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.bottom, 6)
            let sections = CityCatalog.sections(for: results,
                showPopular: selectedArea == .all && store.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if results.isEmpty {
                        Text(store.t("没有匹配的地区，请尝试城市、国家或时区名称。"))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 35)
                        if selectedArea != .all {
                            Button(store.t("搜索全球地区")) { selectedArea = .all }
                        }
                    }
                    ForEach(sections) { section in
                      Section {
                       ForEach(section.identifiers, id: \.self) { identifier in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(CityCatalog.name(for: identifier, language: store.language)).font(.system(size: 13))
                                Text([CityCatalog.country(for: identifier, language: store.language), identifier]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    .help(identifier)
                            }
                            Spacer()
                            Text(store.snapshot(ClockRegion(id: identifier)).offsetLabel)
                                .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .trailing)
                            if store.contains(identifier) {
                                Label(store.t("已添加"), systemImage: "checkmark").font(.system(size: 11)).foregroundStyle(.secondary)
                            } else {
                                Button(store.t("添加")) { store.add(identifier) }
                                    .disabled(store.regions.count >= store.maximumRegions)
                                    .accessibilityLabel("\(store.t("添加")) \(CityCatalog.name(for: identifier, language: store.language))")
                            }
                        }.padding(.horizontal, 8).frame(height: 48)
                        Divider()
                       }
                      } header: {
                        HStack {
                            Text(store.t(section.area.title))
                            Spacer()
                            Text("\(section.identifiers.count)").monospacedDigit()
                        }
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 8)
                        .background(Color(nsColor: .windowBackgroundColor))
                      }
                    }
                }.padding(.horizontal, 24)
            }.frame(minHeight: 120, maxHeight: .infinity)
                .id("\(selectedArea.rawValue):\(store.search)")

            Divider()
            HStack {
                Button(store.t("恢复默认")) { store.reset() }
                Spacer()
                if let notice = store.notice {
                    Text(notice).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Button(store.t("完成"), action: done).keyboardShortcut(.defaultAction)
            }.padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .onAppear { searchFocused = true }
    }
}

struct MenuClocksView: View {
    @ObservedObject var store: ClockStore

    var body: some View {
        VStack(spacing: 0) {
            ForEach(store.regions) { region in
                let clock = store.snapshot(region)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(clock.city).font(.system(size: 12, weight: .medium))
                            if clock.isLocal { Text(store.t("本地")).font(.system(size: 9)).foregroundStyle(.secondary) }
                            if let day = clock.dayLabel { Text(day).font(.system(size: 9)).foregroundStyle(.secondary) }
                        }
                        Text("\(clock.date) \(clock.weekday)")
                            .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                        if store.showWeather {
                            if let weather = store.weather(region) {
                                Label("\(weather.temperatureLabel) · \(store.weatherStale(region) ? store.t("未更新") : weather.condition(in: store.language))", systemImage: weather.symbol)
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            } else {
                                Text(store.weatherMessage(region)).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    Text(clock.time).font(.system(size: 21, weight: .regular).monospacedDigit())
                }
                .padding(.horizontal, 17).frame(height: store.showWeather ? 72 : 55)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 5)
        .frame(width: 286)
    }
}

struct StatusPopoverView: View {
    static let chromeHeight: CGFloat = 206
    @ObservedObject var store: ClockStore
    @ObservedObject var updates: UpdateController
    let clockListHeight: CGFloat
    let manage: () -> Void
    let showDesktop: () -> Void
    let resetPosition: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.t("世界时钟")).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: manage) { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.borderless).accessibilityLabel(store.t("管理地区"))
            }.padding(.horizontal, 17).frame(height: 40)
            VStack(spacing: 6) {
                HStack {
                    Button(action: showDesktop) {
                        Label(store.t("打开"), systemImage: "rectangle.on.rectangle")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity).frame(height: 20)
                    }.buttonStyle(.borderedProminent)
                }
                Text(store.t(store.positionLocked ? "位置已锁定，可在右键菜单解锁。" : (store.snapToEdges ? "拖动标题栏可移动，靠近屏幕边缘自动吸附。" : "拖动标题栏可移动。")))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).frame(height: 26, alignment: .topLeading)
            }.padding(.horizontal, 13).frame(height: 76)
            Divider()
            ScrollView { MenuClocksView(store: store) }
                .frame(height: clockListHeight)
            Divider()
            HStack {
                Text(store.t("状态栏"))
                Spacer()
                Menu(store.t("状态栏显示")) {
                    ForEach(store.regions) { region in
                        Toggle(region.name(local: store.localZone, language: store.language), isOn: Binding(
                            get: { store.statusRegionIDs.contains(region.id) },
                            set: { store.setStatus(region, visible: $0) }))
                    }
                    Divider()
                    Button(store.t("仅本地时钟")) { store.statusRegionIDs = ["system"] }
                    Button(store.t("显示全部")) { store.statusRegionIDs = Set(store.regions.map(\.id)) }
                    Button(store.t("仅显示图标")) { store.statusRegionIDs = [] }
                }.menuStyle(.borderlessButton).fixedSize()
            }.font(.system(size: 12)).buttonStyle(.borderless).padding(.horizontal, 15).frame(height: 36)
            HStack {
                Toggle(store.t("天气"), isOn: $store.showWeather).toggleStyle(.checkbox)
                Spacer()
                Button(store.t("刷新")) { store.refreshWeather(force: true) }
                Menu(store.t("更多")) {
                    DesktopLayoutPicker(store: store)
                    Divider()
                    Toggle(store.t("始终置顶"), isOn: $store.alwaysOnTop)
                    Toggle(store.t("锁定位置"), isOn: $store.positionLocked)
                    Toggle(store.t("吸附屏幕边缘"), isOn: $store.snapToEdges)
                    Button(store.t("找回面板（重置位置）"), action: resetPosition)
                    Divider()
                    Button(store.t("检查更新…")) { updates.check(language: store.language) }
                    Button(store.t("退出世界时钟"), action: quit)
                }.menuStyle(.borderlessButton).fixedSize()
            }.font(.system(size: 11)).buttonStyle(.borderless).padding(.horizontal, 15).frame(height: 30)
            Link(store.t("天气数据 · Open-Meteo"), destination: URL(string: "https://open-meteo.com/")!)
                .font(.system(size: 9)).foregroundStyle(.secondary).frame(height: 22)
        }.frame(width: 286, height: clockListHeight + Self.chromeHeight)
            .background(Color(red: 0.12, green: 0.135, blue: 0.16).opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.16), lineWidth: 0.5) }
            .preferredColorScheme(.dark)
    }
}


struct SettingsRootView: View {
    @ObservedObject var store: ClockStore
    @ObservedObject var updates: UpdateController
    let done: () -> Void
    var body: some View {
        TabView {
            RegionManagerView(store: store, done: done)
                .tabItem { Label(store.language == .english ? "Clocks" : "时钟", systemImage: "globe") }
            PreferencesView(store: store, updates: updates, done: done)
                .tabItem { Label(store.language == .english ? "Settings" : "设置", systemImage: "gearshape") }
        }
        .frame(width: 600, height: 760)
        .preferredColorScheme(.dark)
    }
}

private struct PreferencesView: View {
    @ObservedObject var store: ClockStore
    @ObservedObject var updates: UpdateController
    let done: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Meridian").font(.system(size: 26, weight: .semibold))
            HStack {
                Text(store.t("语言"))
                Spacer()
                Picker(store.t("语言"), selection: $store.language) {
                    ForEach(AppLanguage.allCases) { language in Text(language.displayName).tag(language) }
                }.labelsHidden().frame(width: 180)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text(store.t("桌面布局")).font(.system(size: 17, weight: .semibold))
                DesktopLayoutPicker(store: store).pickerStyle(.segmented).labelsHidden()
                Text(store.t("独立时钟可分别拖动；关闭后，在状态栏点击“打开”恢复全部。"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Divider()
            Toggle(store.t("显示天气（°C）"), isOn: $store.showWeather)
            Text(store.t("天气按时钟所示城市查询，本地使用系统时区对应城市。"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Divider()
            Text(store.t("更新")).font(.system(size: 17, weight: .semibold))
            Text("\(store.language == .english ? "Version" : "版本") \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0")")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Toggle(store.t("自动检查更新"), isOn: $updates.automaticChecks).disabled(!updates.isConfigured)
            Toggle(store.t("自动下载更新"), isOn: $updates.automaticDownloads).disabled(!updates.isConfigured)
            Button(store.t("检查更新…")) { updates.check(language: store.language) }
                .disabled(updates.isConfigured && !updates.canCheck)
            if !updates.isConfigured {
                Text(store.t("更新将在正式发布后启用。"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Link(store.t("天气数据 · Open-Meteo"), destination: URL(string: "https://open-meteo.com/")!)
                .font(.system(size: 12))
            HStack { Spacer(); Button(store.t("完成"), action: done).keyboardShortcut(.defaultAction) }
        }.padding(30)
    }
}
