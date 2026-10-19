import Foundation
import Combine
import OSLog

@MainActor
final class PlaceSearchController: ObservableObject {
    @Published private(set) var results: [ResolvedPlace] = []
    @Published private(set) var searching = false
    @Published private(set) var status: String?
    private var lookup: Task<Void, Never>?
    private var generation = UUID()
    private var cache: [String: [ResolvedPlace]] = [:]
    private var lastRequest = Date.distantPast
    private let session = URLSession(configuration: .ephemeral)
    private let logger = Logger(subsystem: "org.codex.worldclock", category: "PlaceSearch")

    func clear() {
        generation = UUID()
        lookup?.cancel(); lookup = nil
        searching = false; results = []; status = nil
    }

    // Explicit, cached place-name queries; no device location is requested.
    func search(_ text: String, language: String = "en") {
        clear()
        guard let url = PlaceSearchQuery.requestURL(text, language: language) else {
            status = "请输入 2 至 240 个字符的地点名称。"; return
        }
        let key = url.absoluteString.lowercased()
        if let cached = cache[key] {
            results = cached
            status = cached.isEmpty ? "没有找到该地点，请补充城市、州/省或国家。" : nil
            return
        }
        searching = true; status = "正在查询全球地点…"
        let token = generation
        lookup = Task { [weak self] in
            guard let self else { return }
            do {
                let delay = max(0, 1.1 - Date().timeIntervalSince(self.lastRequest))
                if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                try Task.checkCancellation()
                self.lastRequest = Date()
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
                request.setValue("Meridian/1.5 (https://github.com/etongle/Meridian)", forHTTPHeaderField: "User-Agent")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await self.session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1_048_576 else { throw URLError(.badServerResponse) }
                let decoded = try JSONDecoder().decode(GeographicSearchResponse.self, from: data)
                guard self.generation == token else { return }
                var seen = Set<String>()
                self.results = (decoded.results ?? []).compactMap(\.resolved).filter { seen.insert($0.id).inserted }
                if self.cache.count >= 40 { self.cache.removeAll() }
                self.cache[key] = self.results
                self.searching = false; self.lookup = nil
                self.status = self.results.isEmpty ? "没有找到该地点，请补充城市、州/省或国家。" : nil
            } catch {
                guard self.generation == token else { return }
                let failure = error as NSError
                self.logger.error("Place lookup failed: \(failure.domain, privacy: .public) \(failure.code, privacy: .public)")
                self.searching = false; self.lookup = nil
                self.status = "地点查询失败，请检查网络后重试。"
            }
        }
    }
}
