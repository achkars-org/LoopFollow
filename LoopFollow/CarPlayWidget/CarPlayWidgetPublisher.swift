// LoopFollow
// CarPlayWidgetPublisher.swift

#if !targetEnvironment(macCatalyst)

    import Foundation
    import WidgetKit

    /// Writes the CarPlay widget's state after each alarm check and asks
    /// WidgetKit to redraw it, but only when something it shows has changed:
    /// redraws requested from the background are rationed.
    enum CarPlayWidgetPublisher {
        private static var lastPublished: Data?

        static func publish(alarmData: AlarmData, readings: [ShareGlucoseData], now: Date = Date()) {
            let unit = PreferredGlucoseUnit.snapshotUnit()
            let alerts = AlarmManager.shared.carPlayAlarms(data: alarmData, now: now).map {
                CarPlayAlert(alarm: $0.alarm, title: $0.title, data: alarmData, unit: unit)
            }
            let state = CarPlayWidgetState(
                snapshot: GlucoseSnapshotBuilder.build(from: StorageCurrentGlucoseStateProvider()),
                history: history(from: readings, now: now),
                alerts: alerts
            )

            guard let data = CarPlayWidgetStore.encode(state), data != lastPublished else { return }
            CarPlayWidgetStore.save(data)
            lastPublished = data
            WidgetCenter.shared.reloadTimelines(ofKind: CarPlayWidgetStore.kind)
        }

        /// Readings inside the 3 h page's window, oldest first.
        static func history(from readings: [ShareGlucoseData], now: Date) -> [GlucosePoint] {
            let start = now.timeIntervalSince1970 - CarPlayWidgetState.historyWindow
            return readings
                .filter { $0.sgv > 0 && $0.date >= start }
                .sorted { $0.date < $1.date }
                .map { GlucosePoint(date: Date(timeIntervalSince1970: $0.date), mgdl: Double($0.sgv)) }
        }
    }

#endif

extension CarPlayAlert {
    /// A triggered alarm, worded for the widget with the icon LoopFollow uses
    /// for its type. Times are clock times rather than countdowns, so the
    /// text stays the same between checks.
    init(alarm: Alarm, title: String, data: AlarmData, unit: GlucoseSnapshot.Unit) {
        self.init(
            id: alarm.id,
            title: title,
            detail: Self.detail(for: alarm, data: data, unit: unit),
            symbol: alarm.type.icon,
            isUrgent: Self.isUrgent(alarm.type)
        )
    }

    /// Red rather than orange: the alarms about glucose or the loop that
    /// need attention now.
    static func isUrgent(_ type: AlarmType) -> Bool {
        switch type {
        case .low, .fastDrop, .missedReading, .notLooping, .temporary:
            true
        default:
            false
        }
    }

    /// The value behind the alarm. Missed reading and not looping use the
    /// alarm notification's own text when the CGM reported a state.
    static func detail(for alarm: Alarm, data: AlarmData, unit: GlucoseSnapshot.Unit) -> String? {
        if let body = alarm.notificationBody {
            return body
        }

        switch alarm.type {
        case .low, .high, .fastDrop, .fastRise, .temporary:
            guard let sgv = data.bgReadings.last?.sgv, sgv > 0 else { return nil }
            return glucose(Double(sgv), unit: unit)
        case .missedReading:
            return data.bgReadings.last.map { "Last reading \(clock($0.date))" }
        case .notLooping:
            guard let loop = data.lastLoopTime, loop > 0 else { return nil }
            return "Last loop \(clock(Date(timeIntervalSince1970: loop)))"
        case .sensorChange:
            guard let inserted = data.sageInsertTime, inserted > 0 else { return nil }
            let lifetime = Double(alarm.sensorLifetimeDays ?? 10) * 86400
            return "Expires \(clock(Date(timeIntervalSince1970: inserted + lifetime)))"
        case .pumpChange:
            // The same 3-day site life the pump change alarm uses.
            guard let inserted = data.pumpInsertTime, inserted > 0 else { return nil }
            return "Expires \(clock(Date(timeIntervalSince1970: inserted + 3 * 86400)))"
        case .pump:
            return data.latestPumpVolume.map { "\(Int($0.rounded())) U left" }
        case .pumpBattery:
            return data.latestPumpBattery.map { "\(Int($0.rounded()))%" }
        case .battery, .batteryDrop:
            return data.latestBattery.map { "\(Int($0.rounded()))%" }
        case .iob:
            return data.IOB.map { "\($0.formatted(.number.precision(.fractionLength(1)))) U" }
        case .cob:
            return data.COB.map { "\(Int($0.rounded())) g" }
        case .recBolus:
            return data.recBolus.map { "\($0.formatted(.number.precision(.fractionLength(2)))) U" }
        case .buildExpire:
            return data.expireDate.map { "Expires \($0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))" }
        case .dbSize:
            return data.dbSizePercentage.map { "\(Int($0.rounded()))% full" }
        case .missedBolus, .futureCarbs, .overrideStart, .overrideEnd, .tempTargetStart, .tempTargetEnd:
            return nil
        }
    }

    /// "14:05" today, "Sat 14:05" on another day, in the user's clock format.
    static func clock(_ date: Date, now: Date = Date()) -> String {
        if Calendar.current.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private static func glucose(_ mgdl: Double, unit: GlucoseSnapshot.Unit) -> String {
        switch unit {
        case .mgdl:
            "\(Int(mgdl.rounded())) mg/dL"
        case .mmol:
            "\(GlucoseConversion.toMmol(mgdl).formatted(.number.precision(.fractionLength(1)))) mmol/L"
        }
    }
}
