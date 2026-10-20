// LoopFollow
// InsulinVariabilityCalculatorTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct InsulinVariabilityCalculatorTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var day: TimeInterval {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!.timeIntervalSince1970
    }

    private func hour(_ h: Double) -> TimeInterval { day + h * 3600 }

    private func basal(_ rate: Double, at h: Double) -> MainViewController.basalGraphStruct {
        .init(basalRate: rate, date: hour(h))
    }

    private func bolus(_ units: Double, at h: Double) -> MainViewController.bolusGraphStruct {
        .init(value: units, date: hour(h), sgv: 0)
    }

    private func carbs(_ grams: Double, at h: Double) -> MainViewController.carbGraphStruct {
        .init(value: grams, date: hour(h), sgv: 0, absorptionTime: 0)
    }

    private func calculate(
        basalData: [MainViewController.basalGraphStruct],
        automaticBoluses: [MainViewController.bolusGraphStruct] = [],
        manualBoluses: [MainViewController.bolusGraphStruct] = [],
        carbs: [MainViewController.carbGraphStruct] = [],
        overrides: [StatsOverride] = [],
        carbRatio: Double? = 10
    ) -> [TIRPeriod: InsulinVariabilityDataPoint] {
        let points = InsulinVariabilityCalculator.calculate(
            basalData: basalData,
            basalProfile: [.init(value: 1, time: "00:00", timeAsSeconds: 0)],
            automaticBoluses: automaticBoluses,
            manualBoluses: manualBoluses,
            carbs: carbs,
            overrides: overrides,
            carbRatio: { _ in carbRatio },
            startTime: day,
            endTime: day + 24 * 3600,
            calendar: calendar
        )
        return Dictionary(uniqueKeysWithValues: points.map { ($0.period, $0) })
    }

    @Test("basal at the override-scaled rate is on plan")
    func overrideScalesPlannedBasal() {
        let result = calculate(
            basalData: [basal(1, at: 0), basal(1.35, at: 6), basal(1, at: 12)],
            overrides: [StatsOverride(start: hour(6), end: hour(12), insulinNeedsScaleFactor: 1.35)]
        )
        let morning = result[.morning]!
        #expect(abs(morning.plannedBasal - 8.1) < 0.001)
        #expect(abs(morning.variability) < 0.001)
    }

    @Test("basal is measured against the override-scaled rate")
    func basalDeviationUnderOverride() {
        // (2.7 / 1.35) - 1 = +100%
        let result = calculate(
            basalData: [basal(1, at: 0), basal(2.7, at: 6), basal(1, at: 12)],
            overrides: [StatsOverride(start: hour(6), end: hour(12), insulinNeedsScaleFactor: 1.35)]
        )
        #expect(abs(result[.morning]!.variability - 100) < 0.001)
    }

    @Test("automatic boluses count as delivered basal")
    func automaticBolusesCountAsBasal() {
        let result = calculate(basalData: [basal(1, at: 0)], automaticBoluses: [bolus(0.6, at: 1)])
        #expect(abs(result[.night]!.deliveredBasal - 6.6) < 0.001)
        #expect(abs(result[.night]!.basalDeviation - 10) < 0.001)
    }

    @Test("a meal's boluses are compared with its carbs / carb ratio")
    func mealBolusAgainstCarbs() {
        // 60 g + 20 g ten minutes later is one 8 U meal; 9 U given five minutes before.
        let result = calculate(
            basalData: [basal(1, at: 0)],
            manualBoluses: [bolus(9, at: 12.9)],
            carbs: [carbs(60, at: 13), carbs(20, at: 13 + 1 / 6)]
        )
        let day = result[.day]!
        #expect(abs(day.plannedMealBolus - 8) < 0.001)
        #expect(abs(day.mealBolus - 9) < 0.001)
        #expect(abs(day.mealDeviation - 1 / 14 * 100) < 0.001)
    }

    @Test("an override scales the meal plan too")
    func overrideScalesMealPlan() {
        let result = calculate(
            basalData: [basal(1, at: 0)],
            manualBoluses: [bolus(5.4, at: 13)],
            carbs: [carbs(40, at: 13)],
            overrides: [StatsOverride(start: hour(12.5), end: hour(13.5), insulinNeedsScaleFactor: 1.35)]
        )
        #expect(abs(result[.day]!.plannedMealBolus - 5.4) < 0.001)
        #expect(abs(result[.day]!.mealDeviation) < 0.001)
    }

    @Test("carbs without a bolus are an under-bolus; a bolus without carbs is left out")
    func unmatchedCarbsAndBoluses() {
        let result = calculate(
            basalData: [basal(1, at: 0)],
            manualBoluses: [bolus(2, at: 3)],
            carbs: [carbs(50, at: 19)]
        )
        #expect(result[.night]!.mealBolus == 0)
        #expect(result[.evening]!.mealBolus == 0)
        #expect(abs(result[.evening]!.plannedMealBolus - 5) < 0.001)
        #expect(abs(result[.average]!.variability + 5.0 / 29 * 100) < 0.001)
    }

    @Test("meals are skipped without a carb ratio")
    func noCarbRatio() {
        let result = calculate(
            basalData: [basal(1, at: 0)],
            manualBoluses: [bolus(5, at: 13)],
            carbs: [carbs(50, at: 13)],
            carbRatio: nil
        )
        #expect(result[.day]!.plannedMealBolus == 0)
        #expect(result[.day]!.mealBolus == 0)
    }
}
