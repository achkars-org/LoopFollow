// LoopFollow
// URLSessionFireDateTests.swift

//
// Tests for the pure date-arithmetic logic in
// WatchNightscoutFetcher.nextURLSessionFireDate().
//
// NOTE ON SCOPE:
// WatchNightscoutFetcher is compiled into the Watch target only.
// The "Tests" target uses @testable import LoopFollow (the iOS app target), so
// WatchNightscoutFetcher is NOT accessible here. Instead we test the next-slot
// predicate as a pure function — mirroring exactly the logic that lives inside
// nextURLSessionFireDate() — without calling any Watch or System API.
//
// The fire-slot schedule per the spec is [10, 20, 40, 50] minutes past the hour.
// nextURLSessionFireDate() returns the next slot strictly after `now`.
//
// Example — if it is 08:15 the next slot is :20 (5 min away).
//           if it is 08:20 the next slot is :40 (20 min away).
//           if it is 08:45 the next slot is :50 (5 min away).
//           if it is 08:55 the next slot is :10 of 09:xx (15 min away).

import Foundation
import Testing

// MARK: - Fire-date predicate helper

/// The four minute-offsets (seconds past the start of the hour) at which the
/// NightScout background URLSession should fire.
private let fireSlots: [TimeInterval] = [10 * 60, 20 * 60, 40 * 60, 50 * 60]

/// Mirrors WatchNightscoutFetcher.nextURLSessionFireDate().
///
/// Given `now` (as seconds past the Unix epoch), returns the Date of the next
/// clock-aligned fire slot strictly after `now`.
private func nextFireDate(now: TimeInterval) -> Date {
    let secondsPerHour: TimeInterval = 3600
    let secondsIntoHour = now.truncatingRemainder(dividingBy: secondsPerHour)
    let hourStart = now - secondsIntoHour

    // Find the first slot whose minute-offset is strictly after secondsIntoHour
    for slot in fireSlots where slot > secondsIntoHour {
        return Date(timeIntervalSince1970: hourStart + slot)
    }

    // All slots in this hour have passed — wrap to the first slot of the next hour
    return Date(timeIntervalSince1970: hourStart + secondsPerHour + fireSlots[0])
}

// MARK: - Tests

struct URLSessionFireDateTests {
    // -----------------------------------------------------------------------
    // Slots [10, 20, 40, 50] minutes past the hour — 4 distinct slots
    // -----------------------------------------------------------------------

    // All assertions compare Date.timeIntervalSince1970 directly against the
    // expected absolute epoch offset, keeping tests timezone-independent.

    // -----------------------------------------------------------------------
    // Slot 1: :10 — now is before the :10 slot
    // -----------------------------------------------------------------------

    @Test("next slot is :10 when now is at the top of the hour (:00)")
    func nextSlotIsAt10WhenAtHourStart() {
        // hourBoundary = 1_699_992_000 is exactly divisible by 3600 (= 472220 * 3600)
        let hourBoundary: TimeInterval = 1_699_992_000
        let result = nextFireDate(now: hourBoundary)
        #expect(result.timeIntervalSince1970 == hourBoundary + 10 * 60)
    }

    @Test("next slot is :10 when now is 5 minutes into the hour (:05)")
    func nextSlotIsAt10WhenAt05() {
        let hourBoundary: TimeInterval = 1_699_992_000 // round hour (verify: 1_699_992_000 % 3600 == 0)
        let now = hourBoundary + 5 * 60
        let result = nextFireDate(now: now)
        #expect(result.timeIntervalSince1970 == hourBoundary + 10 * 60)
    }

    // -----------------------------------------------------------------------
    // Slot 2: :20 — now is between :10 and :20
    // -----------------------------------------------------------------------

    @Test("next slot is :20 when now is exactly at the :10 slot")
    func nextSlotIsAt20WhenExactlyAt10() {
        let hourBoundary: TimeInterval = 1_699_992_000
        let now = hourBoundary + 10 * 60 // exactly at :10 slot
        let result = nextFireDate(now: now)
        // :10 is NOT strictly after itself → next is :20
        #expect(result.timeIntervalSince1970 == hourBoundary + 20 * 60)
    }

    @Test("next slot is :20 when now is :15")
    func nextSlotIsAt20WhenAt15() {
        let hourBoundary: TimeInterval = 1_699_992_000
        let now = hourBoundary + 15 * 60
        let result = nextFireDate(now: now)
        #expect(result.timeIntervalSince1970 == hourBoundary + 20 * 60)
    }

