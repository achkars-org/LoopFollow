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

        let session = WCSession.default
        session.delegate = self
        session.activate()
        LogManager.shared.log(category: .watch, message: "WatchConnectivityManager: WCSession activation requested")
    }

    // MARK: - Send Snapshot

    /// Sends the latest GlucoseSnapshot to the Watch.
    /// - Uses application context for latest-state sync.
    /// - Uses complication transfer when available.
    /// - Falls back to transferUserInfo otherwise.
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

        guard session.isWatchAppInstalled else {
            LogManager.shared.log(category: .watch, message: "WatchConnectivityManager: Watch app not installed, skipping send")
            return
        }

        do {
            let data = try JSONEncoder().encode(snapshot)
            let payload: [String: Any] = ["snapshot": data]

            do {
                try session.updateApplicationContext(payload)
                LogManager.shared.log(category: .watch, message: "WatchConnectivityManager: application context updated")
            } catch {
                LogManager.shared.log(category: .watch, message: "WatchConnectivityManager: failed to update application context — \(error)")
            }

            if session.isComplicationEnabled {
                let remaining = session.remainingComplicationUserInfoTransfers
                LogManager.shared.log(
                    category: .watch,
                    message: "WatchConnectivityManager: complication enabled, remaining transfers = \(remaining)"
                )

                if remaining > 0 {
                    session.transferCurrentComplicationUserInfo(payload)
                    LogManager.shared.log(category: .watch, message: "WatchConnectivityManager: snapshot sent via complication transfer")
                    return
                } else {
                    LogManager.shared.log(category: .watch, message: "WatchConnectivityManager: no remaining complication transfers, falling back to transferUserInfo")
                }
            } else {
                LogManager.shared.log(category: .watch, message: "WatchConnectivityManager: complication not enabled, using transferUserInfo")
            }

            session.transferUserInfo(payload)
            LogManager.shared.log(category: .watch, message: "WatchConnectivityManager: snapshot transferred via userInfo")
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

    func sessionWatchStateDidChange(_ session: WCSession) {
        LogManager.shared.log(
            category: .watch,
            message: "WatchConnectivityManager: watch state changed paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) complicationEnabled=\(session.isComplicationEnabled)"
        )
    }
}