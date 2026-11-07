// LoopFollow
// CarPlayWidgetAlertsTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct CarPlayWidgetAlertsTests {
    // MARK: - The CarPlay toggle on alarms

    @Test("New alarms are not shown in CarPlay")
    func offByDefault() {
        for type in AlarmType.allCases {
            #expect(Alarm(type: type).showInCarPlay == false)
        }
    }

    @Test("Alarms saved before the toggle existed decode with it off")
    func decodesOldAlarms() throws {
        let data = try JSONEncoder().encode(Alarm(type: .low))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "showInCarPlay")
        let old = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(Alarm.self, from: old).showInCarPlay == false)
    }

    @Test("The toggle survives saving and loading")
    func roundTrip() throws {
        var alarm = Alarm(type: .notLooping)
        alarm.showInCarPlay = true
        let decoded = try JSONDecoder().decode(Alarm.self, from: JSONEncoder().encode(alarm))
        #expect(decoded.showInCarPlay)
    }

    // MARK: - Which alarms can be checked again

    @Test("Alarms that record that they fired are never checked a second time")
    func oneTimeAlarms() {
        let oneTime: Set<AlarmType> = [
            .cob, .recBolus, .missedBolus, .futureCarbs,
            .overrideStart, .overrideEnd, .tempTargetStart, .tempTargetEnd,
        ]
        for type in AlarmType.allCases {
            #expect(type.isStateCondition == !oneTime.contains(type), "\(type)")
        }
    }

    // MARK: - Wording

    @Test("Glucose alarms show the reading in the user's unit")
    func glucoseDetail() {
        let data = AlarmData.withReadings([90, 75, 63])
        #expect(CarPlayAlert.detail(for: Alarm(type: .low), data: data, unit: .mgdl) == "63 mg/dL")
        #expect(CarPlayAlert.detail(for: Alarm(type: .low), data: data, unit: .mmol) == "3.5 mmol/L")
    }

    @Test("Sensor expiry uses the alarm's sensor lifetime")
    func sensorDetail() {
        let inserted = Date().addingTimeInterval(-9 * 86400)
        let data = AlarmData.withSensorInsertTime(inserted.timeIntervalSince1970)
        let alarm = Alarm.sensorChange(threshold: 12, lifetimeDays: 10)
        let expiry = inserted.addingTimeInterval(10 * 86400)
        #expect(CarPlayAlert.detail(for: alarm, data: data, unit: .mgdl) == "Expires \(CarPlayAlert.clock(expiry))")
    }

    @Test("A triggered alarm keeps its id and the title it fired with")
    func alertFromAlarm() {
        var alarm = Alarm(type: .battery)
        alarm.name = "Loop phone"
        let alert = CarPlayAlert(alarm: alarm, title: alarm.name, data: .withBattery(14.6), unit: .mgdl)
        #expect(alert.id == alarm.id)
        #expect(alert.title == "Loop phone")
        #expect(alert.detail == "15%")
        #expect(alert.symbol == AlarmType.battery.icon)
        #expect(alert.isUrgent == false)
        #expect(CarPlayAlert.isUrgent(.low))
    }

    @Test("Ages round down")
    func ages() {
        #expect(CarPlayWidgetState.ago(30) == "1 min ago")
        #expect(CarPlayWidgetState.ago(19 * 60 + 50) == "19 min ago")
        #expect(CarPlayWidgetState.ago(3 * 3600) == "3 h ago")
    }

    // MARK: - Pages

    @Test("With alerts the button goes Now, Alerts, 3 h and back to Now")
    func pageCycleWithAlerts() {
        #expect(CarPlayWidgetPage.now.next(hasAlerts: true) == .alerts)
        #expect(CarPlayWidgetPage.alerts.next(hasAlerts: true) == .trend)
        #expect(CarPlayWidgetPage.trend.next(hasAlerts: true) == .now)
    }

    @Test("Without alerts the Alerts page is skipped")
    func pageCycleWithoutAlerts() {
        #expect(CarPlayWidgetPage.now.next(hasAlerts: false) == .trend)
        #expect(CarPlayWidgetPage.trend.next(hasAlerts: false) == .now)
    }

    @Test("An Alerts page whose alerts have cleared shows Now, and its button moves on to 3 h")
    func clearedAlertsPage() {
        #expect(CarPlayWidgetPage.alerts.resolved(hasAlerts: false) == .now)
        #expect(CarPlayWidgetPage.alerts.resolved(hasAlerts: true) == .alerts)
        #expect(CarPlayWidgetPage.alerts.next(hasAlerts: false) == .trend)
    }
}
