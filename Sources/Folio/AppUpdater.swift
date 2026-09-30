import Foundation
import Sparkle

/// Sparkle updates: checks the GitHub releases feed about once a day and installs
/// updates signed with the release key. Debug builds (and UI tests) never update.
@MainActor @Observable
final class AppUpdater {
    private(set) var canCheckForUpdates = false
    var checksAutomatically: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    var isAvailable: Bool { controller != nil }

    var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    init() {
        #if DEBUG
        controller = nil
        #else
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
        checksAutomatically = controller?.updater.automaticallyChecksForUpdates ?? false
        // Sparkle updates this property on the main thread.
        observation = controller?.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
