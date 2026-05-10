// LoopFollow
// ComplicationRefreshCounter.swift

import Foundation

final class ComplicationRefreshCounter {
    static let shared = ComplicationRefreshCounter()
    private init() {}

    private let timestampsKey = "complicationRefreshTimestamps"
    private let lastSeenKey = "complicationLastSnapshotTime"

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroupID.current())
    }

    /// Records a complication refresh for the given snapshot timestamp.
    /// Deduplicates: if the same snapshot time has already been counted (e.g. from
    /// a duplicate WCSession channel delivery), the call is a no-op.
    func recordRefresh(snapshotTime: Date) {
        let t = snapshotTime.timeIntervalSince1970
        let lastSeen = defaults?.double(forKey: lastSeenKey) ?? 0
        guard t > lastSeen else { return }
        defaults?.set(t, forKey: lastSeenKey)

        var ts = storedTimestamps()
        let now = Date().timeIntervalSince1970
        ts.append(now)
        ts = ts.filter { now - $0 < 86400 }
        defaults?.set(ts, forKey: timestampsKey)
    }

    var hourCount: Int {
        let cutoff = Date().timeIntervalSince1970 - 3600
        return storedTimestamps().filter { $0 > cutoff }.count
    }

    var dayCount: Int {
        storedTimestamps().count
    }

    private func storedTimestamps() -> [Double] {
        defaults?.array(forKey: timestampsKey) as? [Double] ?? []
    }
}
