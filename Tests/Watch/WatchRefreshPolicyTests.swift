// LoopFollow
// WatchRefreshPolicyTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct WatchRefreshPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let noon = 12

    // MARK: - Overnight window

    @Test("#hours 0 through 6 are overnight")
    func overnightHours() {
        for hour in 0 ... 6 {
            #expect(WatchRefreshPolicy.isOvernight(hour: hour), "hour \(hour)")
        }
    }

    @Test("#hours 7 through 23 are not overnight")
    func daytimeHours() {
        for hour in 7 ... 23 {
            #expect(!WatchRefreshPolicy.isOvernight(hour: hour), "hour \(hour)")
        }
    }

    // MARK: - Next refresh delay

    @Test("#overnight always uses the long interval")
    func overnightDelay() {
        let delay = WatchRefreshPolicy.nextRefreshDelay(lastReadingAt: now, now: now, hour: 3)
        #expect(delay == WatchRefreshPolicy.overnightInterval)
    }

    @Test("#no reading yet waits the daytime ceiling")
    func noReadingDelay() {
        let delay = WatchRefreshPolicy.nextRefreshDelay(lastReadingAt: nil, now: now, hour: noon)
        #expect(delay == WatchRefreshPolicy.daytimeCeiling)
    }

    @Test("#wakes just after the next reading is expected")
    func alignsToNextReading() {
        let reading = now.addingTimeInterval(-60)
        let delay = WatchRefreshPolicy.nextRefreshDelay(lastReadingAt: reading, now: now, hour: noon)
        #expect(delay == WatchRefreshPolicy.readingInterval + WatchRefreshPolicy.uploadBuffer - 60)
    }

    @Test("#a late reading is retried at the floor, not immediately")
    func lateReadingUsesFloor() {
        let reading = now.addingTimeInterval(-20 * 60)
        let delay = WatchRefreshPolicy.nextRefreshDelay(lastReadingAt: reading, now: now, hour: noon)
        #expect(delay == WatchRefreshPolicy.lateReadingFloor)
    }

    @Test("#a reading stamped in the future is capped at the ceiling")
    func futureReadingCapped() {
        let reading = now.addingTimeInterval(10 * 60)
        let delay = WatchRefreshPolicy.nextRefreshDelay(lastReadingAt: reading, now: now, hour: noon)
        #expect(delay == WatchRefreshPolicy.daytimeCeiling)
    }

    // MARK: - Deduplication

    @Test("#a strictly newer reading passes")
    func newerReadingPasses() {
        #expect(WatchRefreshPolicy.isNewReading(updatedAt: 1000, lastReloadedAt: 700))
    }

    @Test("#the first reading ever passes")
    func firstReadingPasses() {
        #expect(WatchRefreshPolicy.isNewReading(updatedAt: 1000, lastReloadedAt: 0))
    }

    @Test("#the same reading over a second channel is blocked")
    func duplicateBlocked() {
        #expect(!WatchRefreshPolicy.isNewReading(updatedAt: 1000, lastReloadedAt: 1000))
    }

    @Test("#an older reading is blocked")
    func olderBlocked() {
        #expect(!WatchRefreshPolicy.isNewReading(updatedAt: 700, lastReloadedAt: 1000))
    }

    // MARK: - Complication push budget

    @Test("#push is due after the interval when transfers remain")
    func pushDue() {
        let last = now.addingTimeInterval(-WatchRefreshPolicy.complicationPushInterval)
        #expect(WatchRefreshPolicy.isComplicationPushDue(now: now, lastPush: last, remainingTransfers: 5))
    }

    @Test("#push is not due inside the interval")
    func pushTooSoon() {
        let last = now.addingTimeInterval(-WatchRefreshPolicy.complicationPushInterval + 1)
        #expect(!WatchRefreshPolicy.isComplicationPushDue(now: now, lastPush: last, remainingTransfers: 5))
    }

    @Test("#push is never due once the daily budget is spent")
    func pushBudgetSpent() {
        #expect(!WatchRefreshPolicy.isComplicationPushDue(now: now, lastPush: .distantPast, remainingTransfers: 0))
    }
}
