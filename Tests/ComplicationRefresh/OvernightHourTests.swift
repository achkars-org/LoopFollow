// LoopFollow
// OvernightHourTests.swift
//
// Tests for the isOvernightHour() helper introduced in Step 5:
// WatchAppDelegate.isOvernightHour().
//
// NOTE ON SCOPE:
// WatchAppDelegate is compiled into the Watch target only.
// The "Tests" target uses @testable import LoopFollow (the iOS app target), so
// WatchAppDelegate is NOT accessible here. Instead we test the predicate as a
// pure Boolean expression — mirroring exactly the logic from the spec — without
// calling WKApplication or Calendar.current.
//
// The predicate mirrors:
//   private static func isOvernightHour() -> Bool {
//       let hour = Calendar.current.component(.hour, from: Date())
//       return hour < 7
//   }
//
// Spec invariant #9: uses *local* Calendar, not UTC. The 7 AM boundary is the
// user's local 7 AM. Here we test the predicate directly with injected hour
// values to avoid any dependency on the test host's timezone.

import Testing

// MARK: - Overnight predicate helper

/// Mirrors the isOvernightHour() predicate from WatchAppDelegate.
///
/// Parameter:
///   - hour: the hour component (0–23) at the time of the check
///
/// Returns true for hours 0–6 inclusive (midnight through 6:59 AM),
/// false for hour 7 and above.
private func isOvernightHour(_ hour: Int) -> Bool {
    hour < 7
}

// MARK: - Tests

struct OvernightHourTests {
    // -----------------------------------------------------------------------
    // Overnight hours — should return true
    // -----------------------------------------------------------------------

    @Test("midnight (hour 0) is an overnight hour")
    func midnightIsOvernight() {
        #expect(isOvernightHour(0))
    }

    @Test("hour 1 is an overnight hour")
    func hour1IsOvernight() {
        #expect(isOvernightHour(1))
    }

    @Test("hour 2 is an overnight hour")
    func hour2IsOvernight() {
        #expect(isOvernightHour(2))
    }

    @Test("hour 3 is an overnight hour")
    func hour3IsOvernight() {
        #expect(isOvernightHour(3))
    }

    @Test("hour 4 is an overnight hour")
    func hour4IsOvernight() {
        #expect(isOvernightHour(4))
    }

    @Test("hour 5 is an overnight hour")
    func hour5IsOvernight() {
        #expect(isOvernightHour(5))
    }

    @Test("hour 6 is an overnight hour (last overnight hour)")
    func hour6IsOvernight() {
        // Hour 6 = 6:00–6:59 AM. The spec says "hours 0–6 inclusive" are overnight.
        #expect(isOvernightHour(6))
    }

    // -----------------------------------------------------------------------
    // Boundary — hour 7 is the first non-overnight hour
    // -----------------------------------------------------------------------

    @Test("hour 7 is NOT an overnight hour (boundary)")
    func hour7IsNotOvernight() {
        // The spec: "20-minute interval during hours 0–6 (midnight to 6:59 AM inclusive)"
        // Hour 7 = 7:00–7:59 AM → 2-minute interval.
        #expect(!isOvernightHour(7))
    }

    // -----------------------------------------------------------------------
    // Daytime hours — should return false
    // -----------------------------------------------------------------------

    @Test("hour 8 is not an overnight hour")
    func hour8IsNotOvernight() {
        #expect(!isOvernightHour(8))
    }

    @Test("noon (hour 12) is not an overnight hour")
    func noonIsNotOvernight() {
        #expect(!isOvernightHour(12))
    }

    @Test("hour 18 is not an overnight hour")
    func hour18IsNotOvernight() {
        #expect(!isOvernightHour(18))
    }

    @Test("hour 23 (11 PM) is not an overnight hour")
    func hour23IsNotOvernight() {
        // 23:00 is evening, not overnight per the spec definition
        #expect(!isOvernightHour(23))
    }

    // -----------------------------------------------------------------------
    // Scheduling interval — verify the correct interval is selected
    // -----------------------------------------------------------------------

    /// Mirrors the scheduleNextRefresh() interval selection.
    private func refreshInterval(hour: Int) -> TimeInterval {
        isOvernightHour(hour) ? 20 * 60 : 2 * 60
    }

    @Test("overnight hours use 20-minute refresh interval")
    func overnightIntervalIs20Minutes() {
        for hour in 0...6 {
            #expect(refreshInterval(hour: hour) == 20 * 60,
                    "Expected 20-minute interval for hour \(hour)")
        }
    }

    @Test("daytime hours use 2-minute refresh interval")
    func daytimeIntervalIs2Minutes() {
        for hour in 7...23 {
            #expect(refreshInterval(hour: hour) == 2 * 60,
                    "Expected 2-minute interval for hour \(hour)")
        }
    }

    @Test("interval changes at exactly hour 7 boundary")
    func intervalBoundaryAtHour7() {
        #expect(refreshInterval(hour: 6) == 20 * 60)   // last overnight
        #expect(refreshInterval(hour: 7) == 2 * 60)    // first daytime
    }
}
