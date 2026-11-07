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

    /// What the Alerts page checks. Kept as inputs rather than finished alerts
    /// so the widget can evaluate them again at every timeline date.
    var alertInputs: WidgetAlertInputs

    /// How far back the Trend page reaches.
    static let historyWindow: TimeInterval = 3 * 3600
}

/// One CGM reading, in mg/dL.
struct GlucosePoint: Codable, Equatable {
    let date: Date
    let mgdl: Double
}

/// The widget's pages, in the order the page button steps through them.
enum CarPlayWidgetPage: Int, CaseIterable, Codable {
    case now
    case trend
    case override
    case alerts

    var title: String {
        switch self {
        case .now: "Now"
        case .trend: "Trend"
        case .override: "Override"
        case .alerts: "Alerts"
        }
    }

    /// The page after this one, wrapping round to the first.
    var next: CarPlayWidgetPage {
        Self(rawValue: (rawValue + 1) % Self.allCases.count) ?? .now
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

// MARK: - Alerts

/// One line on the Alerts page.
struct WidgetAlert: Equatable, Identifiable {
    enum Kind: String, CaseIterable {
        case noReadings
        case notLooping
        case low
        case lowSoon
        case droppingFast
        case high
        case sensorExpiry
        case siteExpiry
        case lowInsulin
        case pumpBattery
        case phoneBattery
        case appExpiry
    }

    enum Severity: Int, Comparable {
        case urgent
        case warning

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    let kind: Kind
    let severity: Severity
    let title: String
    let detail: String?

    var id: Kind { kind }
}

/// Everything the Alerts page needs, with the thresholds taken from the
/// user's alarms. Times are absolute, so the same inputs give the right
/// alerts at any later date without the app running.
struct WidgetAlertInputs: Codable, Equatable {
    var unit: GlucoseSnapshot.Unit = .mgdl

    // Glucose
    var latestReadingAt: Date?
    var latestMgdl: Double?
    var missedReadingMinutes: Double = 16
    var lowMgdl: Double = 80
    /// The first forecast point at or below `lowMgdl`, if any.
    var predictedLowAt: Date?
    var isDroppingFast = false
    /// Nil leaves out the high alert.
    var highMgdl: Double?

    // Loop
    var lastLoopAt: Date?
    var notLoopingMinutes: Double = 16

    // Devices
    var sensorExpiresAt: Date?
    var sensorWarnHours: Double = 12
    var siteExpiresAt: Date?
    var siteWarnHours: Double = 12
    var reservoirUnits: Double?
    var reservoirWarnUnits: Double = 20
    var pumpBatteryPercent: Double?
    var pumpBatteryWarnPercent: Double = 20
    var phoneBatteryPercent: Double?
    var phoneBatteryWarnPercent: Double = 20
    var phoneCharging = false
    var appExpiresAt: Date?
    var appWarnDays: Double = 7

    /// The alerts that apply at `now`, urgent ones first, each group in a
    /// fixed order. Glucose alerts need a reading recent enough to trust;
    /// without one, "No new readings" stands in for them.
    func alerts(at now: Date) -> [WidgetAlert] {
        var list: [WidgetAlert] = []

        let readingAge = latestReadingAt.map { now.timeIntervalSince($0) }
        let readingIsFresh = readingAge.map { $0 < missedReadingMinutes * 60 } ?? false

        if let age = readingAge, !readingIsFresh {
            list.append(WidgetAlert(kind: .noReadings, severity: .urgent, title: "No new readings", detail: "Last one \(Self.ago(age))"))
        }

        if let lastLoopAt {
            let sinceLoop = now.timeIntervalSince(lastLoopAt)
            if sinceLoop >= notLoopingMinutes * 60 {
                list.append(WidgetAlert(kind: .notLooping, severity: .urgent, title: "Not looping", detail: "Last loop \(Self.ago(sinceLoop))"))
            }
        }

        if readingIsFresh, let bg = latestMgdl {
            if bg <= lowMgdl {
                list.append(WidgetAlert(kind: .low, severity: .urgent, title: "Low", detail: formatGlucose(bg)))
            } else if let lowAt = predictedLowAt {
                let detail = lowAt > now ? "In about \(Self.duration(lowAt.timeIntervalSince(now)))" : nil
                list.append(WidgetAlert(kind: .lowSoon, severity: .urgent, title: "Low soon", detail: detail))
            }

            if isDroppingFast {
                list.append(WidgetAlert(kind: .droppingFast, severity: .warning, title: "Dropping fast", detail: formatGlucose(bg)))
            }

            if let high = highMgdl, bg >= high {
                list.append(WidgetAlert(kind: .high, severity: .warning, title: "High", detail: formatGlucose(bg)))
            }
        }

        if let alert = Self.expiry(sensorExpiresAt, warnAhead: sensorWarnHours * 3600, kind: .sensorExpiry, name: "Sensor", now: now) {
            list.append(alert)
        }
        if let alert = Self.expiry(siteExpiresAt, warnAhead: siteWarnHours * 3600, kind: .siteExpiry, name: "Pump site", now: now) {
            list.append(alert)
        }

        if let units = reservoirUnits, units <= reservoirWarnUnits {
            list.append(WidgetAlert(kind: .lowInsulin, severity: .warning, title: "Low insulin", detail: "\(Int(units.rounded())) U left"))
        }
        if let percent = pumpBatteryPercent, percent <= pumpBatteryWarnPercent {
            list.append(WidgetAlert(kind: .pumpBattery, severity: .warning, title: "Pump battery low", detail: "\(Int(percent.rounded()))%"))
        }
        if let percent = phoneBatteryPercent, percent <= phoneBatteryWarnPercent, !phoneCharging {
            list.append(WidgetAlert(kind: .phoneBattery, severity: .warning, title: "Loop phone battery", detail: "\(Int(percent.rounded()))%"))
        }

        if let alert = Self.expiry(appExpiresAt, warnAhead: appWarnDays * 86400, kind: .appExpiry, name: "Loop app", now: now) {
            list.append(alert)
        }

        // Urgent first; the order above is kept within each severity.
        return list.enumerated()
            .sorted { ($0.element.severity, $0.offset) < ($1.element.severity, $1.offset) }
            .map(\.element)
    }

    /// "Sensor expires · In 6 h" inside the warning window, "Sensor expired"
    /// once past it, nothing before.
    private static func expiry(_ date: Date?, warnAhead: TimeInterval, kind: WidgetAlert.Kind, name: String, now: Date) -> WidgetAlert? {
        guard let date else { return nil }
        let remaining = date.timeIntervalSince(now)
        if remaining <= 0 {
            return WidgetAlert(kind: kind, severity: .urgent, title: "\(name) expired", detail: nil)
        }
        guard remaining <= warnAhead else { return nil }
        return WidgetAlert(kind: kind, severity: .warning, title: "\(name) expires", detail: "In \(duration(remaining))")
    }

    /// "45 min", "6 h", "3 days": rounded up, so it never reads 0.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes) min" }
        let hours = Int((Double(minutes) / 60).rounded(.up))
        if hours < 48 { return "\(hours) h" }
        return "\(Int((Double(hours) / 24).rounded(.up))) days"
    }

    /// "18 min ago", "2 h ago": rounded down, as clocks count.
    static func ago(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int(seconds / 60))
        if minutes < 90 { return "\(minutes) min ago" }
        return "\(minutes / 60) h ago"
    }

    private func formatGlucose(_ mgdl: Double) -> String {
        switch unit {
        case .mgdl:
            "\(Int(mgdl.rounded())) mg/dL"
        case .mmol:
            "\(GlucoseConversion.toMmol(mgdl).formatted(.number.precision(.fractionLength(1)))) mmol/L"
        }
    }
}
