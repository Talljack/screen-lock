import Cocoa
import CFNetwork
import Darwin
import Network
import Sparkle
import UserNotifications
import os.log

private let log = OSLog(subsystem: "com.yugangcao.screenlock", category: "App")

final class UpdaterDriver: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private struct ProxyEndpoint {
        let scheme: String
        let host: String
        let port: UInt16
    }

    func standardUserDriverWillShowModalAlert() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func standardUserDriverShouldShowVersionHistory(for item: SUAppcastItem) -> Bool {
        false
    }

    func standardUserDriverWillShowReleaseNotesText(
        _ releaseNotesAttributedString: NSAttributedString,
        forUpdate update: SUAppcastItem,
        withBundleDisplayVersion bundleDisplayVersion: String,
        bundleVersion: String
    ) -> NSAttributedString? {
        releaseNotesAttributedString
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        os_log(
            "Sparkle found update %{public}@ (%{public}@) from %{public}@",
            log: log,
            type: .info,
            item.displayVersionString,
            item.versionString,
            item.fileURL?.absoluteString ?? "no file URL"
        )
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        os_log("Sparkle did not find an update", log: log, type: .info)
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        os_log(
            "Sparkle will download update %{public}@ from %{public}@",
            log: log,
            type: .info,
            item.displayVersionString,
            request.url?.absoluteString ?? "unknown URL"
        )
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        os_log("Sparkle downloaded update %{public}@", log: log, type: .info, item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        os_log(
            "Sparkle failed to download update %{public}@ with error: %{public}@",
            log: log,
            type: .error,
            item.displayVersionString,
            error.localizedDescription
        )
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        os_log("Sparkle will install update %{public}@", log: log, type: .info, item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error {
            os_log("Sparkle update cycle finished with error: %{public}@",
                   log: log, type: .error, error.localizedDescription)
        } else {
            os_log("Sparkle update cycle finished successfully", log: log, type: .info)
        }
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let path = bundleURL.path
        let isInApplications = path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
        let isTemporaryOrTranslocated = path.hasPrefix("/private/var/folders/") || path.hasPrefix("/private/tmp/") || path.contains("/AppTranslocation/")

        guard isInApplications, !isTemporaryOrTranslocated else {
            let message = "请先将 ScreenLock.app 移动到 Applications 后再执行应用内更新。当前运行路径：\(path)"
            os_log("%{public}@", log: log, type: .error, message)
            throw NSError(
                domain: "ScreenLock.Updater",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        if let proxyMessage = unavailableLoopbackProxyMessage() {
            os_log("%{public}@", log: log, type: .error, proxyMessage)
            throw NSError(
                domain: "ScreenLock.Updater",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: proxyMessage]
            )
        }
    }

    private func unavailableLoopbackProxyMessage() -> String? {
        for endpoint in activeLoopbackProxyEndpoints() {
            guard !isProxyReachable(endpoint) else { continue }

            return "检测到系统\(endpoint.scheme.uppercased())代理 \(endpoint.host):\(endpoint.port) 当前不可连接。请先关闭该代理/VPN，或恢复本地代理服务后再执行应用内更新。"
        }

        return nil
    }

    private func activeLoopbackProxyEndpoints() -> [ProxyEndpoint] {
        guard
            let unmanagedSettings = CFNetworkCopySystemProxySettings(),
            let settings = unmanagedSettings.takeRetainedValue() as? [String: Any]
        else {
            return []
        }

        let candidates: [(scheme: String, enabledKey: String, hostKey: String, portKey: String)] = [
            (
                "http",
                kCFNetworkProxiesHTTPEnable as String,
                kCFNetworkProxiesHTTPProxy as String,
                kCFNetworkProxiesHTTPPort as String
            ),
            (
                "https",
                kCFNetworkProxiesHTTPSEnable as String,
                kCFNetworkProxiesHTTPSProxy as String,
                kCFNetworkProxiesHTTPSPort as String
            ),
        ]

        return candidates.compactMap { candidate in
            let enabled = (settings[candidate.enabledKey] as? NSNumber)?.boolValue ?? false
            guard enabled else { return nil }

            guard
                let host = settings[candidate.hostKey] as? String,
                let portNumber = settings[candidate.portKey] as? NSNumber
            else {
                return nil
            }

            let normalizedHost = host.lowercased()
            let isLoopbackHost = normalizedHost == "127.0.0.1" || normalizedHost == "localhost" || normalizedHost == "::1"
            guard isLoopbackHost else { return nil }

            return ProxyEndpoint(
                scheme: candidate.scheme,
                host: host,
                port: portNumber.uint16Value
            )
        }
    }

    private func isProxyReachable(_ endpoint: ProxyEndpoint) -> Bool {
        let port = NWEndpoint.Port(rawValue: endpoint.port)
        guard let port else { return false }

        let connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: port, using: .tcp)
        let semaphore = DispatchSemaphore(value: 0)
        let stateQueue = DispatchQueue(label: "com.yugangcao.screenlock.proxy-preflight")
        var reachable = false

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                reachable = true
                connection.cancel()
                semaphore.signal()
            case .failed, .cancelled:
                semaphore.signal()
            default:
                break
            }
        }

        connection.start(queue: stateQueue)
        let _ = semaphore.wait(timeout: .now() + .milliseconds(800))
        connection.cancel()

        return reachable
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private let updaterDriver: UpdaterDriver
    let updaterController: SPUStandardUpdaterController

    override init() {
        let updaterDriver = UpdaterDriver()
        self.updaterDriver = updaterDriver
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: updaterDriver,
            userDriverDelegate: updaterDriver
        )
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {}

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let settings = SettingsManager.shared.settings
        os_log("ScreenLock started — lock: %{public}@, warning: %d min",
               log: log, type: .info, settings.lockTime, settings.warningMinutes)

        updaterController.startUpdater()
        updatePreventSleep(settings.preventSleepEnabled)

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            os_log("Notification permission: %{public}@", log: log, type: .info, granted ? "granted" : "denied")
        }

        SettingsManager.shared.onSettingsChanged = { [weak self] in
            self?.handleSettingsChanged()
        }

        SettingsManager.shared.applyStoredLanguage()
        SunCycleManager.shared.requestLocationIfNeeded()

        ScheduleManager.shared.start()
        ScreenManager.shared.applyCurrentSoftnessSetting()
        menuBarController = MenuBarController(updater: updaterController.updater)

        StatsManager.shared.onNewAchievement = { achievement in
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = L("achievement.unlocked", achievement.emoji)
                alert.informativeText = "\(achievement.title) — \(achievement.description)"
                alert.addButton(withTitle: L("achievement.awesome"))
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }

        showPermissionGuideIfNeeded()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        ScheduleManager.shared.stop()
        PowerManager.shared.disablePreventSleep()
        ScreenManager.shared.restoreOriginalGamma()
        os_log("ScreenLock terminated", log: log, type: .info)
    }

    private func handleSettingsChanged() {
        let settings = SettingsManager.shared.settings
        updatePreventSleep(settings.preventSleepEnabled)
        ScheduleManager.shared.checkSchedule()
    }

    private func updatePreventSleep(_ enabled: Bool) {
        if enabled {
            PowerManager.shared.enablePreventSleep()
        } else {
            PowerManager.shared.disablePreventSleep()
        }
    }

    private func showPermissionGuideIfNeeded() {
        let settings = SettingsManager.shared.settings
        guard !settings.hasShownPermissionGuide else { return }

        let trusted = AXIsProcessTrusted()
        if !trusted {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = L("permission.title")
                alert.informativeText = L("permission.message")
                alert.addButton(withTitle: L("permission.open_settings"))
                alert.addButton(withTitle: L("permission.later"))

                NSApp.activate(ignoringOtherApps: true)
                let response = alert.runModal()

                if response == .alertFirstButtonReturn {
                    let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                    )!
                    NSWorkspace.shared.open(url)
                }
            }
        }

        SettingsManager.shared.markPermissionGuideShown()
    }
}
