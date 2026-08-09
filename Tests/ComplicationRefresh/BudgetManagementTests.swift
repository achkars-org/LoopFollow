// LoopFollow
// BudgetManagementTests.swift

//
// Tests for the deduplication gate, rate limiter, URLSession fire-date
// calculation, and overnight scheduling helper introduced in Steps 1–5.
//
// NOTE ON SCOPE:
// ComplicationRefreshCounter, WatchNightscoutFetcher, and WatchAppDelegate
// are Watch-target types. The "Tests" target uses @testable import LoopFollow
// (the iOS app target), so those types are not directly accessible here.
// Pure helper logic is mirrored as local functions — the same pattern used
// in StalenessGuardTests.swift.

import Testing

// MARK: - Step 1: Deduplication gate predicate

/// Mirrors ComplicationRefreshCounter.shouldReloadAndRecord logic:
/// returns true only when the incoming timestamp is strictly greater than
/// the last recorded value.
private func shouldReload(incoming: TimeInterval, lastRecorded: TimeInterval) -> Bool {
    incoming > lastRecorded
}

struct DeduplicationGateTests {
    @Test("passes when incoming timestamp is newer than last recorded")
    func passesForNewTimestamp() {
        #expect(shouldReload(incoming: 1000, lastRecorded: 999))
    }

    @Test("passes when no reload has ever been recorded (lastRecorded = 0)")
    func passesWhenNeverRecorded() {
        #expect(shouldReload(incoming: 1, lastRecorded: 0))
    }

    @Test("blocks when incoming timestamp equals last recorded")
    func blocksOnDuplicate() {
        #expect(!shouldReload(incoming: 1000, lastRecorded: 1000))
    }

    @Test("blocks when incoming timestamp is older than last recorded")
    func blocksOnStaleDelivery() {
        #expect(!shouldReload(incoming: 999, lastRecorded: 1000))
    }

    @Test("second delivery of the same reading is always blocked")
    func secondDeliveryBlocked() {
        var lastRecorded: TimeInterval = 0
        let timestamp: TimeInterval = 1_700_000_000

        // First delivery — passes, update state
        #expect(shouldReload(incoming: timestamp, lastRecorded: lastRecorded))
        lastRecorded = timestamp

        // Second delivery (same timestamp, e.g. transferUserInfo racing transferCurrentComplicationUserInfo)
        #expect(!shouldReload(incoming: timestamp, lastRecorded: lastRecorded))
    }

    @Test("new reading after a duplicate is allowed through")
    func newReadingAfterDuplicatePasses() {
        var lastRecorded: TimeInterval = 1_700_000_000

        // Duplicate blocked
        #expect(!shouldReload(incoming: lastRecorded, lastRecorded: lastRecorded))

        // New 5-minute reading passes
        let next = lastRecorded + 300
        #expect(shouldReload(incoming: next, lastRecorded: lastRecorded))
        lastRecorded = next
        _ = lastRecorded // suppress unused-variable warning
    }
}

// MARK: - Step 2: Rate limiter predicate

/// Mirrors WatchConnectivityManager.complicationCreditAvailable():
/// a credit is available when lastWindowStart is before the current 30-minute window.
private func creditAvailable(now: TimeInterval, lastWindowStart: TimeInterval) -> Bool {
    let currentWindowStart = now - now.truncatingRemainder(dividingBy: 1800)
    return lastWindowStart < currentWindowStart
}

struct RateLimiterTests {
    @Test("credit available when no push has ever been sent (lastWindowStart = 0)")
    func availableWhenNeverSent() {
        let now: TimeInterval = 1_700_000_900 // 15 min into a window
        #expect(creditAvailable(now: now, lastWindowStart: 0))
    }

    @Test("credit available when last push was in a previous 30-minute window")
    func availableInNewWindow() {
        let now: TimeInterval = 1_700_003_600 // one hour after epoch anchor
        let lastWindow: TimeInterval = 1_700_001_800 // previous window start
        #expect(creditAvailable(now: now, lastWindowStart: lastWindow))
    }

    @Test("credit unavailable when last push was in the current window")
    func unavailableInSameWindow() {
        let now: TimeInterval = 1_700_000_900 // 15 min past window boundary
        let windowStart = now - now.truncatingRemainder(dividingBy: 1800) // same window
        #expect(!creditAvailable(now: now, lastWindowStart: windowStart))
    }

