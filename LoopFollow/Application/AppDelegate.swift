// LoopFollow
// AppDelegate.swift

import CoreData
import EventKit
import UIKit
import UserNotifications


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    var window: UIWindow?
    private let notificationCenter = UNUserNotificationCenter.current()

    // Cache the last-known APNs token so the long-press can show it anytime
    private var lastAPNSTokenString: String?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        LogManager.shared.log(category: .liveactivities, message: "App started")
        LogManager.shared.cleanupOldLogs()

        // App Group migration for Nightscout URL/token (legacy -> App Group)
        // NOTE: If you have adopted the dynamic "Group ID" concept elsewhere, replace this hardcoded value.
        let appGroupID = "group.com.2HEY366Q6J.LoopFollow"
        AppGroupStorageValue<String>.migrateFromStandardIfNeeded(appGroupID: appGroupID, key: "url")
        AppGroupStorageValue<String>.migrateFromStandardIfNeeded(appGroupID: appGroupID, key: "token")

        // Nightscout settings migration (legacy -> current)
        NightscoutSettings.migrateLegacyIfNeeded()

        // Re-save the existing Nightscout token so it picks up Keychain accessibility (AfterFirstUnlock)
        migrateNightscoutTokenAccessibilityIfNeeded()

        // Sync user BG thresholds to App Group for Live Activity / Widget
        Storage.shared.laLowLineMgdl.value  = Storage.shared.lowLine.value
        Storage.shared.laHighLineMgdl.value = Storage.shared.highLine.value

        // One-time sanity check: safe fingerprint (no token leak)
        let url = Storage.shared.url.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = Storage.shared.token.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlDisplay = url.isEmpty ? "empty" : url
        let tokenTail = token.isEmpty ? "empty" : String(token.suffix(6))

        LogManager.shared.log(
            category: .liveactivities,
            message: "Nightscout Storage url=\(urlDisplay) tokenLen=\(token.count) tokenTail=\(tokenTail)"
        )

        // Notifications
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        notificationCenter.requestAuthorization(options: options) { didAllow, _ in
            if !didAllow {
                LogManager.shared.log(category: .liveactivities, message: "User declined notifications")
            }
        }

        // Calendar permissions (LoopFollow existing behavior)
        let store = EKEventStore()
        store.requestCalendarAccess { granted, error in
            if !granted {
                LogManager.shared.log(category: .calendar, message: "Calendar access denied: \(String(describing: error))")
            }
        }

        // Notification category for in-app open action
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

        LiveActivityManager.shared.startIfNeeded()

        // Long-press gesture: show Bundle ID + APNs token
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

    // MARK: - Token migration helper

    private func migrateNightscoutTokenAccessibilityIfNeeded() {
        let key = "nightscout_readable_token"

        guard let existing = KeychainStore.get(key),
              !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            LogManager.shared.log(category: .liveactivities, message: "Token migration: nothing to migrate")
            return
        }

        let ok = KeychainStore.set(existing, for: key)
        LogManager.shared.log(category: .liveactivities, message: "Token migration: re-saved ok=\(ok) len=\(existing.count)")
    }

    // MARK: - APNs Registration

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()

        lastAPNSTokenString = tokenString
        Observable.shared.loopFollowDeviceToken.value = tokenString

        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        LogManager.shared.log(category: .liveactivities, message: "APNs registered bundleID=\(bundleID) tokenLen=\(tokenString.count)")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        LogManager.shared.log(category: .liveactivities, message: "APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: - Silent Push (Swift 6 sendability-safe)

    /// Silent push handler using completionHandler API to avoid Swift 6 non-Sendable async warnings.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Extract what we need immediately (don’t keep/capture userInfo across concurrency hops)
        let aps = userInfo["aps"] as? [String: Any]
        let alert = aps?["alert"] as? [String: Any]
        let title = alert?["title"] as? String ?? ""
        let body  = alert?["body"] as? String ?? ""

        let contentAvailable: Bool = {
            if let i = aps?["content-available"] as? Int { return i == 1 }
            if let b = aps?["content-available"] as? Bool { return b == true }
            return false
        }()

        // Only log user-visible alert content when present (avoid dumping userInfo)
        if !title.isEmpty || !body.isEmpty {
            LogManager.shared.log(category: .liveactivities, message: "Remote notif alert title=\(title) body=\(body)")
        }

        // We only treat content-available pushes as "silent push" signals
        guard contentAvailable else {
            completionHandler(.noData)
            return
        }

        // IMPORTANT: mark receipt immediately so polling can be suppressed for the next 300s.
        LASilentPushGate.markSilentPushReceived()
        LogManager.shared.log(category: .liveactivities, message: "[LA] silent push received (gate marked)")

        let stateString: String
        switch application.applicationState {
        case .active: stateString = "ACTIVE"
        case .inactive: stateString = "INACTIVE"
        case .background: stateString = "BACKGROUND"
        @unknown default: stateString = "UNKNOWN"
        }
        LogManager.shared.log(category: .liveactivities, message: "Silent push wake state=\(stateString)")

        // Background time for the refresh + LA update
        let bgTask = application.beginBackgroundTask(withName: "SilentPushRefresh") {
            LogManager.shared.log(category: .liveactivities, message: "Silent push background time expired")
        }

        Task {
            defer {
                DispatchQueue.main.async {
                    if bgTask != .invalid {
                        application.endBackgroundTask(bgTask)
                    }
                }
            }

            do {
                // Trigger LoopFollow's normal refresh path (DexShare or NS) once
                try await awaitLoopFollowRefresh(timeoutSeconds: 25)

                // Then paint Live Activity from updated shared state
                await LiveActivityManager.shared.refreshFromCurrentState(source: "silent_push")

                LogManager.shared.log(category: .liveactivities, message: "Silent push completed")
                completionHandler(.newData)
            } catch {
                LogManager.shared.log(category: .liveactivities, message: "Silent push update failed: \(error)")
                completionHandler(.failed)
            }
        }
    }

    // MARK: - LoopFollow refresh bridge (Notification-based)

    private enum SilentPushRefreshError: Error {
        case timeout
    }

    /// Posts a refresh request to LoopFollow's existing pipeline and waits for completion.
    /// - Important: The refresh owner MUST post `.loopFollowRefreshDidFinish` once per request.
    private func awaitLoopFollowRefresh(timeoutSeconds: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var finished = false

            let token = NotificationCenter.default.addObserver(
                forName: .loopFollowRefreshDidFinish,
                object: nil,
                queue: nil
            ) { note in
                guard !finished else { return }
                finished = true
                NotificationCenter.default.removeObserver(token)

                let ok = (note.userInfo?["ok"] as? Bool) ?? false
                if ok {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "LoopFollowRefresh",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "LoopFollow refresh reported ok=false"]
                    ))
                }
            }

            // Post AFTER subscribing so we can't miss a fast completion.
            NotificationCenter.default.post(name: .loopFollowRefreshRequested, object: nil)

            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                guard !finished else { return }
                finished = true
                NotificationCenter.default.removeObserver(token)
                continuation.resume(throwing: SilentPushRefreshError.timeout)
            }
        }
    }

    // MARK: - UISceneSession Lifecycle

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

    // MARK: - Notification Actions

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case "OPEN_APP_ACTION":
            // Don’t instantiate MainViewController() directly (outlets/storyboard won’t be wired).
            // Instead, bring the existing UI to the front and navigate to the Home tab/root.
            DispatchQueue.main.async { [weak self] in
                self?.navigateToHome()
            }

        case "snooze":
            AlarmManager.shared.performSnooze()

        default:
            break
        }

        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Foreground presentation only (not the silent push signal).
        // Keep logging minimal: keys are enough for debugging.
        let keys = Array(notification.request.content.userInfo.keys)
        LogManager.shared.log(category: .liveactivities, message: "Will present notification (keys): \(keys)")
        completionHandler([.banner, .sound, .badge])
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        let forcePortrait = Storage.shared.forcePortraitMode.value
        return forcePortrait ? .portrait : .all
    }

    private func navigateToHome() {
        guard let root = (window?.rootViewController ?? keyWindowRootViewController()) else { return }

        // Dismiss anything presented
        root.dismiss(animated: false)

        if let tab = root as? UITabBarController {
            tab.selectedIndex = 0
            if let nav = tab.selectedViewController as? UINavigationController {
                nav.popToRootViewController(animated: false)
            }
            return
        }

        if let nav = root as? UINavigationController {
            nav.popToRootViewController(animated: false)
        }
    }

    private func keyWindowRootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController
    }

    // MARK: - Long-press Debug Menu (Bundle ID + APNs token only)

    private func installDebugLongPressGesture() {
        let targetWindow = window ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })

        guard let w = targetWindow else {
            LogManager.shared.log(category: .liveactivities, message: "Long-press debug: no key window yet")
            return
        }

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleDebugLongPress(_:)))
        longPress.minimumPressDuration = 0.8
        longPress.cancelsTouchesInView = false
        w.addGestureRecognizer(longPress)

        LogManager.shared.log(category: .liveactivities, message: "Long-press debug installed")
    }

    @objc private func handleDebugLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        guard let presenter = topViewController() else { return }

        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let token = lastAPNSTokenString ?? Observable.shared.loopFollowDeviceToken.value

        LogManager.shared.log(category: .liveactivities, message: "Debug bundleID=\(bundleID)")
        LogManager.shared.log(category: .liveactivities, message: "Debug apnsToken=\(token)")

        let menu = UIAlertController(
            title: "LoopFollow Debug",
            message: "Bundle:\n\(bundleID)\n\nAPNs Token:\n\(token)",
            preferredStyle: .actionSheet
        )
        menu.addAction(UIAlertAction(title: "OK", style: .cancel))

        if let pop = menu.popoverPresentationController {
            pop.sourceView = presenter.view
            pop.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }

        presenter.present(menu, animated: true)
    }

    private func topViewController() -> UIViewController? {
        let root = (window?.rootViewController) ?? keyWindowRootViewController()

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