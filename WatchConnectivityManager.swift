//
//  WatchConnectivityManager.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-03-10.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//


// WatchConnectivityManager.swift
// Philippe Achkar
// 2026-03-10

import Foundation
import WatchConnectivity

final class WatchConnectivityManager: NSObject {

    // MARK: - Shared Instance

    static let shared = WatchConnectivityManager()

    // MARK: - Init

    private override init() {
        super.init()
    }

    // MARK: - Setup

    /// Call once from AppDelegate after app launch.
    func activate() {
        guard WCSession.isSupported() else {
            LogManager.shared.log(category: .watch, message: "WatchConnectivityManager: WCSession not supported on this device")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        LogManager.shared.log(category: .watch, message: "WatchConnectivityManager: WCSession activation requested")
    }

    // MARK: - Send Snapshot

    /// Sends the latest GlucoseSnapshot to the Watch via transferUserInfo.
    /// Safe to call from any thread.
    /// No-ops silently if Watch is not paired or reachable.
    func send(snapshot: GlucoseSnapshot) {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default

        guard session.activationState == .activated else {
            LogManager.shared.log(category: .watch, message: "WatchConnectivityManager: session not activated, skipping send")
            return
        }

        guard session.isPaired else {
            LogManager.shared.log(category: .watch, message: "WatchConnectivityManager: no paired Watch, skipping send")
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            let payload: [String: Any] = ["snapshot": data]
            session.transferUserInfo(payload)
            try? session.updateApplicationContext(payload)
            LogManager.shared.log(category: .watch, message: "WatchConnectivityManager: snapshot transferred to Watch")
        } catch {
            LogManager.shared.log(category: .watch, message: "WatchConnectivityManager: failed to encode snapshot — \(error)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error = error {
            LogManager.shared.log(category: .watch, message: "WatchConnectivityManager: activation failed — \(error)")
        } else {
            LogManager.shared.log(category: .watch, message: "WatchConnectivityManager: activation complete — state \(activationState.rawValue)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        LogManager.shared.log(category: .watch, message: "WatchConnectivityManager: session became inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        LogManager.shared.log(category: .watch, message: "WatchConnectivityManager: session deactivated — reactivating")
        WCSession.default.activate()
    }
}