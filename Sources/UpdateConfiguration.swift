import Foundation

struct UpdateConfiguration {
    let feedURL: URL?
    let publicKey: String?
    init(feed: String?, publicKey: String?) {
        if let feed, let url = URL(string: feed), url.scheme == "https",
           let host = url.host, !host.isEmpty, url.user == nil, url.password == nil {
            self.feedURL = url
        } else { self.feedURL = nil }
        if let publicKey, let data = Data(base64Encoded: publicKey), data.count == 32 {
            self.publicKey = publicKey
        } else { self.publicKey = nil }
    }
    var isConfigured: Bool { feedURL != nil && publicKey != nil }
}
