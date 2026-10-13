// LoopFollow
// WatchPendingBolus.swift

import Foundation

/// A bolus sent from the Watch that the loop may not have accounted for yet.
///
/// The recommended bolus shown on the Watch comes from the last loop run. Until the
/// loop runs again after a Watch bolus, that recommendation still assumes the insulin
/// was not given, so the Watch subtracts it to avoid prompting a second dose.
struct WatchPendingBolus: Codable, Equatable {
    let units: Double
    let sentAt: Date

    /// The loop must have run at least this long after the bolus to have seen it.
    static let loopPickupDelay: TimeInterval = 60
    /// After this long the adjustment is dropped whatever the loop has reported.
    static let maximumAge: TimeInterval = 15 * 60

    /// Whether this bolus is still missing from a recommendation computed at `loopRanAt`.
    func isPending(loopRanAt: Date?, now: Date) -> Bool {
        guard now.timeIntervalSince(sentAt) < Self.maximumAge else { return false }
        guard let loopRanAt else { return true }
        return loopRanAt < sentAt.addingTimeInterval(Self.loopPickupDelay)
    }

    /// The recommendation to display, never below zero.
    static func adjustedRecommendation(_ recommended: Double, pending: WatchPendingBolus?, loopRanAt: Date?, now: Date) -> Double {
        guard let pending, pending.isPending(loopRanAt: loopRanAt, now: now) else {
            return max(0, recommended)
        }
        return max(0, recommended - pending.units)
    }

    // MARK: - Persistence (Watch App Group)

    private static let key = "watch.pendingBolus"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroupID.current())
    }

    static func load() -> WatchPendingBolus? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WatchPendingBolus.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.defaults?.set(data, forKey: Self.key)
    }
}
