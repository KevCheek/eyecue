import AppKit
import Sparkle

/// In-app updates with Sparkle. The app itself has no network access: Sparkle's separate Downloader
/// service fetches the update feed and the new version from GitHub, and its Installer service swaps
/// the app in place. Every update is checked against the EdDSA public key in Info.plist before it
/// is installed. The same file works in any app that embeds Sparkle the same way.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?

    /// Starts Sparkle only in the packaged app (it needs the feed URL and key from Info.plist), and
    /// never during the command line checks.
    func start(checkNow: Bool) {
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        // Tell people about a new version when they open the app, not only once a day.
        if checkNow, controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
    }

    var isAvailable: Bool { controller != nil }

    /// The off switch is absolute: with automatic checks off, no check starts unless the person chose
    /// Check for Updates, even one Sparkle had already scheduled.
    nonisolated func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        let automatic = MainActor.assumeIsolated { updater.automaticallyChecksForUpdates }  // called on the main thread
        if updateCheck == .updatesInBackground && !automatic {
            throw NSError(domain: "SnowpineCue.Updater", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Automatic update checks are off."])
        }
    }

    /// Menu: Check for Updates...
    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    /// Menu: Check for Updates Automatically. Off means no network traffic at all unless asked.
    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
}

/// `SnowpineCue --update-check` (packaged app only): asks Sparkle's Downloader helper to read the update
/// feed and reports what it found, with no window. Proves the update path works inside the sandbox.
@MainActor
final class UpdateCheck: NSObject, SPUUpdaterDelegate {
    private var updater: SPUUpdater?

    func run() {
        let driver = SPUStandardUserDriver(hostBundle: .main, delegate: nil)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        self.updater = updater
        do {
            try updater.start()
        } catch {
            finish("UPDATE-CHECK FAIL start: \(error.localizedDescription)", code: 1)
            return
        }
        updater.checkForUpdateInformation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { self.finish("UPDATE-CHECK FAIL timed out", code: 1) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated { finish("UPDATE-CHECK OK update available: \(version)", code: 0) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        MainActor.assumeIsolated { finish("UPDATE-CHECK OK feed read, no newer version", code: 0) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        var parts: [String] = []
        var current: NSError? = error as NSError
        while let e = current {
            parts.append("\(e.domain) \(e.code): \(e.localizedDescription)")
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        let text = parts.joined(separator: " <- ")
        MainActor.assumeIsolated { finish("UPDATE-CHECK RESULT \(text)", code: 2) }
    }

    private func finish(_ line: String, code: Int32) {
        print(line)
        fflush(stdout)
        exit(code)
    }
}
