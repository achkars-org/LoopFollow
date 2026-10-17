// LoopFollow
// WatchNightscoutFetcher.swift

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
    /// Fetches the latest reading and passes it through the deduplication gate.
    /// `completion` is always called exactly once.
    func handleRefreshTask(completion: @escaping () -> Void) {
        WatchNightscoutClient.fetchLatest { result in
            switch result {
            case let .success(snapshot):
                self.process(snapshot, completion: completion)
            case let .failure(failure):
                WatchEventLog.record("ns", Self.message(for: failure))
                os_log("WatchNightscoutFetcher: fetch failed — %{public}@", log: fetchLog, type: .error, Self.message(for: failure))
                completion()
            }
        }
    }

    private func process(_ snapshot: GlucoseSnapshot, completion: @escaping () -> Void) {
        guard ComplicationRefreshCounter.shared.shouldReloadAndRecord(for: snapshot) else {
            WatchEventLog.record("ns", "no newer reading than \(Self.ageText(of: snapshot.updatedAt)) ago", coalescing: true)
            completion()
            return
        }
        WatchEventLog.record("ns", "new reading from \(Self.ageText(of: snapshot.updatedAt)) ago, saving")
        GlucoseSnapshotStore.shared.save(snapshot) {
            ChannelDiagnosticsStore.shared.record(.watchWake)
            WatchSessionReceiver.shared.triggerComplicationReload()
            completion()
        }
    }

    private static func message(for failure: WatchNightscoutClient.Failure) -> String {
        switch failure {
        case .notConfigured: return "skipped: no Nightscout URL on watch"
        case .notHTTPS: return "skipped: URL is not HTTPS"
        case let .network(text): return "fetch failed: \(text)"
        case .empty: return "empty response"
        case .decode: return "decode failed"
        }
    }

    private static func ageText(of date: Date) -> String {
        "\(Int(Date().timeIntervalSince(date) / 60))m"
    }
}
