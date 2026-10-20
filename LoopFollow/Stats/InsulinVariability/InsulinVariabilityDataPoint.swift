// LoopFollow
// InsulinVariabilityDataPoint.swift

import Foundation

/// An override's span and how much it scaled insulin needs.
struct StatsOverride: Equatable {
    let start: TimeInterval
    let end: TimeInterval
    let insulinNeedsScaleFactor: Double
}

/// The basal and carb ratio schedules of a profile, from the time it took effect.
struct StatsProfile {
    struct Entry {
        let timeAsSeconds: Double
        let value: Double
    }

    let start: TimeInterval
    let basal: [Entry]
    let carbRatio: [Entry]
    private let calendar: Calendar

    init(start: TimeInterval, timeZone: TimeZone, basal: [Entry], carbRatio: [Entry]) {
        self.start = start
        self.basal = basal.sorted { $0.timeAsSeconds < $1.timeAsSeconds }
        self.carbRatio = carbRatio.sorted { $0.timeAsSeconds < $1.timeAsSeconds }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// The profile's default store, or nil when it has no start date or no basal schedule.
    init?(_ profile: NSProfile) {
        guard let startString = profile.startDate ?? profile.createdAt,
              let start = NightscoutUtils.parseDate(startString),
              let store = profile.store[profile.defaultProfile] ?? profile.store["default"] ?? profile.store["Default"],
              !store.basal.isEmpty
        else { return nil }
        self.init(
            start: start.timeIntervalSince1970,
            timeZone: ProfileManager.getTimeZone(from: store.timezone),
            basal: store.basal.map { Entry(timeAsSeconds: $0.timeAsSeconds, value: $0.value) },
            carbRatio: store.carbratio.map { Entry(timeAsSeconds: $0.timeAsSeconds, value: $0.value) }
        )
    }

    func basalRate(at time: TimeInterval) -> Double? { value(in: basal, at: time) }

    func carbRatio(at time: TimeInterval) -> Double? { value(in: carbRatio, at: time) }

    /// Schedules are in the profile's own time zone, by wall-clock time of day.
    private func value(in schedule: [Entry], at time: TimeInterval) -> Double? {
        guard let first = schedule.first else { return nil }
        let date = Date(timeIntervalSince1970: time)
        let hours = calendar.component(.hour, from: date)
        let minutes = calendar.component(.minute, from: date)
        let seconds = Double(hours * 3600 + minutes * 60 + calendar.component(.second, from: date))
        return schedule.last { $0.timeAsSeconds <= seconds }?.value ?? first.value
    }
}

/// Insulin delivered against plan for one period, in units.
/// The plan is scheduled basal plus carbs / carb ratio, both scaled by any override passed to the calculator.
struct InsulinVariabilityDataPoint {
    let period: TIRPeriod
    let plannedBasal: Double // scheduled basal
    let deliveredBasal: Double // basal plus automatic boluses
    let plannedMealBolus: Double // carbs / carb ratio
    let mealBolus: Double // manual boluses given with those carbs
    let correctionBolus: Double // manual boluses with no carbs nearby, all above plan

    var planned: Double { plannedBasal + plannedMealBolus }

    /// Basal and automatic bolus deviation, as % of the period's whole plan.
    var basalDeviation: Double { percentOfPlan(deliveredBasal - plannedBasal) }

    /// Meal over- or under-bolus, as % of the period's whole plan.
    var mealDeviation: Double { percentOfPlan(mealBolus - plannedMealBolus) }

    /// Correction boluses, as % of the period's whole plan.
    var correctionDeviation: Double { percentOfPlan(correctionBolus) }

    /// Delivered / planned - 1, as a %.
    var variability: Double { basalDeviation + mealDeviation + correctionDeviation }

    private func percentOfPlan(_ units: Double) -> Double {
        planned > 0 ? units / planned * 100 : 0
    }
}
