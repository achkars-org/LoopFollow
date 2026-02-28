// LAHeartbeatStore.swift
// Philippe Achkar
// 2026-02-28

import Foundation

final class LAHeartbeatStore {

    static let shared = LAHeartbeatStore()
    private init() {}

    private let key = "la.heartbeat.lastRefreshEpoch"

    func setNow() {
        let epoch = Date().timeIntervalSince1970
        UserDefaults(suiteName: AppGroupID.current())?.set(epoch, forKey: key)
    }

    func get() -> Date? {
        guard let epoch = UserDefaults(suiteName: AppGroupID.current())?.object(forKey: key) as? Double else {
            return nil
        }
        return Date(timeIntervalSince1970: epoch)
    }
}
