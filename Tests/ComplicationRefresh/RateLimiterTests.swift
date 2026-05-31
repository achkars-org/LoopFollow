// LoopFollow
// RateLimiterTests.swift
//
// Tests for the phone-side rate-limiter logic introduced in Step 2:
// WatchConnectivityManager.complicationCreditAvailable().
//
// NOTE ON SCOPE:
// WatchConnectivityManager is compiled into the iOS app target but its
// complicationCreditAvailable() method is private and depends on WCSession.
// We test the predicate as a pure Boolean expression — mirroring exactly the
// formula from the spec — without touching WCSession or UserDefaults.
//
// The predicate mirrors:
//   private func complicationCreditAvailable() -> Bool {
//       let now = Date().timeIntervalSince1970
//       let windowStart = now - now.truncatingRemainder(dividingBy: 1800)
//       let last = LAAppGroupSettings.lastComplicationPushWindowStart()
//       return last < windowStart
//   }
//
// A 30-minute window is epoch-aligned: every window starts at a multiple of
// 1800 seconds since the Unix epoch.
//
// Window-boundary constants used in tests:
//   windowA = 1_699_999_200  (1_699_999_200 % 1800 == 0 ✓ — 1_699_999_200 / 1800 = 944444)
//   windowB = 1_700_001_000  (windowA + 1800)

import Testing

// MARK: - Rate-limiter predicate helper

/// Mirrors the complicationCreditAvailable() predicate from WatchConnectivityManager.
///
/// Parameters:
///   - now:              the current time (timeIntervalSince1970)
///   - lastWindowStart:  value of LAAppGroupSettings.lastComplicationPushWindowStart()
///
/// Returns true when credit is available (no push made in this 30-min window).
private func complicationCreditAvailable(
    now: TimeInterval,
    lastWindowStart: TimeInterval
) -> Bool {
    let windowStart = now - now.truncatingRemainder(dividingBy: 1800)
    return lastWindowStart < windowStart
}

// MARK: - Window-boundary constants
// windowA and windowB are exact multiples of 1800:
//   windowA = 944444 * 1800 = 1_699_999_200
//   windowB = windowA + 1800 = 1_700_001_000
private let windowA: TimeInterval = 1_699_999_200
private let windowB: TimeInterval = 1_699_999_200 + 1800   // = 1_700_001_000

// MARK: - Tests

struct RateLimiterTests {
    // -------------------------------------------------------------------------
    // Credit IS available
    // -------------------------------------------------------------------------

    @Test("credit available when no push has ever been made (lastWindowStart = 0)")
    func creditAvailableOnFirstUse() {
        // Any now > 1800 produces windowStart > 0, so lastWindowStart=0 < windowStart.
        let now = windowB + 60   // 60 s into windowB
        #expect(complicationCreditAvailable(now: now, lastWindowStart: 0))
    }

    @Test("credit available when last push was in a previous window")
    func creditAvailableForNewWindow() {
        // We are 60 s into windowB; last push was recorded during windowA.
        let now = windowB + 60
        #expect(complicationCreditAvailable(now: now, lastWindowStart: windowA))
    }

    @Test("credit available when now is exactly at window boundary")
    func creditAvailableAtWindowBoundary() {
        // now is exactly windowB (start of a new window).
        // windowStart computed from now = windowB - 0 = windowB.
        // lastWindowStart = windowA < windowB → credit available.
        #expect(complicationCreditAvailable(now: windowB, lastWindowStart: windowA))
    }

    @Test("credit available when now is 1 second past a window boundary")
    func creditAvailableOneSecondPastBoundary() {
        let now = windowB + 1
        #expect(complicationCreditAvailable(now: now, lastWindowStart: windowA))
    }

    // -------------------------------------------------------------------------
    // Credit is NOT available (same window)
    // -------------------------------------------------------------------------

    @Test("credit unavailable when last push was in the current window")
    func creditUnavailableInSameWindow() {
        // We are 300 s into windowB; last push was also made during windowB.
        let now = windowB + 300
        #expect(!complicationCreditAvailable(now: now, lastWindowStart: windowB))
    }

    @Test("credit unavailable when last push was recorded at exact window start and we are still in that window")
    func creditUnavailableWhenPushedAtWindowStart() {
        // now = windowB + 1799 (last second before next window)
        let now = windowB + 1799
        #expect(!complicationCreditAvailable(now: now, lastWindowStart: windowB))
    }

    @Test("credit unavailable when now is mid-window and last push is same window")
    func creditUnavailableWhenNowIsMidWindow() {
        // now = windowB + 900 (15 min into windowB); last push at windowB.
        let now = windowB + 900
        #expect(!complicationCreditAvailable(now: now, lastWindowStart: windowB))
    }

    // -------------------------------------------------------------------------
    // Window alignment correctness
    // -------------------------------------------------------------------------

    @Test("window start is always a multiple of 1800")
    func windowStartIsMultipleOf1800() {
        let now = windowB + 234
        let computedWindowStart = now - now.truncatingRemainder(dividingBy: 1800)
        #expect(computedWindowStart.truncatingRemainder(dividingBy: 1800) == 0)
    }

    @Test("two timestamps 1799 seconds apart share the same window")
    func twoTimestampsInSameWindowSameWindowStart() {
        let t1 = windowB + 1       // 1 s into windowB
        let t2 = windowB + 1799    // last second of windowB

        let ws1 = t1 - t1.truncatingRemainder(dividingBy: 1800)
        let ws2 = t2 - t2.truncatingRemainder(dividingBy: 1800)
        #expect(ws1 == ws2)
        #expect(ws1 == windowB)
    }

    @Test("two timestamps exactly 1800 seconds apart are in different windows")
    func twoTimestamps1800SecondsApartAreDifferentWindows() {
        let t1 = windowB          // start of windowB
        let t2 = windowB + 1800   // start of windowC (next window)

        let ws1 = t1 - t1.truncatingRemainder(dividingBy: 1800)
        let ws2 = t2 - t2.truncatingRemainder(dividingBy: 1800)
        #expect(ws1 != ws2)
        #expect(ws2 == ws1 + 1800)
    }

    // -------------------------------------------------------------------------
    // Midnight epoch-rollover edge case (UTC-aligned windows)
    // -------------------------------------------------------------------------

    @Test("readings 2 seconds apart straddling a window boundary get separate credits")
    func stradingWindowBoundaryCreatesSeparateCredits() {
        // t1 is 1 s before windowB, t2 is 1 s after windowB
        let t1 = windowB - 1   // still in windowA
        let t2 = windowB + 1   // in windowB

        let ws1 = t1 - t1.truncatingRemainder(dividingBy: 1800)
        let ws2 = t2 - t2.truncatingRemainder(dividingBy: 1800)
        #expect(ws1 != ws2)

        // Credit is available for t2 because it is in a new window
        #expect(complicationCreditAvailable(now: t2, lastWindowStart: ws1))
    }
}
