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

    // ✅ NEW: Keep the last-known token so the long-press can show it anytime
    private var lastAPNSTokenString: String?

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        LogManager.shared.log(category: .general, message: "App started")
        LogManager.shared.cleanupOldLogs()

        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        notificationCenter.requestAuthorization(options: options) {
            didAllow, _ in
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
        let category = UNNotificationCategory(identifier: "loopfollow.background.alert", actions: [action], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])

        UNUserNotificationCenter.current().delegate = self

        _ = BLEManager.shared
        // Ensure VolumeButtonHandler is initialized so it can receive alarm notifications
        _ = VolumeButtonHandler.shared

        // 🔥 START LIVE ACTIVITY HERE
        LiveActivityManager.shared.startIfNeeded()
        
        // ✅ NEW: Add a long-press gesture to the app window to show token + bundle id
        DispatchQueue.main.async { [weak self] in
            self?.installDebugLongPressGesture()
        }

        // Register for remote notifications
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return true
    }

    func applicationWillTerminate(_: UIApplication) {}

    // MARK: - Remote Notifications

    // Called when successfully registered for remote notifications
    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()

        // ✅ NEW: store it for the long-press
        lastAPNSTokenString = tokenString

        Observable.shared.loopFollowDeviceToken.value = tokenString

        // ✅ NEW: also log bundle id right here so you get it the moment registration succeeds
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        LogManager.shared.log(category: .general, message: "Bundle ID: \(bundleID)")
        LogManager.shared.log(category: .general, message: "Successfully registered for remote notifications with token: \(tokenString)")
    }

    // Called when failed to register for remote notifications
    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        LogManager.shared.log(category: .general, message: "Failed to register for remote notifications: \(error.localizedDescription)")
    }

    // Called when a remote notification is received
    func application(_: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        LogManager.shared.log(category: .general, message: "Received remote notification: \(userInfo)")

        // Check if this is a notification from Trio with status update
        if let aps = userInfo["aps"] as? [String: Any] {
            // Handle visible notification (alert, sound, badge)
            if let alert = aps["alert"] as? [String: Any] {
                let title = alert["title"] as? String ?? ""
                let body = alert["body"] as? String ?? ""
                LogManager.shared.log(category: .general, message: "Notification - Title: \(title), Body: \(body)")
            }

            // Handle silent notification (content-available)
            if let contentAvailable = aps["content-available"] as? Int, contentAvailable == 1 {
                // This is a silent push, nothing implemented but logging for now

                if let commandStatus = userInfo["command_status"] as? String {
                    LogManager.shared.log(category: .general, message: "Command status: \(commandStatus)")
                }

                if let commandType = userInfo["command_type"] as? String {
                    LogManager.shared.log(category: .general, message: "Command type: \(commandType)")
                }
            }
        }

        // Call completion handler
        completionHandler(.newData)
    }

    // MARK: UISceneSession Lifecycle

    func application(_: UIApplication, willFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // set the "prevent screen lock" option when the app is started
        // This method doesn't seem to be working anymore. Added to view controllers as solution offered on SO
        UIApplication.shared.isIdleTimerDisabled = Storage.shared.screenlockSwitchState.value

        return true
    }

    func application(_: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options _: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_: UIApplication, didDiscardSceneSessions _: Set<UISceneSession>) {}

    // MARK: - Core Data stack
    lazy var persistentContainer: NSPersistentCloudKitContainer = {
        let container = NSPersistentCloudKitContainer(name: "LoopFollow")
        container.loadPersistentStores(completionHandler: { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        return container
    }()

    // MARK: - Core Data Saving support
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

    func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
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

    func application(_: UIApplication, supportedInterfaceOrientationsFor _: UIWindow?) -> UIInterfaceOrientationMask {
        let forcePortrait = Storage.shared.forcePortraitMode.value
        return forcePortrait ? .portrait : .all
    }

    // =========================================================
    // ✅ NEW: Long-press gesture + presenter
    // =========================================================

    private func installDebugLongPressGesture() {
        // If the window isn’t ready yet, try to find the key window.
        let targetWindow = window ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })

        guard let w = targetWindow else { return }

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleDebugLongPress(_:)))
        longPress.minimumPressDuration = 0.8
        longPress.cancelsTouchesInView = false
        w.addGestureRecognizer(longPress)

        LogManager.shared.log(category: .general, message: "Debug long-press installed (hold ~0.8s anywhere)")
    }

    @objc private func handleDebugLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }

        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let token = lastAPNSTokenString ?? Observable.shared.loopFollowDeviceToken.value ?? "Token not yet available"

        // Log (easy to copy from Logs screen)
        LogManager.shared.log(category: .general, message: "DEBUG — Bundle ID: \(bundleID)")
        LogManager.shared.log(category: .general, message: "DEBUG — APNs Token: \(token)")

        // Also show an on-screen alert for quick viewing
        let message = "Bundle ID:\n\(bundleID)\n\nAPNs Token:\n\(token)"
        let alert = UIAlertController(title: "APNs Debug Info", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))

        // Present from the top-most view controller
        if let presenter = topViewController() {
            presenter.present(alert, animated: true, completion: nil)
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
    func userNotificationCenter(_: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    {
        // Log the notification
        let userInfo = notification.request.content.userInfo
        LogManager.shared.log(category: .general, message: "Will present notification: \(userInfo)")

        // Show the notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
}
