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

    private func profile(from start: TimeInterval = 0, basal: Double, carbRatio: Double?) -> StatsProfile {
        StatsProfile(
            start: start,
            timeZone: calendar.timeZone,
            basal: [.init(timeAsSeconds: 0, value: basal)],
            carbRatio: carbRatio.map { [.init(timeAsSeconds: 0, value: $0)] } ?? []
        )
    }

    private func calculate(
        basalData: [MainViewController.basalGraphStruct],
        automaticBoluses: [MainViewController.bolusGraphStruct] = [],
        manualBoluses: [MainViewController.bolusGraphStruct] = [],
        carbs: [MainViewController.carbGraphStruct] = [],
        overrides: [StatsOverride] = [],
        carbRatio: Double? = 10,
        profiles: [StatsProfile]? = nil
    ) -> [TIRPeriod: InsulinVariabilityDataPoint] {
        let points = InsulinVariabilityCalculator.calculate(
            basalData: basalData,
            profiles: profiles ?? [profile(basal: 1, carbRatio: carbRatio)],
            automaticBoluses: automaticBoluses,
            manualBoluses: manualBoluses,
            carbs: carbs,
            overrides: overrides,
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

    @Test("without override adjustment, what an override adds shows as variability")
    func unadjustedShowsOverride() {
        // 1 U/h scheduled, Loop delivering 1.35 U/h under a 35% override.
        let result = calculate(basalData: [basal(1, at: 0), basal(1.35, at: 6), basal(1, at: 12)])
        #expect(abs(result[.morning]!.plannedBasal - 6) < 0.001)
        #expect(abs(result[.morning]!.variability - 35) < 0.001)
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

    @Test("carbs without a bolus are an under-bolus; a bolus without carbs is a correction")
    func unmatchedCarbsAndBoluses() {
        let result = calculate(
            basalData: [basal(1, at: 0)],
            manualBoluses: [bolus(2, at: 3)],
            carbs: [carbs(50, at: 19)]
        )
        #expect(result[.night]!.mealBolus == 0)
        #expect(abs(result[.night]!.correctionBolus - 2) < 0.001)
        #expect(result[.evening]!.mealBolus == 0)
        #expect(abs(result[.evening]!.plannedMealBolus - 5) < 0.001)
        // 24 U basal + 5 U meal planned; 24 U basal + 2 U correction delivered.
        #expect(abs(result[.average]!.correctionDeviation - 2.0 / 29 * 100) < 0.001)
        #expect(abs(result[.average]!.variability + 3.0 / 29 * 100) < 0.001)
    }

    @Test("a bolus just outside a meal's window is a correction")
    func correctionNearMeal() {
        let result = calculate(
            basalData: [basal(1, at: 0)],
            manualBoluses: [bolus(4, at: 13), bolus(1, at: 14)],
            carbs: [carbs(40, at: 13)]
        )
        #expect(abs(result[.day]!.mealBolus - 4) < 0.001)
        #expect(abs(result[.day]!.correctionBolus - 1) < 0.001)
    }

    @Test("each time is measured against the profile in effect then")
    func profileHistory() {
        // Basal raised from 1 to 2 U/h and carb ratio from 1:10 to 1:5 at noon.
        let result = calculate(
            basalData: [basal(1, at: 0), basal(2, at: 12)],
            manualBoluses: [bolus(4, at: 8), bolus(8, at: 13)],
            carbs: [carbs(40, at: 8), carbs(40, at: 13)],
            profiles: [profile(from: hour(12), basal: 2, carbRatio: 5), profile(basal: 1, carbRatio: 10)]
        )
        #expect(abs(result[.morning]!.plannedBasal - 6) < 0.001)
        #expect(abs(result[.morning]!.plannedMealBolus - 4) < 0.001)
        #expect(abs(result[.day]!.plannedBasal - 12) < 0.001)
        #expect(abs(result[.day]!.plannedMealBolus - 8) < 0.001)
        #expect(abs(result[.average]!.variability) < 0.001)
    }

    @Test("an override that started before the range scales the plan from the start")
    func overrideFromBeforeRange() {
        let result = calculate(
            basalData: [basal(1.35, at: 0), basal(1, at: 6)],
            overrides: [StatsOverride(start: day - 3 * 24 * 3600, end: hour(6), insulinNeedsScaleFactor: 1.35)]
        )
        #expect(abs(result[.night]!.plannedBasal - 8.1) < 0.001)
        #expect(abs(result[.night]!.variability) < 0.001)
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
