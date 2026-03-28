// LoopFollowWatchApp.swift
// Philippe Achkar
// 2026-03-10

import SwiftUI
import WatchConnectivity
import WatchKit

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
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    private func handleRefresh(_ task: WKApplicationRefreshBackgroundTask) {
        // receivedApplicationContext always holds the last value the iPhone sent —
        // no active Bluetooth or WKWatchConnectivityRefreshBackgroundTask needed.
        // If it's newer than what's in the file store, persist it and reload complications.
        let contextSnapshot = Self.decodeContextSnapshot()
        let storeSnapshot   = GlucoseSnapshotStore.shared.load()

        let useContext = contextSnapshot != nil && (
            storeSnapshot == nil ||
            contextSnapshot!.updatedAt > storeSnapshot!.updatedAt
        )

        if useContext, let ctx = contextSnapshot {
            GlucoseSnapshotStore.shared.save(ctx) {
                WatchSessionReceiver.shared.reloadComplicationsIfNeeded(for: ctx)
                WatchAppDelegate.scheduleNextRefresh()
                task.setTaskCompletedWithSnapshot(false)
            }
        } else {
            if let snapshot = storeSnapshot {
                WatchSessionReceiver.shared.reloadComplicationsIfNeeded(for: snapshot)
            }
            WatchAppDelegate.scheduleNextRefresh()
            task.setTaskCompletedWithSnapshot(false)
        }
    }

    static func decodeContextSnapshot() -> GlucoseSnapshot? {
        guard let data = WCSession.default.receivedApplicationContext["snapshot"] as? Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GlucoseSnapshot.self, from: data)
    }

    static func scheduleNextRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: 5 * 60),
            userInfo: nil
        ) { _ in }
    }

    private func scheduleNextRefresh() {
        WatchAppDelegate.scheduleNextRefresh()
    }
}
