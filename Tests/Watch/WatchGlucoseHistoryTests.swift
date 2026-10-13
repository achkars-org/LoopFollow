// LoopFollow
// WatchGlucoseHistoryTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct WatchGlucoseHistoryTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func point(minutesAgo: Double, mgdl: Int) -> WatchGlucoseHistory.Point {
        .init(date: now.timeIntervalSince1970 - minutesAgo * 60, mgdl: mgdl)
    }

    @Test("#keeps only readings inside the window, oldest first")
    func trimsAndSorts() {
        let history = WatchGlucoseHistory.make(
            from: [point(minutesAgo: 5, mgdl: 110), point(minutesAgo: 200, mgdl: 90), point(minutesAgo: 10, mgdl: 105)],
            now: now
        )
        #expect(history.points.map(\.mgdl) == [105, 110])
    }

    @Test("#drops duplicate timestamps and invalid values")
    func dropsDuplicatesAndZeros() {
        let history = WatchGlucoseHistory.make(
            from: [point(minutesAgo: 5, mgdl: 110), point(minutesAgo: 5, mgdl: 110), point(minutesAgo: 15, mgdl: 0)],
            now: now
        )
        #expect(history.points.count == 1)
    }

    @Test("#appending a reading keeps the window ordered")
    func appending() {
        let history = WatchGlucoseHistory.make(from: [point(minutesAgo: 10, mgdl: 100)], now: now)
            .appending(point(minutesAgo: 5, mgdl: 104), now: now)
        #expect(history.points.map(\.mgdl) == [100, 104])
    }

    @Test("#points(within:) returns the trailing slice")
    func trailingSlice() {
        let history = WatchGlucoseHistory.make(
            from: [point(minutesAgo: 90, mgdl: 100), point(minutesAgo: 30, mgdl: 120)],
            now: now
        )
        #expect(history.points(within: 60 * 60, of: now).map(\.mgdl) == [120])
    }

    @Test("#encoding round-trips with compact keys")
    func encodingRoundTrip() throws {
        let history = WatchGlucoseHistory.make(from: [point(minutesAgo: 5, mgdl: 110)], now: now)
        let data = try history.encoded()
        #expect(String(decoding: data, as: UTF8.self).contains("\"g\":110"))
        #expect(try WatchGlucoseHistory.decoded(from: data) == history)
    }
}