    // -----------------------------------------------------------------------
    // Slot 3: :40 — now is between :20 and :40
    // -----------------------------------------------------------------------

    @Test("next slot is :40 when now is exactly at the :20 slot")
    func nextSlotIsAt40WhenExactlyAt20() {
        let hourBoundary: TimeInterval = 1_699_992_000
        let now = hourBoundary + 20 * 60
        let result = nextFireDate(now: now)
        #expect(result.timeIntervalSince1970 == hourBoundary + 40 * 60)
    }

    @Test("next slot is :40 when now is :30")
    func nextSlotIsAt40WhenAt30() {
        let hourBoundary: TimeInterval = 1_699_992_000
        let now = hourBoundary + 30 * 60
        let result = nextFireDate(now: now)
        #expect(result.timeIntervalSince1970 == hourBoundary + 40 * 60)
    }

    // -----------------------------------------------------------------------
    // Slot 4: :50 — now is between :40 and :50
    // -----------------------------------------------------------------------

    @Test("next slot is :50 when now is exactly at the :40 slot")
    func nextSlotIsAt50WhenExactlyAt40() {
        let hourBoundary: TimeInterval = 1_699_992_000
        let now = hourBoundary + 40 * 60
        let result = nextFireDate(now: now)
        #expect(result.timeIntervalSince1970 == hourBoundary + 50 * 60)
    }

    @Test("next slot is :50 when now is :45")
    func nextSlotIsAt50WhenAt45() {
        let hourBoundary: TimeInterval = 1_699_992_000
        let now = hourBoundary + 45 * 60
        let result = nextFireDate(now: now)
        #expect(result.timeIntervalSince1970 == hourBoundary + 50 * 60)
    }

    // -----------------------------------------------------------------------
    // Hour wrap — now is past :50, wraps to next hour's :10
    // -----------------------------------------------------------------------

    @Test("wraps to next hour :10 when now is exactly at the :50 slot")
    func wrapsToNextHour10WhenExactlyAt50() {
        let hourBoundary: TimeInterval = 1_699_992_000
        let now = hourBoundary + 50 * 60
        let result = nextFireDate(now: now)
        #expect(result.timeIntervalSince1970 == hourBoundary + 3600 + 10 * 60)
    }

    @Test("wraps to next hour :10 when now is :55")
    func wrapsToNextHour10WhenAt55() {
        let hourBoundary: TimeInterval = 1_699_992_000
        let now = hourBoundary + 55 * 60
        let result = nextFireDate(now: now)
        #expect(result.timeIntervalSince1970 == hourBoundary + 3600 + 10 * 60)
    }

    @Test("wraps to next hour :10 when now is :59:59")
    func wrapsToNextHour10WhenAt5959() {
        let hourBoundary: TimeInterval = 1_699_992_000
        let now = hourBoundary + 59 * 60 + 59
        let result = nextFireDate(now: now)
        #expect(result.timeIntervalSince1970 == hourBoundary + 3600 + 10 * 60)
    }

    // -----------------------------------------------------------------------
    // Result is always strictly in the future relative to now
    // -----------------------------------------------------------------------

    @Test("fire date is always strictly after now for all slots")
    func fireDateIsAlwaysInFuture() {
        // Test a sample of `now` values spread across an hour
        let hourBoundary: TimeInterval = 1_699_992_000
        let samples: [TimeInterval] = [
            0, 1, 5 * 60, 9 * 60 + 59, 10 * 60, 15 * 60, 19 * 60 + 59, 20 * 60,
            30 * 60, 39 * 60 + 59, 40 * 60, 45 * 60, 49 * 60 + 59, 50 * 60,
            55 * 60, 59 * 60 + 59,
        ].map { hourBoundary + $0 }
        for now in samples {
            let fire = nextFireDate(now: now)
            #expect(fire.timeIntervalSince1970 > now,
                    "Expected fire date to be after now=\(now), got \(fire.timeIntervalSince1970)")
        }
    }

    // -----------------------------------------------------------------------
    // Correct slot alignment verification (verify the test helper itself)
    // -----------------------------------------------------------------------

    @Test("fire-slot offsets are [10, 20, 40, 50] minutes in seconds")
    func fireSlotsAreCorrect() {
        #expect(fireSlots == [600, 1200, 2400, 3000])
    }
}
