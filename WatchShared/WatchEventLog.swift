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
        /// How many identical occurrences this line stands for (see `record(coalescing:)`).
        var count = 1
    }

    private static let key = "watch.eventLog"
    private static let capacity = 40
    private static let lock = NSLock()

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroupID.current())
    }

    /// Appends an event, dropping the oldest beyond the capacity. Safe from any thread.
    /// With `coalescing`, an earlier identical event is folded into the new one (count
    /// incremented, time refreshed) so repeated noise cannot push real events out.
    static func record(_ source: String, _ detail: String, coalescing: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        var events = loadUnlocked()
        var count = 1
        if coalescing, let index = events.firstIndex(where: { $0.source == source && $0.detail == detail }) {
            count = events[index].count + 1
            events.remove(at: index)
        }
        events.append(Event(date: Date(), source: source, detail: detail, count: count))
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
