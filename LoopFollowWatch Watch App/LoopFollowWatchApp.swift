// LoopFollowWatchApp.swift
// Philippe Achkar
// 2026-03-10

import SwiftUI
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

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refreshTask as WKApplicationRefreshBackgroundTask:
                handleRefresh(refreshTask)
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    private func handleRefresh(_ task: WKApplicationRefreshBackgroundTask) {
        // Read latest snapshot from store — written by WatchConnectivity deliveries
        if let snapshot = GlucoseSnapshotStore.shared.load() {
            WatchSessionReceiver.shared.reloadComplicationsIfNeeded(for: snapshot)
        }
        // Schedule next background wake to stay in sync with iPhone's 5-min BG cycle
        scheduleNextRefresh()
        task.setTaskCompletedWithSnapshot(false)
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
