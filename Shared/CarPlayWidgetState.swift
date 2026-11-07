// LoopFollow
// CarPlayWidgetState.swift

import Foundation

/// What the CarPlay widget shows. The app writes it to the App Group and the
/// widget reads it back; nothing here depends on either side's code.
struct CarPlayWidgetState: Codable, Equatable {
    /// The latest reading and loop values; nil before the first reading.
    var snapshot: GlucoseSnapshot?

    /// Readings from the last `historyWindow`, oldest first.
    var history: [GlucosePoint]

    /// The user's alarms marked for CarPlay that are triggered, most
    /// important first.
    var alerts: [CarPlayAlert]

    /// How far back the 3 h page reaches.
    static let historyWindow: TimeInterval = 3 * 3600

    var hasAlerts: Bool {
        !alerts.isEmpty
    }

    /// "18 min ago", "2 h ago": rounded down, as clocks count.
    static func ago(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int(seconds / 60))
        if minutes < 90 { return "\(minutes) min ago" }
        return "\(minutes / 60) h ago"
    }
}

/// One CGM reading, in mg/dL.
struct GlucosePoint: Codable, Equatable {
    let date: Date
    let mgdl: Double
}

/// One line on the Alerts page: a triggered alarm, already worded. The text
/// holds no countdowns, so it only changes when the alarm's state does and
/// the widget isn't reloaded every minute.
struct CarPlayAlert: Codable, Equatable, Identifiable {
    /// The alarm's id.
    let id: UUID
    /// The alarm's name, or the phase it announces ("Override Ending Soon").
    let title: String
    /// The value behind it: the reading, units left, an expiry time.
    let detail: String?
    /// SF Symbol for the alarm's type.
    let symbol: String
    /// Shown in red rather than orange.
    let isUrgent: Bool
}

/// The widget's pages, in the order the page button steps through them.
/// Alerts is only in the cycle while there is something to report.
enum CarPlayWidgetPage: Int, CaseIterable, Codable {
    case now
    case alerts
    case trend

    var title: String {
        switch self {
        case .now: "Now"
        case .alerts: "Alerts"
        case .trend: "3 h"
        }
    }

    /// The pages in the cycle.
    static func sequence(hasAlerts: Bool) -> [CarPlayWidgetPage] {
        hasAlerts ? [.now, .alerts, .trend] : [.now, .trend]
    }

    /// This page if it is in the cycle; Alerts with nothing to report falls
    /// back to Now.
    func resolved(hasAlerts: Bool) -> CarPlayWidgetPage {
        Self.sequence(hasAlerts: hasAlerts).contains(self) ? self : .now
    }

    /// The page the button leads to, wrapping round to Now. From an Alerts
    /// page whose alerts have cleared, that is the page after it.
    func next(hasAlerts: Bool) -> CarPlayWidgetPage {
        let pages = Self.sequence(hasAlerts: hasAlerts)
        if let index = pages.firstIndex(of: self) {
            return pages[(index + 1) % pages.count]
        }
        return pages.first { $0.rawValue > rawValue } ?? .now
    }
}

/// The widget's state and current page in the App Group.
enum CarPlayWidgetStore {
    /// The widget kind, used by the app to ask for a reload.
    static let kind = "LoopFollowCarPlayWidget"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroupID.current())
    }

    private enum Keys {
        static let state = "carPlayWidget.state"
        static let page = "carPlayWidget.page"
    }

    /// Encodes with sorted keys, so equal states give equal data and the app
    /// can skip a reload when nothing changed.
    static func encode(_ state: CarPlayWidgetState) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(state)
    }

    static func save(_ data: Data) {
        defaults?.set(data, forKey: Keys.state)
    }

    static func load() -> CarPlayWidgetState? {
        guard let data = defaults?.data(forKey: Keys.state) else { return nil }
        return try? JSONDecoder().decode(CarPlayWidgetState.self, from: data)
    }

    static var page: CarPlayWidgetPage {
        get { CarPlayWidgetPage(rawValue: defaults?.integer(forKey: Keys.page) ?? 0) ?? .now }
        set { defaults?.set(newValue.rawValue, forKey: Keys.page) }
    }
}
