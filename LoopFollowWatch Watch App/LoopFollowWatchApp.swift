// LoopFollowWatchApp.swift
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

// MARK: - App Delegate

final class WatchAppDelegate: NSObject, WKApplicationDelegate {

    func applicationDidFinishLaunching() {
        WatchSessionReceiver.shared.activate()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                WatchSessionReceiver.shared.beginHandling(task: connectivityTask)

            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}