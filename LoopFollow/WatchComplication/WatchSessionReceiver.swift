// WatchSessionReceiver.swift
// Philippe Achkar
// 2026-03-10

import Foundation
import WatchConnectivity
import ClockKit
import os.log

private let watchLog = OSLog(
    subsystem: Bundle.main.bundleIdentifier ?? "com.loopfollow.watch",
    category: "Watch"
)

final class WatchSessionReceiver: NSObject {

    // MARK: - Shared Instance

    static let shared = WatchSessionReceiver()

    static let snapshotReceivedNotification = Notification.Name("WatchSnapshotReceived")

    // MARK: - Init

    private override init() {
        super.init()
    }

    // MARK: - Setup

    /// Call once from the Watch extension entry point after launch.
    func activate() {
        guard WCSession.isSupported() else {
            os_log("WatchSessionReceiver: WCSession not supported", log: watchLog, type: .debug)
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        os_log("WatchSessionReceiver: WCSession activation requested", log: watchLog, type: .debug)
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionReceiver: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error = error {
            os_log("WatchSessionReceiver: activation failed — %{public}@", log: watchLog, type: .error, error.localizedDescription)
        } else {
            os_log("WatchSessionReceiver: activation complete — state %d", log: watchLog, type: .debug, activationState.rawValue)
        }
    }

    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        guard let data = userInfo["snapshot"] as? Data else {
            os_log("WatchSessionReceiver: received userInfo with no snapshot key", log: watchLog, type: .debug)
            return
        }

        do {
            let snapshot = try JSONDecoder().decode(GlucoseSnapshot.self, from: data)
            GlucoseSnapshotStore.shared.save(snapshot)
            os_log("WatchSessionReceiver: snapshot saved, requesting complication reload", log: watchLog, type: .debug)
            reloadComplications()
            NotificationCenter.default.post(
                name: WatchSessionReceiver.snapshotReceivedNotification,
                object: nil,
                userInfo: ["snapshot": snapshot]
            )
        } catch {
            os_log("WatchSessionReceiver: failed to decode snapshot — %{public}@", log: watchLog, type: .error, error.localizedDescription)
        }
    }

    // MARK: - Private

    private func reloadComplications() {
        let server = CLKComplicationServer.sharedInstance()
        guard let complications = server.activeComplications, !complications.isEmpty else {
            os_log("WatchSessionReceiver: no active complications to reload", log: watchLog, type: .debug)
            return
        }
        for complication in complications {
            server.reloadTimeline(for: complication)
        }
        os_log("WatchSessionReceiver: reloaded %d complication(s)", log: watchLog, type: .debug, complications.count)
    }
}
