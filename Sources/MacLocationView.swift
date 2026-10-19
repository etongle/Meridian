import SwiftUI

private typealias LocationViewState<Value> = SwiftUI.State<Value>

struct MacLocationView: View {
    @ObservedObject var store: ClockStore
    @ObservedObject var location: MacLocationController
    let done: () -> Void
    @LocationViewState private var search = ""
    @LocationViewState private var selectedID: String?
    @LocationViewState private var selectedSearchPlace: SimulatedPlace?
    @StateObject private var placeSearch = PlaceSearchController()
    @LocationViewState private var manual = false
    @LocationViewState private var latitude = ""
    @LocationViewState private var longitude = ""

    private func searchPlaces() {
        placeSearch.search(search, language: store.language == .english ? "en" : "zh")
    }

    private var selectedPlace: SimulatedPlace? {
        if manual {
            guard let lat = Double(latitude.trimmingCharacters(in: .whitespaces)),
                  let lon = Double(longitude.trimmingCharacters(in: .whitespaces)) else { return nil }
            let place = SimulatedPlace(id: "manual", latitude: lat, longitude: lon)
            return place.isValid ? place : nil
        }
        if let selectedSearchPlace { return selectedSearchPlace }
        guard let id = selectedID, let fallback = CityCatalog.location(for: id) else { return nil }
        let known = WeatherClient.coordinates[id]
        return SimulatedPlace(id: id, latitude: known?.latitude ?? fallback.latitude, longitude: known?.longitude ?? fallback.longitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(store.t("Mac 定位"), systemImage: "mappin.and.ellipse").font(.system(size: 24, weight: .semibold))
                Spacer()
                Text(store.t("实验功能")).font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.orange.opacity(0.16), in: Capsule()).foregroundStyle(.orange)
            }
            Text(store.t("为使用 macOS 定位服务的应用模拟指定地区。需要管理员授权，系统版本可能影响效果。"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Picker(store.t("选择方式"), selection: $manual) {
                Text(store.t("搜索地区")).tag(false)
                Text(store.t("输入经纬度")).tag(true)
            }.pickerStyle(.segmented).labelsHidden().disabled(location.busy)

            if manual {
                HStack(spacing: 14) {
                    VStack(alignment: .leading) {
                        Text(store.t("纬度（−90 至 90）")).font(.system(size: 11))
                        TextField("31.23", text: $latitude).accessibilityLabel(store.t("纬度"))
                    }
                    VStack(alignment: .leading) {
                        Text(store.t("经度（−180 至 180）")).font(.system(size: 11))
                        TextField("121.47", text: $longitude).accessibilityLabel(store.t("经度"))
                    }
                }.disabled(location.busy)
                Text(store.t("请输入十进制经纬度，南纬和西经使用负数。"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                HStack {
                    TextField(store.t("城市、州/省或国家"), text: $search)
                        .textFieldStyle(.roundedBorder).onSubmit { searchPlaces() }
                    Button(store.t("搜索地点")) { searchPlaces() }
                        .disabled(PlaceSearchQuery.normalized(search).count < 2 || placeSearch.searching)
                }.disabled(location.busy)
                HStack {
                    Text(store.t("点击搜索或按回车查询全球地区，无需本机定位。"))
                    Spacer(minLength: 4)
                    Link("GeoNames · Open-Meteo", destination: URL(string: "https://open-meteo.com/en/docs/geocoding-api")!)
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if placeSearch.searching {
                            ProgressView(store.t("正在查询全球地点…")).padding(20)
                        }
                        if let status = placeSearch.status, !placeSearch.searching {
                            Text(store.t(status)).font(.system(size: 12)).foregroundStyle(.secondary).padding(14)
                        }
                        ForEach(placeSearch.results) { result in
                            Button {
                                selectedSearchPlace = result.target
                                selectedID = nil
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedSearchPlace?.id == result.id ? "checkmark.circle.fill" : "mappin.circle")
                                        .foregroundStyle(selectedSearchPlace?.id == result.id ? Color.accentColor : .secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(result.target.displayName ?? result.subtitle).font(.system(size: 13, weight: .medium))
                                        Text(result.subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }.padding(.horizontal, 12).frame(minHeight: 52).contentShape(Rectangle())
                                    .background(selectedSearchPlace?.id == result.id ? Color.accentColor.opacity(0.12) : .clear)
                            }.buttonStyle(.plain).disabled(location.busy)
                            Divider().padding(.leading, 42)
                        }
                        let matches = CityCatalog.search(search, language: store.language).filter { CityCatalog.location(for: $0) != nil }
                        if matches.isEmpty && placeSearch.results.isEmpty && placeSearch.status == nil {
                            Text(store.t("内置目录无匹配。点击“搜索地点”查询全球城市。"))
                                .font(.system(size: 12)).foregroundStyle(.secondary).padding(20)
                        }
                        ForEach(matches, id: \.self) { id in
                            Button { selectedID = id; selectedSearchPlace = nil } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedID == id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedID == id ? Color.accentColor : .secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(CityCatalog.name(for: id, language: store.language)).font(.system(size: 13, weight: .medium))
                                        Text("\(CityCatalog.country(for: id, language: store.language) ?? "") · \(id)")
                                            .font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }.padding(.horizontal, 12).frame(height: 46).contentShape(Rectangle())
                                    .background(selectedID == id ? Color.accentColor.opacity(0.12) : .clear)
                            }.buttonStyle(.plain).disabled(location.busy)
                            Divider().padding(.leading, 42)
                        }
                    }
                }.frame(height: 190).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(store.t("目标地区")).font(.system(size: 11)).foregroundStyle(.secondary)
                if let place = selectedPlace {
                    Text(place.displayName ?? (manual ? store.t("自定义坐标") : CityCatalog.name(for: place.id, language: store.language)))
                        .font(.system(size: 17, weight: .semibold))
                    Text(String(format: "%.6f, %.6f", place.latitude, place.longitude))
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                } else {
                    Text(store.t("请先选择地区或输入有效坐标")).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button(store.t("应用到 Mac 定位")) { if let place = selectedPlace { location.apply(place) } }
                        .buttonStyle(.borderedProminent).disabled(selectedPlace == nil || location.busy)
                    Button(store.t("恢复原定位")) { location.restore() }.disabled(location.busy)
                    if location.busy { ProgressView().controlSize(.small) }
                }
            }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    if let active = location.appliedPlace, location.needsRestore {
                        Text("\(store.t("上次应用")) · \(active.displayName ?? (active.id == "manual" ? store.t("自定义坐标") : CityCatalog.name(for: active.id, language: store.language))) · \(String(format: "%.4f, %.4f", active.latitude, active.longitude))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text(store.t(location.status)).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button(store.t("验证系统返回的位置")) { location.verify(target: selectedPlace) }
                            .disabled((selectedPlace == nil && location.appliedPlace == nil) || location.busy || location.verifying)
                        Button(store.t("检查兼容性")) { location.diagnose() }.disabled(location.busy)
                    }
                    if let detail = location.diagnosticDetail {
                        Text(detail).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            Text(store.t("退出或重启后可能继续生效，请用“恢复原定位”结束。IP 定位、账号地区和应用缓存可能显示不同地区。"))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack { Spacer(); Button(store.t("完成"), action: done).keyboardShortcut(.defaultAction) }
        }.padding(26).onAppear {
            if let previous = location.appliedPlace {
                if previous.displayName != nil { selectedSearchPlace = previous }
                else if previous.id == "manual" {
                    manual = true; latitude = String(previous.latitude); longitude = String(previous.longitude)
                } else if selectedID == nil { selectedID = previous.id }
            }
        }
        .onChange(of: search) { _, _ in
            placeSearch.clear(); selectedSearchPlace = nil; selectedID = nil
        }
    }
}
