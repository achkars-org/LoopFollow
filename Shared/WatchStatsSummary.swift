// LoopFollow
// WatchStatsSummary.swift

import Foundation

/// A small statistics summary computed on the iPhone and shown on the Watch, so the
/// Watch never needs a full day of readings.
struct WatchStatsSummary: Codable, Equatable {
    /// WatchConnectivity payload key.
    static let payloadKey = "stats"
    /// Period the summary covers.
    static let window: TimeInterval = 24 * 60 * 60

    let readingCount: Int
    let averageMgdl: Double
    let standardDeviationMgdl: Double
    /// Glucose management indicator, %.
    let gmiPercent: Double
    let lowPercent: Double
    let inRangePercent: Double
    let highPercent: Double
    /// Range used for the percentages, mg/dL.
    let lowMgdl: Double
    let highMgdl: Double

    /// Summarises readings from the trailing 24 hours; nil when there are none.
    /// In range is inclusive of both lines, matching how the lines are drawn.
    static func make(from points: [WatchGlucoseHistory.Point], lowMgdl: Double, highMgdl: Double, now: Date) -> WatchStatsSummary? {
        let cutoff = now.timeIntervalSince1970 - window
        let values = points.filter { $0.date >= cutoff && $0.mgdl > 0 }.map { Double($0.mgdl) }
        guard !values.isEmpty else { return nil }

        let count = Double(values.count)
        let average = values.reduce(0, +) / count
        let variance = values.reduce(0) { $0 + ($1 - average) * ($1 - average) } / count
        let low = Double(values.filter { $0 < lowMgdl }.count) / count * 100
        let high = Double(values.filter { $0 > highMgdl }.count) / count * 100

        return WatchStatsSummary(
            readingCount: values.count,
            averageMgdl: average,
            standardDeviationMgdl: variance.squareRoot(),
            gmiPercent: 3.31 + 0.02392 * average,
            lowPercent: low,
            inRangePercent: 100 - low - high,
            highPercent: high,
            lowMgdl: lowMgdl,
            highMgdl: highMgdl
        )
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decoded(from data: Data) throws -> WatchStatsSummary {
        try JSONDecoder().decode(WatchStatsSummary.self, from: data)
    }

    // MARK: - Persistence (Watch App Group)

    private static let key = "watch.statsSummary"

    func save() {
        guard let data = try? encoded() else { return }
        UserDefaults(suiteName: AppGroupID.current())?.set(data, forKey: Self.key)
    }

    static func load() -> WatchStatsSummary? {
        guard let data = UserDefaults(suiteName: AppGroupID.current())?.data(forKey: key) else { return nil }
        return try? decoded(from: data)
    }
}
