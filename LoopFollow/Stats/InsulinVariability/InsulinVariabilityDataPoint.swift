// LoopFollow
// InsulinVariabilityDataPoint.swift

import Foundation

/// An override's span and how much it scaled insulin needs.
struct StatsOverride: Equatable {
    let start: TimeInterval
    let end: TimeInterval
    let insulinNeedsScaleFactor: Double
}

/// Insulin delivered against plan for one period, in units.
/// The plan is scheduled basal plus carbs / carb ratio, both scaled by any active override.
struct InsulinVariabilityDataPoint {
    let period: TIRPeriod
    let plannedBasal: Double // scheduled basal
    let deliveredBasal: Double // basal plus automatic boluses
    let plannedMealBolus: Double // carbs / carb ratio
    let mealBolus: Double // manual boluses given with those carbs

    var planned: Double { plannedBasal + plannedMealBolus }

    /// Basal and automatic bolus deviation, as % of the period's whole plan.
    var basalDeviation: Double { percentOfPlan(deliveredBasal - plannedBasal) }

    /// Meal over- or under-bolus, as % of the period's whole plan.
    var mealDeviation: Double { percentOfPlan(mealBolus - plannedMealBolus) }

    /// Delivered / planned - 1, as a %.
    var variability: Double { basalDeviation + mealDeviation }

    private func percentOfPlan(_ units: Double) -> Double {
        planned > 0 ? units / planned * 100 : 0
    }
}
