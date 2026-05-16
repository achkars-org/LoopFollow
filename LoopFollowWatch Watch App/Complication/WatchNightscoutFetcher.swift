// LoopFollow
// WatchNightscoutFetcher.swift
// Watch target only.

import CryptoKit
import Foundation
import os.log

private let fetchLog = OSLog(
    subsystem: Bundle.main.bundleIdentifier ?? "com.loopfollow.watch",
    category: "WatchNightscoutFetcher"
)

/// Provides a URLSession-based fallback channel for fetching glucose readings directly
/// from NightScout on the Watch, independent of the WCSession delivery path.
///
/// Fire dates are clock-aligned to [10, 20, 40, 50] minutes past the hour so that they
/// interleave with the WCSession-driven 5-minute BG readings without exact overlap.
///
/// All completion callbacks are invoked exactly once on an internal serial queue.
final class WatchNightscoutFetcher: NSObject {
    static let shared = WatchNightscoutFetcher()

    override private init() {}

    // MARK: - Fetch handling

    /// Called from `WatchAppDelegate.handle` when a `WKURLSessionRefreshBackgroundTask` fires.
    /// Fetches `/api/v1/entries.json?count=1`, decodes the first SGV entry, builds a
    /// glucose-only `GlucoseSnapshot`, and passes it through the deduplication gate.
    /// `completion` is always called exactly once.
    func handleRefreshTask(completion: @escaping () -> Void) {
        let urlString = LAAppGroupSettings.watchNightscoutURL()
        guard !urlString.isEmpty, let baseURL = URL(string: urlString) else {
            os_log(
                "WatchNightscoutFetcher: NightScout URL not configured — skipping fetch",
                log: fetchLog,
                type: .info
            )
            completion()
            return
        }
        guard isHTTPS(urlString) else {
            os_log(
                "WatchNightscoutFetcher: NightScout URL is not HTTPS — skipping fetch",
                log: fetchLog,
                type: .info
            )
            completion()
            return
        }

        let entriesURL = buildEntriesURL(base: baseURL)
        var request = URLRequest(url: entriesURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        applyAuth(to: &request)

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else {
                completion()
                return
            }
            if let error = error {
                os_log(
                    "WatchNightscoutFetcher: fetch failed — %{public}@",
                    log: fetchLog,
                    type: .error,
                    error.localizedDescription
                )
                completion()
                return
            }
            guard let data else {
                os_log("WatchNightscoutFetcher: empty response", log: fetchLog, type: .error)
                completion()
                return
            }
            self.processEntries(data: data, completion: completion)
        }
        task.resume()
    }

    // MARK: - Private helpers

    private func buildEntriesURL(base: URL) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.path = "/api/v1/entries.json"
        components.queryItems = [URLQueryItem(name: "count", value: "1")]
        return components.url ?? base
    }

    /// Adds the NightScout `api-secret` header (SHA-1 hex of the stored token) to a request.
    /// No-ops when no token is configured — supports public NightScout instances.
    private func applyAuth(to request: inout URLRequest) {
        let token = LAAppGroupSettings.watchNightscoutToken()
        guard !token.isEmpty else { return }
        let digest = Insecure.SHA1.hash(data: Data(token.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        request.setValue(hex, forHTTPHeaderField: "api-secret")
    }

    private func isHTTPS(_ urlString: String) -> Bool {
        URL(string: urlString)?.scheme?.lowercased() == "https"
    }

    private func processEntries(data: Data, completion: @escaping () -> Void) {
        do {
            let entries = try JSONDecoder().decode([NightscoutEntry].self, from: data)
            guard let entry = entries.first else {
                os_log("WatchNightscoutFetcher: entries array is empty", log: fetchLog, type: .info)
                completion()
                return
            }

            let updatedAt = Date(timeIntervalSince1970: entry.date / 1000)
            let unit = resolveUnit()
            let snapshot = GlucoseSnapshot(
                glucose: Double(entry.sgv),
                delta: 0,
                trend: trendFromDirection(entry.direction),
                updatedAt: updatedAt,
                iob: nil,
                cob: nil,
                projected: nil,
                unit: unit,
                isNotLooping: false
            )

            guard ComplicationRefreshCounter.shared.shouldReloadAndRecord(for: snapshot) else {
                os_log(
                    "WatchNightscoutFetcher: duplicate entry at %f — skipping save",
                    log: fetchLog,
                    type: .debug,
                    updatedAt.timeIntervalSince1970
                )
                completion()
                return
            }

            os_log(
                "WatchNightscoutFetcher: new entry g=%d at %f, saving",
                log: fetchLog,
                type: .info,
                entry.sgv,
                updatedAt.timeIntervalSince1970
            )
            GlucoseSnapshotStore.shared.save(snapshot) {
                ChannelDiagnosticsStore.shared.record(.watchWake)
                WatchSessionReceiver.shared.triggerComplicationReload()
                completion()
            }
        } catch {
            os_log(
                "WatchNightscoutFetcher: decode failed — %{public}@",
                log: fetchLog,
                type: .error,
                error.localizedDescription
            )
            completion()
        }
    }

    private func resolveUnit() -> GlucoseSnapshot.Unit {
        let stored = GlucoseSnapshotStore.shared.load()
        return stored?.unit ?? .mgdl
    }

    private func trendFromDirection(_ direction: String?) -> GlucoseSnapshot.Trend {
        switch direction {
        case "DoubleUp": return .upFast
        case "SingleUp": return .up
        case "FortyFiveUp": return .upSlight
        case "Flat": return .flat
        case "FortyFiveDown": return .downSlight
        case "SingleDown": return .down
        case "DoubleDown": return .downFast
        default: return .unknown
        }
    }
}

// MARK: - NightScout entries.json response model

private struct NightscoutEntry: Decodable {
    /// Glucose value in mg/dL.
    let sgv: Int
    /// Timestamp in milliseconds since epoch.
    let date: TimeInterval
    /// Trend direction string (e.g. "Flat", "SingleUp"). Optional — not always present.
    let direction: String?

    enum CodingKeys: String, CodingKey {
        case sgv
        case date
        case direction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // sgv may arrive as Int or Double in some NightScout versions
        if let intValue = try? container.decode(Int.self, forKey: .sgv) {
            sgv = intValue
        } else {
            sgv = try Int(container.decode(Double.self, forKey: .sgv).rounded())
        }
        date = try container.decode(TimeInterval.self, forKey: .date)
        direction = try container.decodeIfPresent(String.self, forKey: .direction)
    }
}
