// LoopFollow
// WatchGlucoseHistory.swift

import Foundation
import os.log

private let historyLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.loopfollow", category: "WatchGlucoseHistory")

/// Recent BG readings sent to the Watch for its graph and complication sparkline.
///
/// Kept separate from `GlucoseSnapshot` because the snapshot also rides in Live
/// Activity push payloads, which have a small size limit.
struct WatchGlucoseHistory: Codable, Equatable {
    /// WatchConnectivity payload key.
    static let payloadKey = "history"
    /// How much history the phone sends.
    static let window: TimeInterval = 3 * 60 * 60

    struct Point: Codable, Equatable {
        /// Reading time, Unix epoch seconds.
        let date: TimeInterval
        /// Glucose in mg/dL.
        let mgdl: Int

        private enum CodingKeys: String, CodingKey {
            case date = "t"
            case mgdl = "g"
        }
    }

    /// Readings inside the window, oldest first, one per timestamp.
    let points: [Point]

    /// Builds a history from raw readings, keeping only those inside `window` before `now`.
    static func make(from readings: [Point], now: Date) -> WatchGlucoseHistory {
        let cutoff = now.timeIntervalSince1970 - window
        var seen = Set<TimeInterval>()
        let points = readings
            .filter { $0.date >= cutoff && $0.date <= now.timeIntervalSince1970 + 60 && $0.mgdl > 0 }
            .sorted { $0.date < $1.date }
            .filter { seen.insert($0.date).inserted }
        return WatchGlucoseHistory(points: points)
    }

    /// Adds a reading (e.g. from the Watch's own Nightscout fallback) and re-trims the window.
    func appending(_ point: Point, now: Date) -> WatchGlucoseHistory {
        Self.make(from: points + [point], now: now)
    }

    /// Points whose reading time falls inside the trailing `duration` before `now`.
    func points(within duration: TimeInterval, of now: Date) -> [Point] {
        let cutoff = now.timeIntervalSince1970 - duration
        return points.filter { $0.date >= cutoff }
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decoded(from data: Data) throws -> WatchGlucoseHistory {
        try JSONDecoder().decode(WatchGlucoseHistory.self, from: data)
    }

    // MARK: - App Group persistence

    private static let fileName = "watch_glucose_history.json"

    private static func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroupID.current())?
            .appendingPathComponent(fileName, isDirectory: false)
    }

    /// Writes the history atomically so the widget extension never reads a partial file.
    func save() {
        guard let url = Self.fileURL() else { return }
        do {
            try encoded().write(to: url, options: [.atomic])
        } catch {
            os_log("WatchGlucoseHistory: save failed — %{public}@", log: historyLog, type: .error, error.localizedDescription)
        }
    }

    static func load() -> WatchGlucoseHistory? {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? decoded(from: data)
    }
}
