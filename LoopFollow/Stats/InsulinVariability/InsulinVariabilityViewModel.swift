// LoopFollow
// InsulinVariabilityViewModel.swift

import Combine
import Foundation

class InsulinVariabilityViewModel: ObservableObject {
    @Published var data: [InsulinVariabilityDataPoint] = []

    private let dataService: StatsDataService

    init(dataService: StatsDataService) {
        self.dataService = dataService
        calculate()
    }

    func calculate() {
        data = InsulinVariabilityCalculator.calculate(
            basalData: dataService.getBasalData(),
            basalProfile: dataService.getBasalProfile(),
            automaticBoluses: dataService.getSMBData(),
            manualBoluses: dataService.getBolusData(),
            carbs: dataService.getCarbData(),
            overrides: dataService.getOverrideData(),
            carbRatio: { ProfileManager.shared.carbRatio(at: $0) },
            startTime: dataService.startDate.timeIntervalSince1970,
            endTime: dataService.endDate.timeIntervalSince1970
        )
    }

    func clearStats() {
        data = []
    }
}
