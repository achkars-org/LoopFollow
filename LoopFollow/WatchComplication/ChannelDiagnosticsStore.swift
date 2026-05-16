// LoopFollow
// ChannelDiagnosticsStore.swift
// Watch target only.

import Foundation

final class ChannelDiagnosticsStore {
    static let shared = ChannelDiagnosticsStore()
    private init() {}

    enum Channel: String, CaseIterable {
        case phonePush = "phonepush"
        case watchWake = "watchwake"

        var displayName: String {
            switch self {
            case .phonePush: return "Phone Push"
            case .watchWake: return "Watch Wake"
            }
        }
    }

    struct ChannelStats {
        let channel: Channel
        let lastFired: Date?
        let hourCount: Int
        let dayCount: Int
    }

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroupID.current())
    }

    func record(_ channel: Channel) {
        let now = Date().timeIntervalSince1970
        let currentHourBucket = Int(now / 3600)
        let currentDayBucket = Int(now / 86400)
        let prefix = "watch.diag.\(channel.rawValue)"

        let storedHourBucket = defaults?.integer(forKey: "\(prefix).hourBucket") ?? 0
        let storedDayBucket = defaults?.integer(forKey: "\(prefix).dayBucket") ?? 0

        let hourCount = (storedHourBucket == currentHourBucket
            ? (defaults?.integer(forKey: "\(prefix).hourCount") ?? 0) : 0) + 1
        let dayCount = (storedDayBucket == currentDayBucket
            ? (defaults?.integer(forKey: "\(prefix).dayCount") ?? 0) : 0) + 1

        defaults?.set(now, forKey: "\(prefix).lastFired")
        defaults?.set(hourCount, forKey: "\(prefix).hourCount")
        defaults?.set(currentHourBucket, forKey: "\(prefix).hourBucket")
        defaults?.set(dayCount, forKey: "\(prefix).dayCount")
        defaults?.set(currentDayBucket, forKey: "\(prefix).dayBucket")
    }

    func stats(for channel: Channel) -> ChannelStats {
        let now = Date().timeIntervalSince1970
        let currentHourBucket = Int(now / 3600)
        let currentDayBucket = Int(now / 86400)
        let prefix = "watch.diag.\(channel.rawValue)"

        let lastFiredEpoch = defaults?.double(forKey: "\(prefix).lastFired") ?? 0
        let storedHourBucket = defaults?.integer(forKey: "\(prefix).hourBucket") ?? 0
        let storedDayBucket = defaults?.integer(forKey: "\(prefix).dayBucket") ?? 0

        return ChannelStats(
            channel: channel,
            lastFired: lastFiredEpoch > 0 ? Date(timeIntervalSince1970: lastFiredEpoch) : nil,
            hourCount: storedHourBucket == currentHourBucket
                ? (defaults?.integer(forKey: "\(prefix).hourCount") ?? 0) : 0,
            dayCount: storedDayBucket == currentDayBucket
                ? (defaults?.integer(forKey: "\(prefix).dayCount") ?? 0) : 0
        )
    }

    func allStats() -> [ChannelStats] {
        Channel.allCases.map { stats(for: $0) }
    }

    func reset() {
        for channel in Channel.allCases {
            let prefix = "watch.diag.\(channel.rawValue)"
            for suffix in ["lastFired", "hourCount", "hourBucket", "dayCount", "dayBucket"] {
                defaults?.removeObject(forKey: "\(prefix).\(suffix)")
            }
        }
    }
}
