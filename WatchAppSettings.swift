// WatchAppSettings.swift
// LoopFollowWatch Watch App
//
// STUB — single source of truth for all editable alert settings.
// Currently backed by UserDefaults.standard (watch-local).
// TODO: Migrate to shared App Group container if iPhone needs read/write access.

import Foundation
import Combine

final class WatchAppSettings: ObservableObject {

    static let shared = WatchAppSettings()
    private init() {}

    // MARK: - UserDefaults keys

    private enum Key {
        static let snoozeAllByDefault   = "watchSnoozeAllByDefault"
        static let defaultSnoozeMinutes = "watchDefaultSnoozeMinutes"
        static func cooldown(_ type: WatchAlertType) -> String { "watchCooldown_\(type.rawValue)" }
    }

    // MARK: - Snooze defaults

    var snoozeAllByDefault: Bool {
        get { UserDefaults.standard.object(forKey: Key.snoozeAllByDefault) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.snoozeAllByDefault); objectWillChange.send() }
    }

    var defaultSnoozeMinutes: Int {
        get { UserDefaults.standard.object(forKey: Key.defaultSnoozeMinutes) as? Int ?? 60 }
        set { UserDefaults.standard.set(newValue, forKey: Key.defaultSnoozeMinutes); objectWillChange.send() }
    }

    // MARK: - Cooldowns

    /// Default cooldowns in seconds. Used when no persisted value exists.
    static let defaultCooldowns: [WatchAlertType: TimeInterval] = [
        .lowBG:     15 * 60,
        .urgentLow:  5 * 60,
        .highBG:    15 * 60,
        .fastDrop:  10 * 60,
        .fastRise:  10 * 60,
    ]

    func cooldown(for type: WatchAlertType) -> TimeInterval {
        let stored = UserDefaults.standard.double(forKey: Key.cooldown(type))
        return stored > 0 ? stored : (Self.defaultCooldowns[type] ?? 10 * 60)
    }

    func setCooldown(_ seconds: TimeInterval, for type: WatchAlertType) {
        UserDefaults.standard.set(seconds, forKey: Key.cooldown(type))
        objectWillChange.send()
    }
}
