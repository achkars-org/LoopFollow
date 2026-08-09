// LoopFollow
// ComplicationRefreshCounter.swift

import Foundation

final class ComplicationRefreshCounter {
    static let shared = ComplicationRefreshCounter()
    private init() {}

    private let timestampsKey = "complicationRefreshTimestamps"
    private let lastReloadedSnapshotUpdatedAtKey = "complicationLastReloadedSnapshotUpdatedAt"

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroupID.current())
    }

    private var lastReloadedSnapshotUpdatedAt: TimeInterval {
        get { defaults?.double(forKey: lastReloadedSnapshotUpdatedAtKey) ?? 0 }
        set { defaults?.set(newValue, forKey: lastReloadedSnapshotUpdatedAtKey) }
    }

    /// Returns true and records a refresh if the snapshot's updatedAt is newer than the last
    /// reloaded snapshot. Returns false without side effects if the snapshot is a duplicate.
    func shouldReloadAndRecord(for snapshot: GlucoseSnapshot) -> Bool {
        let snapshotTime = snapshot.updatedAt.timeIntervalSince1970
        guard snapshotTime > lastReloadedSnapshotUpdatedAt else { return false }
        lastReloadedSnapshotUpdatedAt = snapshotTime
        recordRefresh()
        return true
    }

    func recordRefresh() {
        var ts = storedTimestamps()
        let now = Date().timeIntervalSince1970
        ts.append(now)
        ts = ts.filter { now - $0 < 86400 }
        defaults?.set(ts, forKey: timestampsKey)
    }

    func resetCounter() {
        defaults?.removeObject(forKey: timestampsKey)
    }

    var hourCount: Int {
        let cutoff = Date().timeIntervalSince1970 - 3600
        return storedTimestamps().filter { $0 > cutoff }.count
    }

    var dayCount: Int {
        storedTimestamps().count
    }

    var timeSinceLastRefresh: TimeInterval {
        guard let latest = storedTimestamps().max() else { return .infinity }
        return Date().timeIntervalSince1970 - latest
    }

    private func storedTimestamps() -> [Double] {
        defaults?.array(forKey: timestampsKey) as? [Double] ?? []
    }
}