    @Test("credit becomes available at the next window boundary")
    func availableAtNextBoundary() {
        let windowStart: TimeInterval = 1_700_000_000
        let inWindow = windowStart + 60 // 1 min after boundary
        let nextWindow = windowStart + 1800 // exactly at next boundary

        // Same window — blocked
        #expect(!creditAvailable(now: inWindow, lastWindowStart: windowStart))

        // Next window — available
        #expect(creditAvailable(now: nextWindow, lastWindowStart: windowStart))
    }

    @Test("credit unavailable at the exact window boundary when already sent")
    func unavailableAtExactBoundaryIfAlreadySent() {
        let now: TimeInterval = 1_700_001_800 // exactly on a window boundary
        let windowStart = now - now.truncatingRemainder(dividingBy: 1800)
        #expect(!creditAvailable(now: now, lastWindowStart: windowStart))
    }
}

// MARK: - Step 4: URLSession fire-date calculation

/// Mirrors WatchNightscoutFetcher.nextURLSessionFireDate():
/// returns the next minute from [10, 20, 40, 50] that is strictly after
/// the current minute-of-the-hour, wrapping to the next hour if needed.
private func nextFireMinute(currentMinute: Int) -> Int {
    let slots = [10, 20, 40, 50]
    if let next = slots.first(where: { $0 > currentMinute }) {
        return next
    }
    return slots[0] // wraps to next hour
}

struct URLSessionFireDateTests {
    @Test("returns :10 when current minute is before 10")
    func returnsSlot10Before10() {
        #expect(nextFireMinute(currentMinute: 0) == 10)
        #expect(nextFireMinute(currentMinute: 5) == 10)
        #expect(nextFireMinute(currentMinute: 9) == 10)
    }

    @Test("returns :20 when current minute is between 10 and 19 inclusive")
    func returnsSlot20Between10And19() {
        #expect(nextFireMinute(currentMinute: 10) == 20)
        #expect(nextFireMinute(currentMinute: 15) == 20)
        #expect(nextFireMinute(currentMinute: 19) == 20)
    }

    @Test("returns :40 when current minute is between 20 and 39 inclusive")
    func returnsSlot40Between20And39() {
        #expect(nextFireMinute(currentMinute: 20) == 40)
        #expect(nextFireMinute(currentMinute: 30) == 40)
        #expect(nextFireMinute(currentMinute: 39) == 40)
    }

    @Test("returns :50 when current minute is between 40 and 49 inclusive")
    func returnsSlot50Between40And49() {
        #expect(nextFireMinute(currentMinute: 40) == 50)
        #expect(nextFireMinute(currentMinute: 45) == 50)
        #expect(nextFireMinute(currentMinute: 49) == 50)
    }

    @Test("wraps to :10 of next hour when current minute is 50 or later")
    func wrapsToNextHourAt50() {
        #expect(nextFireMinute(currentMinute: 50) == 10)
        #expect(nextFireMinute(currentMinute: 55) == 10)
        #expect(nextFireMinute(currentMinute: 59) == 10)
    }

    @Test("slot :00 and :30 (WCSession slots) are never returned")
    func wcSessionSlotsNeverReturned() {
        let wcSlots = [0, 30]
        for minute in 0 ..< 60 {
            #expect(!wcSlots.contains(nextFireMinute(currentMinute: minute)))
        }
    }
}

// MARK: - Step 5: Overnight scheduling helper

/// Mirrors WatchAppDelegate.isOvernightHour():
/// returns true for hours 0–6 (midnight to 6:59 AM local), false from 7 AM onward.
private func isOvernightHour(_ hour: Int) -> Bool {
    hour < 7
}

struct OvernightHourTests {
    @Test("midnight (hour 0) is overnight")
    func midnightIsOvernight() {
        #expect(isOvernightHour(0))
    }

    @Test("6 AM is overnight (last overnight hour)")
    func sixAMIsOvernight() {
        #expect(isOvernightHour(6))
    }

    @Test("7 AM is not overnight (first active hour)")
    func sevenAMIsNotOvernight() {
        #expect(!isOvernightHour(7))
    }

    @Test("noon is not overnight")
    func noonIsNotOvernight() {
        #expect(!isOvernightHour(12))
    }

    @Test("11 PM is not overnight")
    func elevenPMIsNotOvernight() {
        #expect(!isOvernightHour(23))
    }

    @Test("all hours 0–6 are overnight")
    func allOvernightHours() {
        for hour in 0 ... 6 {
            #expect(isOvernightHour(hour), "hour \(hour) should be overnight")
        }
    }

    @Test("all hours 7–23 are not overnight")
    func allActiveHours() {
        for hour in 7 ... 23 {
            #expect(!isOvernightHour(hour), "hour \(hour) should not be overnight")
        }
    }
}
