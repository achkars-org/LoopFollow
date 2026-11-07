// LoopFollow
// CarPlayWidgetAlertsTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct CarPlayWidgetAlertsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A fresh in-range reading and a recent loop: nothing to report.
    private func calm() -> WidgetAlertInputs {
        var inputs = WidgetAlertInputs()
        inputs.latestReadingAt = now.addingTimeInterval(-120)
        inputs.latestMgdl = 120
        inputs.lastLoopAt = now.addingTimeInterval(-180)
        inputs.highMgdl = 180
        return inputs
    }

    private func kinds(_ inputs: WidgetAlertInputs, at date: Date? = nil) -> [WidgetAlert.Kind] {
        inputs.alerts(at: date ?? now).map(\.kind)
    }

    @Test("Nothing to report gives no alerts, so the page shows the thumbs-up")
    func allClear() {
        #expect(calm().alerts(at: now).isEmpty)
    }

    @Test("Old readings replace the glucose alerts with No new readings")
    func noReadings() {
        var inputs = calm()
        inputs.latestMgdl = 60
        #expect(kinds(inputs, at: now.addingTimeInterval(20 * 60)).contains(.noReadings))
        #expect(!kinds(inputs, at: now.addingTimeInterval(20 * 60)).contains(.low))
        #expect(kinds(inputs).contains(.low))
    }

    @Test("Not looping appears once the loop is older than the threshold, later on the timeline too")
    func notLooping() {
        let inputs = calm()
        #expect(!kinds(inputs).contains(.notLooping))
        let later = inputs.alerts(at: now.addingTimeInterval(16 * 60))
        #expect(later.first?.kind == .notLooping || later.first?.kind == .noReadings)
        #expect(later.contains { $0.kind == .notLooping && $0.detail == "Last loop 19 min ago" })
    }

    @Test("A predicted low shows how soon; a current low takes its place")
    func lowSoon() {
        var inputs = calm()
        inputs.predictedLowAt = now.addingTimeInterval(20 * 60)
        let alerts = inputs.alerts(at: now)
        #expect(alerts.map(\.kind) == [.lowSoon])
        #expect(alerts.first?.detail == "In about 20 min")

        inputs.latestMgdl = 70
        #expect(kinds(inputs) == [.low])
    }

    @Test("Glucose is shown in the user's unit")
    func lowInMmol() {
        var inputs = calm()
        inputs.unit = .mmol
        inputs.latestMgdl = 63
        #expect(inputs.alerts(at: now).first?.detail == "3.5 mmol/L")
    }

    @Test("Expiry warns inside the window and turns urgent once past")
    func expiry() {
        var inputs = calm()
        inputs.sensorExpiresAt = now.addingTimeInterval(13 * 3600)
        #expect(kinds(inputs).isEmpty)

        inputs.sensorExpiresAt = now.addingTimeInterval(6 * 3600)
        let warning = inputs.alerts(at: now).first
        #expect(warning?.title == "Sensor expires")
        #expect(warning?.detail == "In 6 h")
        #expect(warning?.severity == .warning)

        inputs.sensorExpiresAt = now.addingTimeInterval(-60)
        #expect(inputs.alerts(at: now).first?.title == "Sensor expired")
        #expect(inputs.alerts(at: now).first?.severity == .urgent)
    }

    @Test("Urgent alerts come before warnings")
    func ordering() {
        var inputs = calm()
        inputs.reservoirUnits = 12
        inputs.lastLoopAt = now.addingTimeInterval(-30 * 60)
        #expect(kinds(inputs) == [.notLooping, .lowInsulin])
        #expect(inputs.alerts(at: now).last?.detail == "12 U left")
    }

    @Test("A charging phone gets no battery warning")
    func phoneCharging() {
        var inputs = calm()
        inputs.phoneBatteryPercent = 10
        #expect(kinds(inputs) == [.phoneBattery])
        inputs.phoneCharging = true
        #expect(kinds(inputs).isEmpty)
    }

    @Test("Durations round up and ages round down")
    func durations() {
        #expect(WidgetAlertInputs.duration(30) == "1 min")
        #expect(WidgetAlertInputs.duration(45 * 60) == "45 min")
        #expect(WidgetAlertInputs.duration(5 * 3600 + 60) == "6 h")
        #expect(WidgetAlertInputs.duration(3 * 86400) == "3 days")
        #expect(WidgetAlertInputs.ago(19 * 60 + 50) == "19 min ago")
        #expect(WidgetAlertInputs.ago(3 * 3600) == "3 h ago")
    }

    @Test("Thresholds come from the user's enabled alarm, else the alarm's default")
    func thresholdsFromAlarms() {
        let data = AlarmData.withSensorInsertTime(now.timeIntervalSince1970)

        let defaults = WidgetAlertInputs(alarmData: data, alarms: [], unit: .mgdl, now: now)
        #expect(defaults.sensorWarnHours == 12)
        #expect(defaults.sensorExpiresAt == now.addingTimeInterval(10 * 86400))

        var disabled = Alarm.sensorChange(threshold: 48, lifetimeDays: 15)
        disabled.isEnabled = false
        let enabled = Alarm.sensorChange(threshold: 24, lifetimeDays: 14)
        let inputs = WidgetAlertInputs(alarmData: data, alarms: [disabled, enabled], unit: .mgdl, now: now)
        #expect(inputs.sensorWarnHours == 24)
        #expect(inputs.sensorExpiresAt == now.addingTimeInterval(14 * 86400))
    }

    @Test("A low in the forecast is found within the look-ahead")
    func predictedLowFromForecast() {
        let readings = [GlucoseValue(sgv: 110, date: now)]
        let forecast = (0 ..< 12).map { GlucoseValue(sgv: 110 - $0 * 5, date: now.addingTimeInterval(Double($0) * 300)) }
        let data = AlarmData.withGlucose(readings: readings, prediction: forecast)

        let inputs = WidgetAlertInputs(alarmData: data, alarms: [.low(belowBG: 80)], unit: .mgdl, now: now)
        #expect(inputs.predictedLowAt == now.addingTimeInterval(6 * 300))

        let shortLook = WidgetAlertInputs(alarmData: data, alarms: [.low(belowBG: 80, predictiveMinutes: 15)], unit: .mgdl, now: now)
        #expect(shortLook.predictedLowAt == nil)
    }

    @Test("The page button cycles through every page and back to the first")
    func pageCycle() {
        var page = CarPlayWidgetPage.now
        var seen: [CarPlayWidgetPage] = []
        for _ in CarPlayWidgetPage.allCases {
            seen.append(page)
            page = page.next
        }
        #expect(seen == CarPlayWidgetPage.allCases)
        #expect(page == .now)
    }
}
