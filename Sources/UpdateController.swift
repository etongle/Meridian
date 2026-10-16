import AppKit
import Combine
import Sparkle

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var isConfigured = false
    @Published private(set) var canCheck = false
    @Published var automaticChecks = true {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticChecks }
    }
    @Published var automaticDownloads = false {
        didSet { controller?.updater.automaticallyDownloadsUpdates = automaticDownloads }
    }
    private var controller: SPUStandardUpdaterController?
    private var subscriptions = Set<AnyCancellable>()

    init(preview: Bool = false) {
        let config = UpdateConfiguration(feed: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
        guard config.isConfigured, !preview else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.startUpdater()
        isConfigured = true
        automaticChecks = controller.updater.automaticallyChecksForUpdates
        automaticDownloads = controller.updater.automaticallyDownloadsUpdates
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).removeDuplicates()
            .sink { [weak self] value in if self?.automaticChecks != value { self?.automaticChecks = value } }
            .store(in: &subscriptions)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates).removeDuplicates()
            .sink { [weak self] value in if self?.automaticDownloads != value { self?.automaticDownloads = value } }
            .store(in: &subscriptions)
    }
    func check(language: AppLanguage) {
        guard let controller else {
            let alert = NSAlert()
            alert.messageText = language.text("更新将在正式发布后启用。")
            alert.informativeText = language.text("发布渠道尚未配置。")
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        controller.checkForUpdates(nil)
    }
}
