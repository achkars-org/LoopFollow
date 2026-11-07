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
            let snapshot = GlucoseSnapshotBuilder.build(from: StorageCurrentGlucoseStateProvider())
            let state = CarPlayWidgetState(
                snapshot: snapshot,
                history: history(from: readings, now: now),
                alertInputs: WidgetAlertInputs(
                    alarmData: alarmData,
                    alarms: Storage.shared.alarms.value,
                    unit: PreferredGlucoseUnit.snapshotUnit(),
                    now: now
                )
            )

            guard let data = CarPlayWidgetStore.encode(state), data != lastPublished else { return }
            CarPlayWidgetStore.save(data)
            lastPublished = data
            WidgetCenter.shared.reloadTimelines(ofKind: CarPlayWidgetStore.kind)
        }

        /// Readings inside the Trend page's window, oldest first.
        static func history(from readings: [ShareGlucoseData], now: Date) -> [GlucosePoint] {
            let start = now.timeIntervalSince1970 - CarPlayWidgetState.historyWindow
            return readings
                .filter { $0.sgv > 0 && $0.date >= start }
                .sorted { $0.date < $1.date }
                .map { GlucosePoint(date: Date(timeIntervalSince1970: $0.date), mgdl: Double($0.sgv)) }
        }
    }

#endif

extension WidgetAlertInputs {
    /// Looks ahead this far for a low when the low alarm has no look-ahead of its own.
    static let defaultLowLookaheadMinutes = 30

    /// Inputs from the values the alarms check, with each threshold taken
    /// from the user's first enabled alarm of that type, or the alarm's
    /// default when none is enabled. Snoozes and day/night limits are
    /// ignored: they silence an alarm, but the condition still holds.
    init(alarmData data: AlarmData, alarms: [Alarm], unit: GlucoseSnapshot.Unit, now: Date) {
        func settings(_ type: AlarmType) -> Alarm {
            alarms.first { $0.type == type && $0.isEnabled } ?? Alarm(type: type)
        }

        func positive(_ value: Double?) -> Double? {
            guard let value, value > 0 else { return nil }
            return value
        }

        func date(_ timestamp: TimeInterval?) -> Date? {
            guard let timestamp, timestamp > 0 else { return nil }
            return Date(timeIntervalSince1970: timestamp)
        }

        self.init()
        self.unit = unit

        if let last = data.bgReadings.last, last.sgv > 0 {
            latestReadingAt = last.date
            latestMgdl = Double(last.sgv)
        }
        missedReadingMinutes = positive(settings(.missedReading).threshold) ?? missedReadingMinutes

        let low = settings(.low)
        lowMgdl = positive(low.belowBG) ?? lowMgdl
        let lookahead = (low.predictiveMinutes ?? 0) > 0 ? low.predictiveMinutes! : Self.defaultLowLookaheadMinutes
        let threshold = lowMgdl
        predictedLowAt = data.predictionData
            .prefix(LowBGCondition.forecastPoints(forMinutes: lookahead))
            .first { $0.sgv > 0 && Double($0.sgv) <= threshold }?
            .date

        isDroppingFast = FastDropCondition().evaluate(alarm: settings(.fastDrop), data: data, now: now)
        highMgdl = positive(settings(.high).aboveBG)

        lastLoopAt = date(data.lastLoopTime)
        notLoopingMinutes = positive(settings(.notLooping).threshold) ?? notLoopingMinutes

        let sensor = settings(.sensorChange)
        if let inserted = date(data.sageInsertTime) {
            sensorExpiresAt = inserted.addingTimeInterval(Double(sensor.sensorLifetimeDays ?? 10) * 86400)
        }
        sensorWarnHours = positive(sensor.threshold) ?? sensorWarnHours

        // The same 3-day site life the pump change alarm uses.
        siteExpiresAt = date(data.pumpInsertTime)?.addingTimeInterval(3 * 86400)
        siteWarnHours = positive(settings(.pumpChange).threshold) ?? siteWarnHours

        reservoirUnits = data.latestPumpVolume
        reservoirWarnUnits = positive(settings(.pump).threshold) ?? reservoirWarnUnits

        pumpBatteryPercent = data.latestPumpBattery
        pumpBatteryWarnPercent = positive(settings(.pumpBattery).threshold) ?? pumpBatteryWarnPercent

        // The looping phone's battery, as uploaded. A phone that's charging
        // needs no warning, whatever the alarm does.
        phoneBatteryPercent = data.latestBattery
        phoneBatteryWarnPercent = positive(settings(.battery).threshold) ?? phoneBatteryWarnPercent
        phoneCharging = data.latestBatteryIsCharging == true

        appExpiresAt = data.expireDate
        appWarnDays = positive(settings(.buildExpire).threshold) ?? appWarnDays
    }
}
