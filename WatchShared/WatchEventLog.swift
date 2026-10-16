// LoopFollow
// WatchEventLog.swift

import Foundation

/// A short rolling log of what the complication pipeline did, kept in the App Group so the
/// Watch app and the widget extension both write to it and the Debug screen can read it
/// after the complication has gone stale. Opening the app does not overwrite older entries.
enum WatchEventLog {
    struct Event: Codable, Equatable {
        let date: Date
        let source: String
        let detail: String
    }

    private static let key = "watch.eventLog"
    private static let capacity = 40
    private static let lock = NSLock()

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroupID.current())
    }

    /// Appends an event, dropping the oldest beyond the capacity. Safe from any thread.
    static func record(_ source: String, _ detail: String) {
        lock.lock()
        defer { lock.unlock() }
        var events = loadUnlocked()
        events.append(Event(date: Date(), source: source, detail: detail))
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
        if let data = try? JSONEncoder().encode(events) {
            defaults?.set(data, forKey: key)
        }
    }

    /// Events, newest first.
    static func recent() -> [Event] {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked().reversed()
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        defaults?.removeObject(forKey: key)
    }

    private static func loadUnlocked() -> [Event] {
        guard let data = defaults?.data(forKey: key),
              let events = try? JSONDecoder().decode([Event].self, from: data)
        else { return [] }
        return events
    }
}
