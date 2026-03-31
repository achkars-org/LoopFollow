// WatchSessionReceiver.swift
// 2026-03-10

import Foundation
import WatchConnectivity
import ClockKit
import WatchKit
import os.log

private let watchLog = OSLog(
    subsystem: Bundle.main.bundleIdentifier ?? "com.loopfollow.watch",
    category: "Watch"
)

final class WatchSessionReceiver: NSObject {

    // MARK: - Shared Instance

    static let shared = WatchSessionReceiver()

    // MARK: - State

    private var pendingConnectivityTask: WKWatchConnectivityRefreshBackgroundTask?

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

        let session = WCSession.default
        session.delegate = self
        session.activate()

        os_log("WatchSessionReceiver: WCSession activation requested", log: watchLog, type: .debug)
    }

    // MARK: - Background Task Handling

    func beginHandling(task: WKWatchConnectivityRefreshBackgroundTask) {
        pendingConnectivityTask = task
        os_log("WatchSessionReceiver: began background connectivity task", log: watchLog, type: .debug)
    }

    private func finishPendingTask(snapshotReloaded: Bool) {
        pendingConnectivityTask?.setTaskCompletedWithSnapshot(snapshotReloaded)
        pendingConnectivityTask = nil

        os_log(
            "WatchSessionReceiver: completed background connectivity task snapshotReloaded=%{public}@",
            log: watchLog,
            type: .debug,
            String(snapshotReloaded)
        )
    }

    // MARK: - Payload Handling

    private func handleSnapshotPayload(_ payload: [String: Any], source: String) {
        guard let data = payload["snapshot"] as? Data else {
            os_log(
                "WatchSessionReceiver: %{public}@ received with no snapshot key",
                log: watchLog,
                type: .debug,
                source
            )
            finishPendingTask(snapshotReloaded: false)
            return
        }

        do {
            let snapshot = try JSONDecoder().decode(GlucoseSnapshot.self, from: data)
            GlucoseSnapshotStore.shared.save(snapshot)

            os_log(
                "WatchSessionReceiver: snapshot saved from %{public}@ glucose=%{public}d updatedAt=%{public}@",
                log: watchLog,
                type: .debug,
                source,
                snapshot.glucose,
                snapshot.updatedAt as NSDate
            )

            reloadComplications()
            finishPendingTask(snapshotReloaded: true)
        } catch {
            os_log(
                "WatchSessionReceiver: failed to decode snapshot from %{public}@ — %{public}@",
                log: watchLog,
                type: .error,
                source,
                error.localizedDescription
            )
            finishPendingTask(snapshotReloaded: false)
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

        os_log(
            "WatchSessionReceiver: reloaded %d complication(s)",
            log: watchLog,
            type: .debug,
            complications.count
        )
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
            os_log(
                "WatchSessionReceiver: activation failed — %{public}@",
                log: watchLog,
                type: .error,
                error.localizedDescription
            )
        } else {
            os_log(
                "WatchSessionReceiver: activation complete — state %d",
                log: watchLog,
                type: .debug,
                activationState.rawValue
            )
        }
    }

    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        handleSnapshotPayload(userInfo, source: "didReceiveUserInfo")
    }

    func session(
        _ session: WCSession,
        didReceiveComplicationUserInfo complicationUserInfo: [String: Any] = [:]
    ) {
        handleSnapshotPayload(complicationUserInfo, source: "didReceiveComplicationUserInfo")
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        handleSnapshotPayload(applicationContext, source: "didReceiveApplicationContext")
    }
}