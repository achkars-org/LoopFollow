import Foundation

enum LASilentPushGate {

    private static let keyLastSilentPushAt = "la.lastSilentPushReceivedAt"

    // Uses your dynamic App Group ID (preferred).
    // If you don't have AppGroupID.current yet, see the fallback below.
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroupID.current)
    }

    /// Call as soon as a silent push arrives.
    static func markSilentPushReceived(now: Date = Date()) {
        defaults?.set(now.timeIntervalSince1970, forKey: keyLastSilentPushAt)
        defaults?.synchronize()
    }

    /// Returns age in seconds, or nil if we never received a silent push.
    static func secondsSinceLastSilentPush(now: Date = Date()) -> TimeInterval? {
        guard let ts = defaults?.object(forKey: keyLastSilentPushAt) as? Double else { return nil }
        return now.timeIntervalSince1970 - ts
    }

    /// True when a silent push was received within the suppression window.
    static func shouldSuppressPolling(windowSeconds: TimeInterval = 300, now: Date = Date()) -> Bool {
        guard let age = secondsSinceLastSilentPush(now: now) else { return false }
        return age >= 0 && age < windowSeconds
    }

    /// Optional: debugging / manual reset.
    static func clear() {
        defaults?.removeObject(forKey: keyLastSilentPushAt)
    }
}