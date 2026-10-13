// LoopFollow
// WatchStatsSummaryTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct WatchStatsSummaryTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func points(_ values: [Int], minutesApart: Double = 5) -> [WatchGlucoseHistory.Point] {
        values.enumerated().map { index, mgdl in
            .init(date: now.timeIntervalSince1970 - Double(index) * minutesApart * 60, mgdl: mgdl)
        }
    }

    @Test("#no readings gives no summary")
    func empty() {
        #expect(WatchStatsSummary.make(from: [], lowMgdl: 70, highMgdl: 180, now: now) == nil)
    }

    @Test("#splits readings into low, in range and high")
    func rangeSplit() throws {
        let summary = try #require(WatchStatsSummary.make(from: points([60, 100, 150, 200]), lowMgdl: 70, highMgdl: 180, now: now))
        #expect(summary.lowPercent == 25)
        #expect(summary.inRangePercent == 50)
        #expect(summary.highPercent == 25)
        #expect(summary.readingCount == 4)
    }

    @Test("#readings on a line count as in range")
    func linesAreInRange() throws {
        let summary = try #require(WatchStatsSummary.make(from: points([70, 180]), lowMgdl: 70, highMgdl: 180, now: now))
        #expect(summary.inRangePercent == 100)
    }

    @Test("#average, standard deviation and GMI")
    func averageAndSpread() throws {
        let summary = try #require(WatchStatsSummary.make(from: points([100, 200]), lowMgdl: 70, highMgdl: 180, now: now))
        #expect(summary.averageMgdl == 150)
        #expect(summary.standardDeviationMgdl == 50)
        #expect(abs(summary.gmiPercent - (3.31 + 0.02392 * 150)) < 0.0001)
    }

    @Test("#ignores readings older than 24 hours")
    func window() throws {
        let summary = try #require(WatchStatsSummary.make(from: points([100, 300], minutesApart: 25 * 60), lowMgdl: 70, highMgdl: 180, now: now))
        #expect(summary.readingCount == 1)
        #expect(summary.averageMgdl == 100)
    }
}
