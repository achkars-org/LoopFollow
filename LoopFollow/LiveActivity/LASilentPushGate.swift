import Foundation

enum LASilentPushGate {

    private static let key = "la.lastSilentPushReceivedAt"
    private static let groupDefaults = UserDefaults(suiteName: AppGroupID.current) // your saved “Group ID” concept

    /// Call this as soon as a silent push arrives (before/around refresh).
    static func markSilentPushReceived(now: Date = Date()) {
        groupDefaults?.set(now.timeIntervalSince1970, forKey: key)
        groupDefaults?.synchronize()
    }

    /// Returns seconds since the most recent silent push, or nil if never.
    static func secondsSinceLastSilentPush(now: Date = Date()) -> TimeInterval? {
        guard let ts = groupDefaults?.object(forKey: key) as? Double else { return nil }
        return now.timeIntervalSince1970 - ts
    }

    /// Polling should be suppressed if APNs is active and we got a silent push recently.
    static func shouldSuppressPolling(apnsActive: Bool, windowSeconds: TimeInterval = 300) -> Bool {
        guard apnsActive else { return false }
        guard let age = secondsSinceLastSilentPush() else { return false }
        return age >= 0 && age < windowSeconds
    }
}