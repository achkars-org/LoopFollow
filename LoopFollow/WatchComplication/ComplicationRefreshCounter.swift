// LoopFollow
// ComplicationRefreshCounter.swift

import Foundation

final class ComplicationRefreshCounter {
    static let shared = ComplicationRefreshCounter()
    private init() {}

    private let key = "complicationRefreshTimestamps"

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroupID.current())
    }

    func recordRefresh() {
        var ts = storedTimestamps()
        let now = Date().timeIntervalSince1970
        ts.append(now)
        ts = ts.filter { now - $0 < 86400 }
        defaults?.set(ts, forKey: key)
    }

    var hourCount: Int {
        let cutoff = Date().timeIntervalSince1970 - 3600
        return storedTimestamps().filter { $0 > cutoff }.count
    }

    var dayCount: Int {
        storedTimestamps().count
    }

    private func storedTimestamps() -> [Double] {
        defaults?.array(forKey: key) as? [Double] ?? []
    }
}
