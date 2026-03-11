// LoopFollowWatchApp.swift
// Philippe Achkar
// 2026-03-10

import SwiftUI

@main
struct LoopFollowWatch_Watch_AppApp: App {

    init() {
        WatchSessionReceiver.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
