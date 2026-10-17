// LoopFollow
// LoopFollowWatchApp.swift

import OSLog
import SwiftUI
import WatchConnectivity
import WatchKit

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.loopfollow.watch",
    category: "Watch"
)

@main
struct LoopFollowWatch_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) var delegate

    init() {
        WatchSessionReceiver.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - App delegate for background tasks

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchAlertManager.shared.setup()
        WatchAppDelegate.scheduleNextRefresh()
    }

    /// The refresh chain only continues from a fired wake, so one missed wake would end it.
    /// Re-arming whenever the app is used or leaves the screen keeps a request pending.
    func applicationDidBecomeActive() {
        WatchEventLog.record("life", "app active")
        WatchAppDelegate.scheduleNextRefresh()
    }

    func applicationDidEnterBackground() {
        WatchEventLog.record("life", "app in background")
        WatchAppDelegate.scheduleNextRefresh()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refreshTask as WKApplicationRefreshBackgroundTask:
                handleRefresh(refreshTask)

            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                // Hold the task open — WatchConnectivity will deliver the pending
                // transferUserInfo to session(_:didReceiveUserInfo:) while the app
                // is awake. WatchSessionReceiver completes it after saving the snapshot.
                WatchSessionReceiver.shared.pendingConnectivityTask = connectivityTask
                WatchAppDelegate.scheduleNextRefresh()

            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    private func handleRefresh(_ task: WKApplicationRefreshBackgroundTask) {
        WatchEventLog.record("wake", "background refresh fired")
        // receivedApplicationContext always holds the last value the iPhone sent —
        // no active Bluetooth or WKWatchConnectivityRefreshBackgroundTask needed.
        // If it's newer than what's in the file store, persist it and reload complications.
        WatchSessionReceiver.shared.applySettings(from: WCSession.default.receivedApplicationContext)
        WatchSessionReceiver.shared.applyHistory(from: WCSession.default.receivedApplicationContext)
        WatchSessionReceiver.shared.applyStats(from: WCSession.default.receivedApplicationContext)
        let contextSnapshot = Self.decodeContextSnapshot()
        let storeSnapshot = GlucoseSnapshotStore.shared.load()

        if let ctx = contextSnapshot,
           ctx.updatedAt > (storeSnapshot?.updatedAt ?? .distantPast)
        {
            WatchAlertManager.shared.checkAndAlert(snapshot: ctx)
            WatchEventLog.record("wake", "newer phone context, saving")
            GlucoseSnapshotStore.shared.save(ctx) {
                ChannelDiagnosticsStore.shared.record(.watchWake)
                WatchSessionReceiver.shared.triggerComplicationReload()
                // Also poll NightScout — dedup gate prevents a double reload if same reading.
                WatchNightscoutFetcher.shared.handleRefreshTask {
                    DispatchQueue.main.async {
                        WatchAppDelegate.scheduleNextRefresh()
                        task.setTaskCompletedWithSnapshot(false)
                    }
                }
            }
        } else {
            // No newer applicationContext — poll NightScout directly.
            WatchEventLog.record("wake", "no newer phone context, polling Nightscout")
            WatchNightscoutFetcher.shared.handleRefreshTask {
                DispatchQueue.main.async {
                    WatchAppDelegate.scheduleNextRefresh()
                    task.setTaskCompletedWithSnapshot(false)
                }
            }
        }
    }

    static func decodeContextSnapshot() -> GlucoseSnapshot? {
        guard let data = WCSession.default.receivedApplicationContext["snapshot"] as? Data else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(GlucoseSnapshot.self, from: data)
        } catch {
            logger.error("WatchAppDelegate: failed to decode applicationContext snapshot — \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func scheduleNextRefresh() {
        let now = Date()
        let interval = WatchRefreshPolicy.nextRefreshDelay(
            lastReadingAt: GlucoseSnapshotStore.shared.load()?.updatedAt,
            now: now,
            hour: Calendar.current.component(.hour, from: now)
        )
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: now.addingTimeInterval(interval),
            userInfo: nil
        ) { error in
            let outcome = error.map { "failed: \($0.localizedDescription)" } ?? "ok"
            WatchEventLog.record("sched", "next wake in \(Int(interval))s, \(outcome)")
        }
    }
}
