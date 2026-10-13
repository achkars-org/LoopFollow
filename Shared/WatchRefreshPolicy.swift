// LoopFollow
// WatchRefreshPolicy.swift

import Foundation

/// Pure timing and deduplication rules shared by the iPhone and Watch sides of the
/// Watch data pipeline. Kept free of WatchKit/WatchConnectivity so it compiles into
/// every target and can be unit tested from the iOS test target.
enum WatchRefreshPolicy {
    /// CGM readings arrive roughly every five minutes.
    static let readingInterval: TimeInterval = 5 * 60
    /// Cushion for sensor → phone → Nightscout upload latency.
    static let uploadBuffer: TimeInterval = 10
    /// Shortest wake we ask for when the next reading is already due.
    static let lateReadingFloor: TimeInterval = 60
    /// Longest daytime wait, used when no reading has been seen yet.
    static let daytimeCeiling: TimeInterval = readingInterval + 30
    /// Overnight wake interval, chosen to preserve the background refresh budget.
    static let overnightInterval: TimeInterval = 20 * 60
    /// Minimum spacing between high-priority complication transfers from the phone.
    static let complicationPushInterval: TimeInterval = 30 * 60

    /// Hours 0–6 inclusive (midnight to 6:59) are treated as overnight.
    static func isOvernight(hour: Int) -> Bool {
        (0 ... 6).contains(hour)
    }

    /// Delay until the next background refresh. During the day the wake is timed for
    /// just after the next reading should land on Nightscout, rather than a fixed
    /// interval that can perpetually fire just before each new reading.
    static func nextRefreshDelay(lastReadingAt: Date?, now: Date, hour: Int) -> TimeInterval {
        if isOvernight(hour: hour) {
            return overnightInterval
        }
        guard let lastReadingAt else { return daytimeCeiling }
        let target = lastReadingAt.addingTimeInterval(readingInterval + uploadBuffer)
        let delay = target.timeIntervalSince(now)
        return min(max(delay, lateReadingFloor), daytimeCeiling)
    }

    /// A snapshot reloads complications only when it is strictly newer than the last
    /// one that did, so the same reading arriving over several channels reloads once.
    static func isNewReading(updatedAt: TimeInterval, lastReloadedAt: TimeInterval) -> Bool {
        updatedAt > lastReloadedAt
    }

    /// Whether the phone may spend one of the daily high-priority complication transfers.
    static func isComplicationPushDue(now: Date, lastPush: Date, remainingTransfers: Int) -> Bool {
        remainingTransfers > 0 && now.timeIntervalSince(lastPush) >= complicationPushInterval
    }
}
