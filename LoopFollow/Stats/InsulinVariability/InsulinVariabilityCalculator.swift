// LoopFollow
// InsulinVariabilityCalculator.swift

import Foundation

class InsulinVariabilityCalculator {
    /// Carb entries this close together count as one meal, and boluses this
    /// close to a meal's carbs count as that meal's bolus.
    static let mealWindow: TimeInterval = 30 * 60

    private static let periods: [TIRPeriod] = [.night, .morning, .day, .evening]

    static func calculate(
        basalData: [MainViewController.basalGraphStruct],
        profiles: [StatsProfile],
        automaticBoluses: [MainViewController.bolusGraphStruct],
        manualBoluses: [MainViewController.bolusGraphStruct],
        carbs: [MainViewController.carbGraphStruct],
        overrides: [StatsOverride],
        startTime: TimeInterval,
        endTime: TimeInterval,
        calendar: Calendar = dateTimeUtils.displayCalendar()
    ) -> [InsulinVariabilityDataPoint] {
        guard !basalData.isEmpty, !profiles.isEmpty else { return [] }
        let profiles = profiles.sorted { $0.start < $1.start }

        var totals: [TIRPeriod: Totals] = [:]
        func add(at time: TimeInterval, _ update: (inout Totals) -> Void) {
            guard let period = period(at: time, calendar: calendar) else { return }
            update(&totals[period, default: Totals()])
        }

        func scaleFactor(at time: TimeInterval) -> Double {
            overrides.last { $0.start <= time && time < $0.end }?.insulinNeedsScaleFactor ?? 1
        }

        // The profile in effect at a time; the earliest one also covers anything before it.
        func profile(at time: TimeInterval) -> StatsProfile {
            profiles.last { $0.start <= time } ?? profiles[0]
        }

        // Basal, sampled every 5 minutes against the override-scaled schedule.
        let sampleInterval: TimeInterval = 5 * 60
        var basalIndex = 0
        var t = startTime
        while t < endTime {
            while basalIndex < basalData.count - 1, basalData[basalIndex + 1].date <= t {
                basalIndex += 1
            }
            let scheduledRate = profile(at: t).basalRate(at: t) ?? 0
            let hours = min(sampleInterval, endTime - t) / 3600
            let planned = scheduledRate * scaleFactor(at: t) * hours
            let delivered = basalData[basalIndex].basalRate * hours
            add(at: t) {
                $0.plannedBasal += planned
                $0.deliveredBasal += delivered
            }
            t += sampleInterval
        }

        for bolus in automaticBoluses where bolus.date >= startTime && bolus.date < endTime {
            add(at: bolus.date) { $0.deliveredBasal += bolus.value }
        }

        // Meals: each one's boluses against its carbs / carb ratio. Boluses
        // with no meal nearby are corrections, all of them above plan.
        let meals = groupMeals(carbs: carbs.filter { $0.value > 0 && $0.date >= startTime && $0.date < endTime })
        var mealBoluses = Array(repeating: 0.0, count: meals.count)
        for bolus in manualBoluses {
            let nearest = meals.indices
                .filter { meals[$0].first - mealWindow <= bolus.date && bolus.date <= meals[$0].last + mealWindow }
                .min { meals[$0].distance(to: bolus.date) < meals[$1].distance(to: bolus.date) }
            if let nearest {
                mealBoluses[nearest] += bolus.value
            } else if bolus.date >= startTime, bolus.date < endTime {
                add(at: bolus.date) { $0.correctionBolus += bolus.value }
            }
        }
        for (meal, bolus) in zip(meals, mealBoluses) {
            var planned = 0.0
            var hasRatio = true
            for carb in meal.carbs {
                guard let ratio = profile(at: carb.date).carbRatio(at: carb.date), ratio > 0 else {
                    hasRatio = false
                    break
                }
                planned += carb.value / ratio * scaleFactor(at: carb.date)
            }
            guard hasRatio else { continue }
            add(at: meal.first) {
                $0.plannedMealBolus += planned
                $0.mealBolus += bolus
            }
        }

        var result = periods.map { totals[$0, default: Totals()].dataPoint(period: $0) }
        let all = periods.reduce(into: Totals()) { $0.add(totals[$1, default: Totals()]) }
        result.append(all.dataPoint(period: .average))
        return result
    }

    private struct Totals {
        var plannedBasal = 0.0
        var deliveredBasal = 0.0
        var plannedMealBolus = 0.0
        var mealBolus = 0.0
        var correctionBolus = 0.0

        mutating func add(_ other: Totals) {
            plannedBasal += other.plannedBasal
            deliveredBasal += other.deliveredBasal
            plannedMealBolus += other.plannedMealBolus
            mealBolus += other.mealBolus
            correctionBolus += other.correctionBolus
        }

        func dataPoint(period: TIRPeriod) -> InsulinVariabilityDataPoint {
            InsulinVariabilityDataPoint(
                period: period,
                plannedBasal: plannedBasal,
                deliveredBasal: deliveredBasal,
                plannedMealBolus: plannedMealBolus,
                mealBolus: mealBolus,
                correctionBolus: correctionBolus
            )
        }
    }

    private struct Meal {
        var carbs: [MainViewController.carbGraphStruct]
        var first: TimeInterval { carbs[0].date }

        var last: TimeInterval { carbs[carbs.count - 1].date }

        func distance(to time: TimeInterval) -> TimeInterval {
            carbs.map { abs($0.date - time) }.min() ?? .infinity
        }
    }

    private static func groupMeals(carbs: [MainViewController.carbGraphStruct]) -> [Meal] {
        var meals: [Meal] = []
        for carb in carbs.sorted(by: { $0.date < $1.date }) {
            if let last = meals.last, carb.date - last.last <= mealWindow {
                meals[meals.count - 1].carbs.append(carb)
            } else {
                meals.append(Meal(carbs: [carb]))
            }
        }
        return meals
    }

    private static func period(at time: TimeInterval, calendar: Calendar) -> TIRPeriod? {
        let hour = calendar.component(.hour, from: Date(timeIntervalSince1970: time))
        return periods.first { period in
            guard let range = period.hourRange else { return false }
            return hour >= range.start && hour < range.end
        }
    }
}
