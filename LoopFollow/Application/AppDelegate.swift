// LoopFollow
// AppDelegate.swift

// LoopFollow
// AppDelegate.swift

// LoopFollow
// AppDelegate.swift

import CoreData
import EventKit
import UIKit
import UserNotifications

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let notificationCenter = UNUserNotificationCenter.current()

    // Keep the last-known token so the long-press can show it anytime
    private var lastAPNSTokenString: String?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        LogManager.shared.log(category: .general, message: "App started")
        LogManager.shared.cleanupOldLogs()
        let appGroupID = "group.com.2HEY366Q6J.LoopFollow"

        AppGroupStorageValue<String>.migrateFromStandardIfNeeded(appGroupID: appGroupID, key: "url")
        AppGroupStorageValue<String>.migrateFromStandardIfNeeded(appGroupID: appGroupID, key: "token")

        NightscoutSettings.migrateLegacyIfNeeded()
        // ✅ Step 2: Re-save the existing Nightscout token with the new Keychain accessibility
        // (Requires KeychainStore.set to use kSecAttrAccessibleAfterFirstUnlock)
        migrateNightscoutTokenAccessibilityIfNeeded()

        LogManager.shared.log(category: .general, message: "NS url set? \(!Storage.shared.url.value.isEmpty)")
        LogManager.shared.log(category: .general, message: "NS token set? \(!Storage.shared.token.value.isEmpty)")
        
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        notificationCenter.requestAuthorization(options: options) { didAllow, _ in
            if !didAllow {
                LogManager.shared.log(category: .general, message: "User has declined notifications")
            }
        }

        let store = EKEventStore()
        store.requestCalendarAccess { granted, error in
            if !granted {
                LogManager.shared.log(category: .calendar, message: "Failed to get calendar access: \(String(describing: error))")
                return
            }
        }

        let action = UNNotificationAction(identifier: "OPEN_APP_ACTION", title: "Open App", options: .foreground)
        let category = UNNotificationCategory(
            identifier: "loopfollow.background.alert",
            actions: [action],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().delegate = self

        _ = BLEManager.shared
        _ = VolumeButtonHandler.shared

        // Start Live Activity
        LiveActivityManager.shared.startIfNeeded()

        // Install long-press gesture (debug menu)
        DispatchQueue.main.async { [weak self] in
            self?.installDebugLongPressGesture()
        }

        // Register for remote notifications
        DispatchQueue.main.async {
            application.registerForRemoteNotifications()
        }

        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {}

    // MARK: - ✅ Step 2: Token migration helper

    /// Re-saves the existing Nightscout readable token so it picks up the new Keychain accessibility
    /// (AfterFirstUnlock). This must run while the device is unlocked at least once.
    private func migrateNightscoutTokenAccessibilityIfNeeded() {
        let key = "nightscout_readable_token"

        // Attempt read (this should work while unlocked)
        guard let existing = KeychainStore.get(key),
              !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            LogManager.shared.log(category: .general, message: "🔐 Token migration: nothing to migrate (nil/empty)")
            return
        }

        // Re-save (KeychainStore.set must enforce AfterFirstUnlock)
        let ok = KeychainStore.set(existing, for: key)
        LogManager.shared.log(category: .general, message: "🔐 Token migration: re-saved with AfterFirstUnlock ok=\(ok) len=\(existing.count)")
    }

    private func fetchLatestLoopIOBCOBFromNightscout() async throws -> (iob: Double?, cob: Double?) {
        try await withCheckedThrowingContinuation { continuation in
            NightscoutUtils.executeDynamicRequest(
                eventType: .deviceStatus,
                parameters: ["count": "1"]
            ) { result in
                switch result {
                case .success(let json):
                    guard
                        let arr = json as? [[String: AnyObject]],
                        let first = arr.first,
                        let loop = first["loop"] as? [String: AnyObject]
                    else {
                        continuation.resume(returning: (nil, nil))
                        return
                    }

                    let iob = (loop["iob"] as? Double) ?? (loop["iob"] as? NSNumber)?.doubleValue
                    let cob = (loop["cob"] as? Double) ?? (loop["cob"] as? NSNumber)?.doubleValue
                    continuation.resume(returning: (iob, cob))

                case .failure(let err):
                    continuation.resume(throwing: err)
                }
            }
        }
    }
    // MARK: - Remote Notifications

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()

        lastAPNSTokenString = tokenString
        Observable.shared.loopFollowDeviceToken.value = tokenString

        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        LogManager.shared.log(category: .general, message: "Bundle ID: \(bundleID)")
        LogManager.shared.log(category: .general, message: "Successfully registered for remote notifications with token: \(tokenString)")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        LogManager.shared.log(category: .general, message: "Failed to register for remote notifications: \(error.localizedDescription)")
    }

    nonisolated func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {

        LogManager.shared.log(category: .general, message: "Received remote notification (keys): \(Array(userInfo.keys))")

        let aps = userInfo["aps"] as? [String: Any]
        let alert = aps?["alert"] as? [String: Any]
        let title = alert?["title"] as? String ?? ""
        let body  = alert?["body"] as? String ?? ""

        if !title.isEmpty || !body.isEmpty {
            LogManager.shared.log(category: .general, message: "Notification - Title: \(title), Body: \(body)")
        }

        let contentAvailable = (aps?["content-available"] as? Int) == 1
        guard contentAvailable else { return .noData }

        // ✅ Don’t capture `application` inside MainActor.run
        let stateString: String = await MainActor.run {
            switch UIApplication.shared.applicationState {
            case .active: return "ACTIVE"
            case .inactive: return "INACTIVE"
            case .background: return "BACKGROUND"
            @unknown default: return "UNKNOWN"
            }
        }

        LogManager.shared.log(
            category: .general,
            message: "✅ SILENT PUSH WAKE state=\(stateString) at \(Date())"
        )

        let nsURL = NightscoutSettings.getBaseURL()
        let nsTokenSet = (NightscoutSettings.getToken()?.isEmpty == false)

        LogManager.shared.log(
            category: .general,
            message: "🔎 SILENT PUSH Nightscout config — url=\(nsURL ?? "nil") tokenSet=\(nsTokenSet)"
        )

        guard nsURL != nil else {
            LogManager.shared.log(category: .general, message: "❌ SILENT PUSH aborted: Nightscout base URL is nil")
            return .failed
        }

        // ✅ Don’t capture `application` inside MainActor.run
        let bgTask: UIBackgroundTaskIdentifier = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: "SilentPushRefresh") {
                LogManager.shared.log(category: .general, message: "⏱️ SILENT PUSH background time expired")
            }
        }
        defer {
            Task { @MainActor in
                UIApplication.shared.endBackgroundTask(bgTask)
            }
        }

        do {
            LogManager.shared.log(category: .general, message: "➡️ SILENT PUSH calling NightscoutUpdater.refreshData()")
            try await NightscoutUpdater.shared.refreshData()

            do {
                let snap = try await fetchLatestLoopIOBCOBFromNightscout()

                if let iob = snap.iob { Storage.shared.latestIOB.value = iob }
                if let cob = snap.cob { Storage.shared.latestCOB.value = cob }

                let iobText = snap.iob.map { String(format: "%.2f", $0) }
                let cobText = snap.cob.map { String(format: "%.0f", $0) }

                LogManager.shared.log(
                    category: .general,
                    message: "✅ SILENT PUSH deviceStatus iob=\(iobText ?? "nil") cob=\(cobText ?? "nil")"
                )
            } catch {
                LogManager.shared.log(category: .general, message: "⚠️ SILENT PUSH deviceStatus fetch failed: \(error)")
            }

            LogManager.shared.log(category: .general, message: "➡️ SILENT PUSH refreshing Live Activity")
            await LiveActivityManager.shared.refreshFromCurrentState()
            LogManager.shared.log(category: .general, message: "✅ SILENT PUSH Live Activity updated")

            return .newData
        } catch {
            LogManager.shared.log(category: .general, message: "❌ SILENT PUSH update failed: \(error)")
            return .failed
        }
    }

    // MARK: UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UIApplication.shared.isIdleTimerDisabled = Storage.shared.screenlockSwitchState.value
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}

    // MARK: - Core Data stack

    lazy var persistentContainer: NSPersistentCloudKitContainer = {
        let container = NSPersistentCloudKitContainer(name: "LoopFollow")
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        return container
    }()

    func saveContext() {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == "OPEN_APP_ACTION" {
            if let window = window {
                window.rootViewController?.dismiss(animated: true, completion: nil)
                window.rootViewController?.present(MainViewController(), animated: true, completion: nil)
            }
        }

        if response.actionIdentifier == "snooze" {
            AlarmManager.shared.performSnooze()
        }

        completionHandler()
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        let forcePortrait = Storage.shared.forcePortraitMode.value
        return forcePortrait ? .portrait : .all
    }

    // =========================================================
    // Long-press gesture: show BundleID + APNs token + set Nightscout URL/token
    // =========================================================

    private func installDebugLongPressGesture() {
        let targetWindow = window ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })

        guard let w = targetWindow else {
            LogManager.shared.log(category: .general, message: "Debug long-press: no key window yet")
            return
        }

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleDebugLongPress(_:)))
        longPress.minimumPressDuration = 0.8
        longPress.cancelsTouchesInView = false
        w.addGestureRecognizer(longPress)

        LogManager.shared.log(category: .general, message: "Debug long-press installed (hold ~0.8s anywhere)")
    }

    @objc private func handleDebugLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        guard let presenter = topViewController() else { return }

        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let token = lastAPNSTokenString ?? Observable.shared.loopFollowDeviceToken.value

        let nsURL = NightscoutSettings.getBaseURL() ?? "(not set)"
        let hasToken = (NightscoutSettings.getToken() != nil)

        // Log for copy/paste from Logs screen
        LogManager.shared.log(category: .general, message: "DEBUG — Bundle ID: \(bundleID)")
        LogManager.shared.log(category: .general, message: "DEBUG — APNs Token: \(token)")
        LogManager.shared.log(category: .general, message: "DEBUG — Nightscout URL: \(nsURL)")
        LogManager.shared.log(category: .general, message: "DEBUG — Nightscout token set: \(hasToken)")

        let menu = UIAlertController(
            title: "LoopFollow Debug",
            message: "Bundle:\n\(bundleID)\n\nAPNs Token:\n\(token)\n\nNightscout:\n\(nsURL)\nToken set: \(hasToken ? "YES" : "NO")",
            preferredStyle: .actionSheet
        )

        menu.addAction(UIAlertAction(title: "Set Nightscout URL", style: .default) { _ in
            self.promptForText(
                on: presenter,
                title: "Nightscout URL",
                message: "Example: https://glyc.philh4.com",
                placeholder: "https://…"
            ) { text in
                let ok = NightscoutSettings.setBaseURL(text)
                self.toast(on: presenter, ok ? "Saved URL" : "Invalid URL")
            }
        })

        menu.addAction(UIAlertAction(title: "Set Readable Token", style: .default) { _ in
            self.promptForText(
                on: presenter,
                title: "Readable Token",
                message: "Paste your new Nightscout readable token",
                placeholder: "token…"
            ) { text in
                let ok = NightscoutSettings.setToken(text)
                self.toast(on: presenter, ok ? "Saved token" : "Invalid token")
            }
        })

        menu.addAction(UIAlertAction(title: "Test Fetch Now", style: .default) { _ in
            Task {
                do {
                    try await NightscoutUpdater.shared.refreshData()
                    self.toast(on: presenter, "Fetched + updated Live Activity ✅")
                } catch {
                    self.toast(on: presenter, "Fetch failed: \(error.localizedDescription)")
                }
            }
        })

        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        // iPad safety
        if let pop = menu.popoverPresentationController {
            pop.sourceView = presenter.view
            pop.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }

        presenter.present(menu, animated: true)
    }

    private func promptForText(
        on vc: UIViewController,
        title: String,
        message: String,
        placeholder: String,
        completion: @escaping (String) -> Void
    ) {
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addTextField { tf in
            tf.placeholder = placeholder
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            completion(a.textFields?.first?.text ?? "")
        })
        vc.present(a, animated: true)
    }

    private func toast(on vc: UIViewController, _ msg: String) {
        let a = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
        vc.present(a, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            a.dismiss(animated: true)
        }
    }

    private func topViewController() -> UIViewController? {
        let root = (window?.rootViewController) ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController

        var top = root
        while true {
            if let presented = top?.presentedViewController {
                top = presented
            } else if let nav = top as? UINavigationController {
                top = nav.visibleViewController
            } else if let tab = top as? UITabBarController {
                top = tab.selectedViewController
            } else {
                break
            }
        }
        return top
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        LogManager.shared.log(category: .general, message: "Will present notification: \(userInfo)")
        completionHandler([.banner, .sound, .badge])
    }
}
