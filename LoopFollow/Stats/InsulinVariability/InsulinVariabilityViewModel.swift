// LoopFollow
// InsulinVariabilityViewModel.swift

import Combine
import Foundation

class InsulinVariabilityViewModel: ObservableObject {
    @Published var data: [InsulinVariabilityDataPoint] = []
    @Published var hourlyData: [AGPDataPoint] = []
    /// Scale the plan by active overrides, so insulin an override adds or removes is on plan.
    @Published var overrideAdjusted = Storage.shared.insulinVariabilityOverrideAdjusted.value

    private let dataService: StatsDataService

    init(dataService: StatsDataService) {
        self.dataService = dataService
        calculate()
    }

    func calculate() {
        let basalData = dataService.getBasalData()
        let profiles = profiles()
        let automaticBoluses = dataService.getSMBData()
        let manualBoluses = dataService.getBolusData()
        let carbs = dataService.getCarbData()
        let overrides = overrideAdjusted ? dataService.getOverrideData() : []
        let startTime = dataService.startDate.timeIntervalSince1970
        let endTime = dataService.endDate.timeIntervalSince1970

        data = InsulinVariabilityCalculator.calculate(
            basalData: basalData,
            profiles: profiles,
            automaticBoluses: automaticBoluses,
            manualBoluses: manualBoluses,
            carbs: carbs,
            overrides: overrides,
            startTime: startTime,
            endTime: endTime
        )
        hourlyData = InsulinVariabilityCalculator.calculateHourly(
            basalData: basalData,
            profiles: profiles,
            automaticBoluses: automaticBoluses,
            manualBoluses: manualBoluses,
            carbs: carbs,
            overrides: overrides,
            startTime: startTime,
            endTime: endTime
        )
    }

    /// The profiles in effect over the range, or the current one when the history couldn't be fetched.
    private func profiles() -> [StatsProfile] {
        let history = dataService.getProfileData()
        if !history.isEmpty { return history }
        let basal = dataService.getBasalProfile()
        guard !basal.isEmpty else { return [] }
        let profile = ProfileManager.shared
        return [StatsProfile(
            start: 0,
            timeZone: profile.timezone,
            basal: basal.map { StatsProfile.Entry(timeAsSeconds: $0.timeAsSeconds, value: $0.value) },
            carbRatio: profile.carbRatioSchedule.map { StatsProfile.Entry(timeAsSeconds: Double($0.timeAsSeconds), value: $0.value) }
        )]
    }

    func toggleOverrideAdjusted() {
        overrideAdjusted.toggle()
        Storage.shared.insulinVariabilityOverrideAdjusted.value = overrideAdjusted
        calculate()
    }

    func clearStats() {
        data = []
        hourlyData = []
    }
}
